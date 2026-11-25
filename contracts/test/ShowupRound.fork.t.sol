// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ClonesUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {LibString} from "solady/utils/LibString.sol";

import {IPortal} from "src/flap/IPortal.sol";
import {CheckInLauncher, RoundConfig} from "src/CheckInLauncher.sol";
import {CheckInLauncherFactory} from "src/CheckInLauncherFactory.sol";
import {StreakVault} from "src/StreakVault.sol";
import {StreakVaultFactory} from "src/StreakVaultFactory.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IRouterLike {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface ITaxTokenLike {
    function taxProcessor() external view returns (address);
}

interface ITaxProcessorLike {
    function dispatch() external;
    function feeQuoteBalance() external view returns (uint256);
    function marketQuoteBalance() external view returns (uint256);
}

/// @notice A whole round against the LIVE Portal on BNB Testnet (chain 97), nothing mocked and nothing
///         changed on the Portal: no admin prank, no factory enabling. It is what a deployment today
///         would see. Needs `BSC_TESTNET_RPC_URL`; skipped without it.
///
/// @dev Adapted from `test/ForkBase.sol` and `test/launcher-vault/Crowd.fork.t.sol` of Flap's example repo.
contract ShowupRoundForkTest is Test {
    // BNB Testnet addresses (see Flap's ForkAddresses / the README).
    address internal constant PORTAL = 0x000042108465206185A077Edc3F3fd2b49060000;
    address internal constant GUARDIAN = 0x00004d58290854c5E9880F4b5B1993c6Ad8b0000;
    address internal constant TOKEN_IMPL = 0x7777c57ff7dc441c1715b2e36fa581c48B782222;
    address internal constant V2_ROUTER = 0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3;
    /// @dev Flap's test "USD": 18 decimals, anyone can mint, enabled as a quote token at $1.
    address internal constant USD = 0x190C989D5665a0e404B444b53CAE9AbCfb600157;

    uint256 internal constant DEPOSIT = 1000 ether;
    uint256 internal constant LIQUIDITY_BPS = 3000;
    uint256 internal constant GOAL = 6;
    /// @dev What the sponsor adds so the pool reaches the Portal's floor: 3 x 1000 x 30% = 900, + 600 = 1500.
    uint256 internal constant SPONSORED = 600 ether;
    uint256 internal constant POOL_QUOTE = 1500 ether;
    uint256 internal constant PRIZE = 2100 ether;
    uint256 internal constant RESERVE = 500_000 ether;

    uint256 internal constant ATTESTER_KEY = 0xA77E57E2;
    /// @dev What the live Portal answers when the pool's quote is below its liquidity floor: a custom
    ///      error with this selector and two words, (poolQuote offered, floor required). Its name is not
    ///      in the interface subset Flap publishes. Today the floor is 1,500 USD for half the supply.
    bytes4 internal constant PORTAL_BELOW_FLOOR = 0xa32ef056;
    uint256 internal constant PORTAL_FLOOR = 1500 ether;

    IPortal internal portal = IPortal(PORTAL);
    CheckInLauncherFactory internal launcherFactory;
    StreakVaultFactory internal vaultFactory;

    // Plain addresses with no code on chain (see the note in Flap's ForkBase about `makeAddr`).
    address internal creator = address(uint160(0xC0DE0001));
    address internal alice = address(uint160(0xC0DE0002));
    address internal bob = address(uint160(0xC0DE0003));
    address internal carol = address(uint160(0xC0DE0004));
    address internal trader = address(uint160(0xC0DE0005));
    address internal sponsorWallet = address(uint160(0xC0DE0006));
    address internal stranger = address(uint160(0xC0DE0007));
    address internal attester;

    uint256 internal deadline;

    function setUp() public {
        string memory rpcUrl = vm.envOr("BSC_TESTNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpcUrl);
        require(block.chainid == 97, "BSC_TESTNET_RPC_URL is not BNB Testnet");
        // The live gate this build relies on: creation is not paused, so a factory needs no enabling.
        require(portal.featureFlags() & 1 == 0, "testnet creation is paused: Flap must enable the factory");
        attester = vm.addr(ATTESTER_KEY);

        // The two factories name each other, so the Launcher factory's address is predicted first.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        vaultFactory = new StreakVaultFactory(predicted);
        launcherFactory = new CheckInLauncherFactory(PORTAL, GUARDIAN, address(vaultFactory), USD);
        assertEq(address(launcherFactory), predicted, "address prediction held");

        (bool enabled,) = portal.launcherFactoryMultiplier(address(launcherFactory));
        assertFalse(enabled, "the factory is NOT enabled by Flap; the test runs on the open testnet gate");

        deadline = block.timestamp + 14 days;
        vm.deal(creator, 1 ether);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Helpers
    // ═════════════════════════════════════════════════════════════════════════

    /// @dev A salt whose predicted token address ends in 0x7777, which the Portal requires.
    function _mineSalt(bytes32 seed) internal pure returns (bytes32 salt) {
        for (uint256 i;; ++i) {
            assembly ("memory-safe") {
                mstore(0x00, seed)
                mstore(0x20, i)
                salt := keccak256(0x00, 0x40)
            }
            if (uint16(uint160(ClonesUpgradeable.predictDeterministicAddress(TOKEN_IMPL, salt, PORTAL))) == 0x7777) {
                return salt;
            }
        }
    }

    function _config(bytes32 seed) internal view returns (RoundConfig memory c) {
        c.name = "Morning Movers Round 1";
        c.symbol = "MOVEX";
        c.meta = "bafkreig4y5nwb4izyilbbmiydumvkld446d4k7j4ohg3x3q2lfel3fo4yq";
        c.salt = _mineSalt(seed);
        c.deposit = DEPOSIT;
        c.liquidityBps = LIQUIDITY_BPS;
        c.checkInGoal = GOAL;
        c.deadline = deadline;
        c.attester = attester;
    }

    /// @dev The creator opens a round through the Portal, paying the salt-lock fee.
    function _openRound(bytes32 seed) internal returns (CheckInLauncher launcher) {
        uint256 fee = portal.SALT_LOCK_FEE();
        bytes memory data = abi.encode(_config(seed));
        vm.prank(creator);
        uint256 gasBefore = gasleft();
        launcher = CheckInLauncher(portal.newLauncher{value: fee}(address(launcherFactory), data));
        emit log_named_uint("gas used by Portal.newLauncher", gasBefore - gasleft());
    }

    /// @dev A member mints test USD, approves the Launcher and joins.
    function _join(CheckInLauncher launcher, address member) internal {
        IMintable(USD).mint(member, DEPOSIT);
        vm.startPrank(member);
        IERC20(USD).approve(address(launcher), DEPOSIT);
        launcher.join();
        vm.stopPrank();
    }

    function _sponsor(CheckInLauncher launcher, uint256 amount) internal {
        IMintable(USD).mint(sponsorWallet, amount);
        vm.startPrank(sponsorWallet);
        IERC20(USD).approve(address(launcher), amount);
        launcher.sponsor(amount);
        vm.stopPrank();
    }

    function _today() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @dev What the attester's server does: personal_sign over
    ///      keccak256(abi.encode(chainId, launcher, wallet, day)).
    function _sign(uint256 key, CheckInLauncher launcher, address wallet, uint256 day)
        internal
        pure
        returns (bytes memory)
    {
        bytes32 inner = keccak256(abi.encode(uint256(97), address(launcher), wallet, day));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(key, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner)));
        return abi.encodePacked(r, s, v);
    }

    function _checkIn(CheckInLauncher launcher, address member, uint256 day) internal {
        bytes memory sig = _sign(ATTESTER_KEY, launcher, member, day);
        vm.prank(member);
        launcher.checkIn(day, sig);
    }

    function _swap(address from, address to, uint256 amountIn) internal {
        IERC20(from).approve(V2_ROUTER, amountIn);
        address[] memory path = new address[](2);
        path[0] = from;
        path[1] = to;
        IRouterLike(V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 0, path, trader, block.timestamp + 600);
    }

    function _taxLiquidated(address proc) internal view returns (bool) {
        return ITaxProcessorLike(proc).feeQuoteBalance() > 0 || ITaxProcessorLike(proc).marketQuoteBalance() > 0;
    }

    /// @dev Trade on the real pool until the token's tax has been sold into quote, then dispatch it.
    function _generateTaxAndDispatch(address token) internal {
        address proc = ITaxTokenLike(token).taxProcessor();
        IMintable(USD).mint(trader, 1000 ether);
        vm.startPrank(trader);
        _swap(USD, token, 1000 ether);
        uint256 rounds;
        for (; rounds < 80 && !_taxLiquidated(proc); ++rounds) {
            _swap(token, USD, IERC20(token).balanceOf(trader) * 30 / 100);
            _swap(USD, token, IERC20(USD).balanceOf(trader) * 90 / 100);
        }
        vm.stopPrank();
        emit log_named_uint("sell/buy rounds after the first 1000 USD buy", rounds);
        assertTrue(_taxLiquidated(proc), "tax never liquidated within the round budget");
        ITaxProcessorLike(proc).dispatch();
    }

    /// @dev Three members over two simulated days: alice 3 check-ins, bob 2, carol 1. The bar is full.
    function _joinAndFillTheBar(CheckInLauncher launcher) internal {
        _join(launcher, alice);
        _join(launcher, bob);
        _join(launcher, carol);
        uint256 d = _today();
        _checkIn(launcher, alice, d - 1);
        _checkIn(launcher, alice, d);
        _checkIn(launcher, bob, d);
        _checkIn(launcher, carol, d);
        vm.warp(block.timestamp + 1 days);
        _checkIn(launcher, alice, d + 1);
        _checkIn(launcher, bob, d + 1);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Tests
    // ═════════════════════════════════════════════════════════════════════════

    function test_fullJourney_joinCheckInLaunchTaxClaim() public {
        // 1. The creator opens the round through the Portal. No factory enabling.
        vm.recordLogs();
        CheckInLauncher launcher = _openRound("journey");
        _assertThePortalPublishedOurDescription(launcher, vm.getRecordedLogs());
        assertEq(
            portal.getLauncher(address(launcher)).launcherFactory,
            address(launcherFactory),
            "Portal recorded the Launcher"
        );
        assertEq(launcher.deposit(), DEPOSIT);
        assertEq(launcher.liquidityBps(), LIQUIDITY_BPS);
        assertEq(launcher.checkInGoal(), GOAL);
        assertEq(launcher.deadline(), deadline);
        assertEq(launcher.attester(), attester);
        assertEq(launcher.creator(), creator);

        // 2. Three members join by paying the deposit. A second join from the same address reverts.
        _join(launcher, alice);
        _join(launcher, bob);
        _join(launcher, carol);
        assertEq(launcher.memberCount(), 3);
        assertEq(launcher.totalDeposits(), 3 * DEPOSIT);
        assertEq(IERC20(USD).balanceOf(address(launcher)), 3 * DEPOSIT);
        IMintable(USD).mint(alice, DEPOSIT);
        vm.startPrank(alice);
        IERC20(USD).approve(address(launcher), DEPOSIT);
        vm.expectRevert(CheckInLauncher.AlreadyMember.selector);
        launcher.join();
        vm.stopPrank();

        // 3. Day one. Check-ins need the attester's signature and a member's wallet.
        uint256 day1 = _today();
        bytes memory forged = _sign(0xBADBAD, launcher, alice, day1);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        launcher.checkIn(day1, forged);
        bytes memory forStranger = _sign(ATTESTER_KEY, launcher, stranger, day1);
        vm.prank(stranger);
        vm.expectRevert(CheckInLauncher.NotMember.selector);
        launcher.checkIn(day1, forStranger);

        _checkIn(launcher, alice, day1 - 1); // yesterday is still accepted
        _checkIn(launcher, alice, day1);
        _checkIn(launcher, bob, day1);
        _checkIn(launcher, carol, day1);
        assertEq(launcher.totalCheckIns(), 4);
        bytes memory again = _sign(ATTESTER_KEY, launcher, carol, day1);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.AlreadyCheckedIn.selector, day1));
        launcher.checkIn(day1, again);

        // The bar is not full: nobody can launch, the attester included.
        vm.prank(attester);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.GoalNotReached.selector, 4, GOAL));
        launcher.launch();

        // 4. Day two: two more check-ins fill the bar.
        vm.warp(block.timestamp + 1 days);
        _checkIn(launcher, alice, day1 + 1);
        _checkIn(launcher, bob, day1 + 1);
        assertEq(launcher.totalCheckIns(), GOAL);
        assertEq(launcher.daysOf(alice), 3);
        assertEq(launcher.daysOf(bob), 2);
        assertEq(launcher.daysOf(carol), 1);

        // 5. The bar is full, but 30% of the deposits (900 USD) is below Flap's liquidity floor: the
        //    Portal reverts the launch and nothing changes.
        assertEq(launcher.poolQuoteNow(), 900 ether);
        assertTrue(launcher.canLaunch());
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PORTAL_BELOW_FLOOR, 900 ether, PORTAL_FLOOR));
        launcher.launch();
        assertFalse(launcher.launched());
        assertEq(IERC20(USD).balanceOf(address(launcher)), 3 * DEPOSIT);

        // A sponsor tops the pool up. Sponsor money earns nothing.
        _sponsor(launcher, SPONSORED);
        assertEq(launcher.poolQuoteNow(), POOL_QUOTE);
        assertEq(launcher.prizeQuoteNow(), PRIZE);

        // 6. Anyone launches: here a wallet with no role and no deposit. This is the real Flap launch.
        vm.prank(stranger);
        uint256 gasBefore = gasleft();
        launcher.launch();
        emit log_named_uint("gas used by launch()", gasBefore - gasleft());
        assertTrue(launcher.launched(), "launched by a wallet with no role");
        vm.expectRevert(CheckInLauncher.AlreadyLaunched.selector);
        launcher.launch();

        address token = launcher.token();
        StreakVault vault = StreakVault(launcher.vault());
        (address recordedVault, address recordedFactory) = portal.getLaunchVault(token);
        assertEq(recordedVault, address(vault), "the Portal recorded the same vault");
        assertEq(recordedFactory, address(vaultFactory), "the vault came from the paired factory");
        assertEq(uint16(uint160(token)), 0x7777, "the token address ends in 7777");
        assertEq(IERC20(token).totalSupply(), launcher.TOTAL_SUPPLY());
        assertEq(IERC20(token).balanceOf(launcher.pool()), launcher.POOL_TOKEN(), "half the supply is in the pool");
        assertEq(IERC20(USD).balanceOf(launcher.pool()), POOL_QUOTE, "sponsor money + 30% of deposits is the pool");
        assertEq(IERC20(token).balanceOf(address(vault)), RESERVE, "the other half is in the vault");
        assertEq(IERC20(USD).balanceOf(address(vault)), PRIZE, "the prize is in the vault");
        assertEq(IERC20(USD).balanceOf(address(launcher)), 0, "the Launcher holds nothing after the launch");
        assertEq(launcher.prizeQuote(), PRIZE);
        assertEq(vault.launcher(), address(launcher));
        assertEq(vault.totalCheckIns(), GOAL);
        assertEq(vault.reservedTokens(), RESERVE);
        assertEq(vault.quoteReceived(), PRIZE);
        assertGt(bytes(vault.description()).length, 0);

        // The round is closed: no join, no sponsor, no check-in, no refund.
        vm.prank(trader);
        vm.expectRevert(CheckInLauncher.RoundClosed.selector);
        launcher.join();
        bytes memory late = _sign(ATTESTER_KEY, launcher, carol, day1 + 1);
        vm.prank(carol);
        vm.expectRevert(CheckInLauncher.CheckInsClosed.selector);
        launcher.checkIn(day1 + 1, late);

        // 7. alice claims straight away: half the tokens and half the prize (3 of 6 days).
        vm.prank(alice);
        vault.claim();
        assertEq(IERC20(token).balanceOf(alice), RESERVE / 2, "alice: 3/6 of the reserve");
        assertEq(IERC20(USD).balanceOf(alice), DEPOSIT + PRIZE / 2, "alice: 3/6 of the prize (plus her unused mint)");

        // 8. Real trading on the pool; the vault's share of the tax arrives in USD.
        _generateTaxAndDispatch(token);
        uint256 tax = IERC20(USD).balanceOf(address(vault)) + vault.totalQuotePaid() - PRIZE;
        assertGt(tax, 0, "trading tax reached the vault");
        assertEq(vault.quoteReceived(), PRIZE + tax);
        emit log_named_decimal_uint("trading tax that reached the vault (USD)", tax, 18);

        // 9. alice claims again for the tax; bob and carol claim everything in one go.
        (uint256 aliceTokens, uint256 aliceQuote) = vault.claimable(alice);
        assertEq(aliceTokens, 0, "tokens are paid once");
        assertEq(aliceQuote, (PRIZE + tax) * 3 / 6 - PRIZE / 2);
        vm.prank(alice);
        vault.claim();
        vm.prank(bob);
        vault.claim();
        vm.prank(carol);
        vault.claim();
        assertEq(IERC20(USD).balanceOf(alice), DEPOSIT + (PRIZE + tax) * 3 / 6, "alice: 3/6 of prize and tax");
        assertEq(IERC20(USD).balanceOf(bob), (PRIZE + tax) * 2 / 6, "bob: 2/6 of prize and tax");
        assertEq(IERC20(USD).balanceOf(carol), (PRIZE + tax) * 1 / 6, "carol: 1/6 of prize and tax");
        assertEq(IERC20(token).balanceOf(bob), RESERVE * 2 / 6, "bob: 2/6 of the reserve");
        assertEq(IERC20(token).balanceOf(carol), RESERVE * 1 / 6, "carol: 1/6 of the reserve");
        assertLt(IERC20(USD).balanceOf(address(vault)), 3, "only rounding dust is left in USD");
        assertLt(IERC20(token).balanceOf(address(vault)), 3, "only rounding dust is left in tokens");
        emit log_named_decimal_uint("alice received (USD), deposit was 1000", (PRIZE + tax) * 3 / 6, 18);
        emit log_named_decimal_uint("bob received (USD), deposit was 1000", (PRIZE + tax) * 2 / 6, 18);
        emit log_named_decimal_uint("carol received (USD), deposit was 1000", (PRIZE + tax) * 1 / 6, 18);

        // 10. Nobody else is paid: not the sponsor, the creator, the attester or the launcher's caller.
        address[4] memory others = [sponsorWallet, creator, attester, stranger];
        for (uint256 i; i < others.length; ++i) {
            vm.prank(others[i]);
            vm.expectRevert(StreakVault.NothingToClaim.selector);
            vault.claim();
        }
        vm.warp(deadline + 1);
        vm.prank(sponsorWallet);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund();
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund();
    }

    /// @dev The Portal reads `description()` when the Launcher is created and publishes it in its own
    ///      event, unless it is malformed or too long. Check that ours got through.
    function _assertThePortalPublishedOurDescription(CheckInLauncher launcher, Vm.Log[] memory logs) internal {
        string memory expected = launcher.description();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != PORTAL) continue;
            if (LibString.contains(string(logs[i].data), expected)) found = true;
        }
        emit log_named_uint("launcher description length (bytes)", bytes(expected).length);
        assertTrue(found, "the Portal's creation event carries the Launcher's description");
    }

    function test_refund_whenTheBarNeverFills() public {
        CheckInLauncher launcher = _openRound("refund");
        _join(launcher, alice);
        _join(launcher, bob);
        _sponsor(launcher, SPONSORED);
        _checkIn(launcher, alice, _today());
        _checkIn(launcher, bob, _today());

        // Not before the deadline.
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund();

        vm.warp(deadline + 1);
        // Too late to launch, join or check in.
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.GoalNotReached.selector, 2, GOAL));
        launcher.launch();
        vm.prank(carol);
        vm.expectRevert(CheckInLauncher.RoundClosed.selector);
        launcher.join();
        // Someone who paid nothing has nothing to take.
        vm.prank(carol);
        vm.expectRevert(CheckInLauncher.NothingToRefund.selector);
        launcher.refund();

        vm.prank(alice);
        launcher.refund();
        vm.prank(bob);
        launcher.refund();
        vm.prank(sponsorWallet);
        launcher.refund();
        assertEq(IERC20(USD).balanceOf(alice), DEPOSIT, "alice got her full deposit back");
        assertEq(IERC20(USD).balanceOf(bob), DEPOSIT, "bob got his full deposit back");
        assertEq(IERC20(USD).balanceOf(sponsorWallet), SPONSORED, "the sponsor got the contribution back");
        assertEq(IERC20(USD).balanceOf(address(launcher)), 0);
        assertEq(launcher.memberCount(), 0);
        assertFalse(launcher.launched());
        assertEq(launcher.token(), address(0), "no token was ever created");

        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.NothingToRefund.selector);
        launcher.refund(); // only once
    }

    function test_refund_whenTheBarIsFullButThePoolNeverReachesTheFloor() public {
        CheckInLauncher launcher = _openRound("no-sponsor");
        _joinAndFillTheBar(launcher);
        assertEq(launcher.totalCheckIns(), GOAL);

        // 900 USD for the pool: the Portal refuses, every time, and no sponsor shows up.
        vm.expectRevert(abi.encodeWithSelector(PORTAL_BELOW_FLOOR, 900 ether, PORTAL_FLOOR));
        launcher.launch();
        vm.warp(deadline);
        vm.expectRevert(abi.encodeWithSelector(PORTAL_BELOW_FLOOR, 900 ether, PORTAL_FLOOR));
        launcher.launch();

        vm.warp(deadline + 1);
        vm.expectRevert(CheckInLauncher.LaunchClosed.selector);
        launcher.launch();
        vm.prank(alice);
        launcher.refund();
        vm.prank(bob);
        launcher.refund();
        vm.prank(carol);
        launcher.refund();
        assertEq(IERC20(USD).balanceOf(alice), DEPOSIT);
        assertEq(IERC20(USD).balanceOf(bob), DEPOSIT);
        assertEq(IERC20(USD).balanceOf(carol), DEPOSIT);
        assertEq(IERC20(USD).balanceOf(address(launcher)), 0);
    }

    function test_launch_atTheDeadlineStillLaunches() public {
        CheckInLauncher launcher = _openRound("last-second");
        _joinAndFillTheBar(launcher);
        _sponsor(launcher, SPONSORED);

        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund(); // refunds only open after the deadline
        vm.prank(stranger);
        launcher.launch();
        assertTrue(launcher.launched());
        assertEq(IERC20(USD).balanceOf(launcher.vault()), PRIZE);
        assertEq(StreakVault(launcher.vault()).totalCheckIns(), GOAL);
    }

    function test_factory_rejectsBadRoundConfigs() public {
        uint256 fee = portal.SALT_LOCK_FEE();
        RoundConfig memory c = _config("bad-config");

        c.deposit = 0;
        vm.prank(creator);
        vm.expectRevert(CheckInLauncherFactory.InvalidDeposit.selector);
        portal.newLauncher{value: fee}(address(launcherFactory), abi.encode(c));

        c = _config("bad-config");
        c.liquidityBps = 10_001;
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncherFactory.InvalidLiquidityBps.selector, 10_001));
        portal.newLauncher{value: fee}(address(launcherFactory), abi.encode(c));

        c = _config("bad-config");
        c.checkInGoal = 0;
        vm.prank(creator);
        vm.expectRevert(CheckInLauncherFactory.InvalidCheckInGoal.selector);
        portal.newLauncher{value: fee}(address(launcherFactory), abi.encode(c));

        c = _config("bad-config");
        c.deadline = block.timestamp;
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncherFactory.InvalidDeadline.selector, c.deadline));
        portal.newLauncher{value: fee}(address(launcherFactory), abi.encode(c));

        c = _config("bad-config");
        c.attester = address(0);
        vm.prank(creator);
        vm.expectRevert(CheckInLauncherFactory.ZeroAddress.selector);
        portal.newLauncher{value: fee}(address(launcherFactory), abi.encode(c));
    }
}
