// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibString} from "solady/utils/LibString.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";

import {DirectLaunchVaultBase} from "src/flap/DirectLaunchVaultBase.sol";
import {DirectLaunchVaultFactoryBase} from "src/flap/DirectLaunchVaultFactoryBase.sol";
import {VaultUISchema} from "src/flap/IVaultSchemas.sol";
import {CheckInLauncher, RoundConfig} from "src/CheckInLauncher.sol";
import {CheckInLauncherFactory} from "src/CheckInLauncherFactory.sol";
import {StreakVault} from "src/StreakVault.sol";
import {StreakVaultFactory} from "src/StreakVaultFactory.sol";
import {PRODUCT_NAME} from "src/Product.sol";
import {RoundBase, MockErc20} from "test/RoundBase.sol";

/// @dev The views of CheckInLauncher that StreakVault reads, for the tests that build a vault by hand.
contract MockLauncher {
    address public quoteToken;
    address public attester = address(0xA77E);
    uint256 public totalCheckIns;
    bool public launching = true;
    mapping(address member => uint256) public daysOf;

    constructor(address quoteToken_) {
        quoteToken = quoteToken_;
    }

    function setDays(address member, uint256 d) external {
        totalCheckIns = totalCheckIns - daysOf[member] + d;
        daysOf[member] = d;
    }
}

/// @notice StreakVault and its factory, no RPC needed. Most tests run a whole round first (join, check
///         in, launch through the mock Portal) so the vault is the one the launch really creates.
contract StreakVaultTest is RoundBase {
    uint256 internal constant RESERVE = 500_000 ether;

    StreakVault internal vault;
    IERC20 internal token;

    event Claimed(address indexed member, uint256 tokenAmount, uint256 quoteAmount);

    /// @dev alice 3 days, bob 2, carol 1, dave joined and never checked in: 6 check-ins in all. Four
    ///      deposits of 1000: 1200 to the pool with the sponsor's 600, and a prize of 2800.
    function _launchRound() internal {
        _join(dave);
        _fillTheBar();
        _sponsor(sponsorWallet, 600 ether);
        vm.prank(stranger);
        launcher.launch();
        vault = StreakVault(launcher.vault());
        token = IERC20(launcher.token());
    }

    function _claim(address member) internal {
        vm.prank(member);
        vault.claim();
    }

    /// @dev Tax arriving from the token's tax processor is a plain transfer of quote to the vault.
    function _taxArrives(uint256 amount) internal {
        usd.mint(address(vault), amount);
    }

    // ── creation ─────────────────────────────────────────────────────────────

    function test_launch_createsTheVaultWithTheRoundSnapshot() public {
        _launchRound();
        assertEq(vault.launcher(), address(launcher));
        assertEq(vault.taxToken(), address(token));
        assertEq(vault.quoteToken(), address(usd));
        assertEq(vault.totalCheckIns(), 6);
        assertEq(vault.reservedTokens(), RESERVE);
        assertTrue(vault.reserveReceived());
        assertEq(token.balanceOf(address(vault)), RESERVE, "half the supply is in the vault");
        assertEq(token.balanceOf(portal.POOL()), RESERVE, "half the supply is in the pool");
        assertEq(launcher.prizeQuote(), 2800 ether, "70% of four deposits");
        assertEq(vault.quoteReceived(), 2800 ether);
        assertEq(usd.balanceOf(address(vault)), 2800 ether);
        assertEq(vault.daysOf(alice), 3);
        assertEq(vault.daysOf(dave), 0);
        assertEq(vault.version(), "v1.0.0");
        (address recordedVault, address recordedFactory) = portal.getLaunchVault(address(token));
        assertEq(recordedVault, address(vault));
        assertEq(recordedFactory, address(vaultFactory));
    }

    // ── claims ───────────────────────────────────────────────────────────────

    function test_claim_sharesTokensAndPrizeByDaysCheckedIn() public {
        _launchRound();
        uint256 prize = 2800 ether;

        (uint256 t, uint256 q) = vault.claimable(alice);
        assertEq(t, RESERVE * 3 / 6);
        assertEq(q, prize * 3 / 6);

        vm.expectEmit(address(vault));
        emit Claimed(alice, RESERVE / 2, prize / 2);
        _claim(alice);
        _claim(bob);
        _claim(carol);

        assertEq(token.balanceOf(alice), 250_000 ether, "3 of 6 days: half the tokens");
        assertEq(token.balanceOf(bob), RESERVE * 2 / 6, "2 of 6 days: a third");
        assertEq(token.balanceOf(carol), RESERVE * 1 / 6, "1 of 6 days: a sixth");
        assertEq(usd.balanceOf(alice), 1400 ether, "half the prize: more than her 1000 deposit");
        assertEq(usd.balanceOf(bob), prize * 2 / 6);
        assertEq(usd.balanceOf(carol), prize * 1 / 6, "a sixth of the prize: less than her deposit");

        assertEq(vault.claimedTokens(alice), 250_000 ether);
        assertEq(vault.claimedQuote(alice), 1400 ether);
        assertEq(vault.totalTokensPaid(), token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol));
        assertEq(vault.totalQuotePaid(), usd.balanceOf(alice) + usd.balanceOf(bob) + usd.balanceOf(carol));
        assertEq(vault.quoteReceived(), prize, "paying out does not change what was received");
        // Thirds and sixths of these amounts do not divide evenly: a wei or two stays behind.
        assertLt(token.balanceOf(address(vault)), 3);
        assertLt(usd.balanceOf(address(vault)), 3);
    }

    function test_claim_aMemberWithNoCheckInGetsNothing() public {
        _launchRound();
        assertTrue(launcher.isMember(dave), "dave paid a deposit");
        (uint256 t, uint256 q) = vault.claimable(dave);
        assertEq(t, 0);
        assertEq(q, 0);
        vm.prank(dave);
        vm.expectRevert(StreakVault.NothingToClaim.selector);
        vault.claim();

        // Not later either, when tax has arrived.
        _taxArrives(600 ether);
        vm.prank(dave);
        vm.expectRevert(StreakVault.NothingToClaim.selector);
        vault.claim();
        assertEq(token.balanceOf(dave), 0);
        assertEq(usd.balanceOf(dave), 0);
    }

    function test_claim_nothingForSponsorCreatorAttesterOrStrangers() public {
        _launchRound();
        _taxArrives(600 ether);
        address[5] memory others = [sponsorWallet, creator, attester, guardian, stranger];
        for (uint256 i; i < others.length; ++i) {
            (uint256 t, uint256 q) = vault.claimable(others[i]);
            assertEq(t + q, 0);
            vm.prank(others[i]);
            vm.expectRevert(StreakVault.NothingToClaim.selector);
            vault.claim();
        }
        assertEq(usd.balanceOf(sponsorWallet), 0, "sponsor money went to the pool and earns no share");
    }

    function test_claim_tokensOnlyOnce() public {
        _launchRound();
        _claim(alice);
        (uint256 t, uint256 q) = vault.claimable(alice);
        assertEq(t, 0);
        assertEq(q, 0);
        vm.prank(alice);
        vm.expectRevert(StreakVault.NothingToClaim.selector);
        vault.claim();
        assertEq(token.balanceOf(alice), 250_000 ether);
    }

    function test_claim_againAsTaxArrives() public {
        _launchRound();
        uint256 prize = 2800 ether;
        _claim(alice); // tokens + half the prize
        assertEq(usd.balanceOf(alice), prize / 2);

        _taxArrives(600 ether);
        (uint256 t, uint256 q) = vault.claimable(alice);
        assertEq(t, 0, "tokens were paid on the first claim");
        assertEq(q, 300 ether, "half of the new tax");
        vm.expectEmit(address(vault));
        emit Claimed(alice, 0, 300 ether);
        _claim(alice);
        assertEq(usd.balanceOf(alice), prize / 2 + 300 ether);

        // bob claims for the first time only now: tokens, prize share and tax share at once.
        _claim(bob);
        assertEq(token.balanceOf(bob), RESERVE * 2 / 6);
        assertEq(usd.balanceOf(bob), (prize + 600 ether) * 2 / 6);

        // More tax, then everyone claims in a different order.
        _taxArrives(60 ether);
        _claim(carol);
        _claim(bob);
        _claim(alice);
        uint256 received = prize + 660 ether;
        assertEq(vault.quoteReceived(), received);
        assertEq(usd.balanceOf(alice), received * 3 / 6, "the order and number of claims do not matter");
        assertEq(usd.balanceOf(bob), received * 2 / 6);
        assertEq(usd.balanceOf(carol), received * 1 / 6);
        assertLt(usd.balanceOf(address(vault)), 3);

        // Nothing new, nothing to claim.
        vm.prank(alice);
        vm.expectRevert(StreakVault.NothingToClaim.selector);
        vault.claim();
    }

    function test_claim_isOpenStraightAfterTheLaunchWithNoOtherStep() public {
        _join(dave);
        _fillTheBar();
        _sponsor(sponsorWallet, 600 ether);
        launcher.launch();
        vault = StreakVault(launcher.vault());
        // No settle, no list, no role: the member claims in the very next call.
        _claim(carol);
        assertEq(usd.balanceOf(carol), uint256(2800 ether) / 6);
    }

    /// @dev Unequal days, awkward amounts, tax in three instalments and claims in between: every member
    ///      ends with exactly floor(received * days / total) and floor(reserve * days / total), the vault
    ///      never pays more than it received, and at most (members - 1) wei of each asset stays behind.
    function test_claim_roundingLeavesOnlyDust(uint256[3] memory daysSeed, uint256[3] memory tax, uint256 deposit_)
        public
    {
        deposit_ = bound(deposit_, 1, 1e27);
        RoundConfig memory c = _config();
        c.deposit = deposit_;
        c.liquidityBps = 3333;
        c.checkInGoal = 1;
        c.deadline = block.timestamp + 60 days;
        CheckInLauncher l = _open(c);

        address[3] memory m = [alice, bob, carol];
        uint256[3] memory d;
        uint256 total;
        for (uint256 i; i < 3; ++i) {
            _join(l, m[i]);
            d[i] = bound(daysSeed[i], i == 0 ? 1 : 0, 9); // alice always has at least one day
            total += d[i];
        }
        // Check in day by day: a member with d days checks in on the first d days.
        for (uint256 day; day < 9; ++day) {
            for (uint256 i; i < 3; ++i) {
                if (d[i] > day) _checkIn(l, m[i], _today());
            }
            vm.warp(block.timestamp + 1 days);
        }
        assertEq(l.totalCheckIns(), total);
        _sponsor(l, sponsorWallet, 1); // so the pool is never empty
        l.launch();
        StreakVault v = StreakVault(l.vault());
        IERC20 tkn = IERC20(l.token());
        uint256 received = v.quoteReceived();
        assertEq(received, 3 * deposit_ - (3 * deposit_ * 3333) / 10_000, "the prize");

        for (uint256 round; round < 3; ++round) {
            uint256 amount = bound(tax[round], 0, 1e27);
            usd.mint(address(v), amount);
            received += amount;
            // A different member claims after each instalment; some never claim until the end.
            address early = m[round];
            (uint256 t, uint256 q) = v.claimable(early);
            if (t + q != 0) {
                vm.prank(early);
                v.claim();
            }
        }
        for (uint256 i; i < 3; ++i) {
            (uint256 t, uint256 q) = v.claimable(m[i]);
            if (t + q != 0) {
                vm.prank(m[i]);
                v.claim();
            }
        }

        uint256 paidQuote;
        uint256 paidTokens;
        for (uint256 i; i < 3; ++i) {
            assertEq(usd.balanceOf(m[i]), received * d[i] / total, "quote share");
            assertEq(tkn.balanceOf(m[i]), RESERVE * d[i] / total, "token share");
            paidQuote += usd.balanceOf(m[i]);
            paidTokens += tkn.balanceOf(m[i]);
        }
        assertEq(v.quoteReceived(), received);
        assertEq(v.totalQuotePaid(), paidQuote);
        assertEq(v.totalTokensPaid(), paidTokens);
        assertLe(paidQuote, received);
        assertLt(received - paidQuote, 3, "quote dust");
        assertLt(RESERVE - paidTokens, 3, "token dust");
        assertEq(usd.balanceOf(address(v)), received - paidQuote);
        assertEq(tkn.balanceOf(address(v)), RESERVE - paidTokens);
    }

    // ── a vault built by hand ────────────────────────────────────────────────

    function _handBuilt(MockLauncher l) internal returns (StreakVault v, MockErc20 t) {
        t = new MockErc20("T", "T");
        address beacon = address(new UpgradeableBeacon(address(this), address(new StreakVault())));
        v = StreakVault(LibClone.deployERC1967BeaconProxy(beacon));
        v.initialize(address(t), address(l), RESERVE);
    }

    function test_initialize_revertsWithoutAnyCheckIn() public {
        MockLauncher l = new MockLauncher(address(usd));
        MockErc20 t = new MockErc20("T", "T");
        address beacon = address(new UpgradeableBeacon(address(this), address(new StreakVault())));
        StreakVault v = StreakVault(LibClone.deployERC1967BeaconProxy(beacon));
        vm.expectRevert(StreakVault.NoCheckIns.selector);
        v.initialize(address(t), address(l), RESERVE);

        vm.expectRevert(StreakVault.ZeroAddress.selector);
        v.initialize(address(0), address(l), RESERVE);
    }

    function test_initialize_onlyOnce() public {
        MockLauncher l = new MockLauncher(address(usd));
        l.setDays(alice, 1);
        (StreakVault v, MockErc20 t) = _handBuilt(l);
        vm.expectRevert("Initializable: contract is already initialized");
        v.initialize(address(t), address(l), RESERVE);

        StreakVault impl = new StreakVault();
        vm.expectRevert("Initializable: contract is already initialized");
        impl.initialize(address(t), address(l), RESERVE);
    }

    function test_initializeDistribution_onlyThePortalAndOnlyOnce() public {
        MockLauncher l = new MockLauncher(address(usd));
        l.setDays(alice, 1);
        (StreakVault v, MockErc20 t) = _handBuilt(l);

        vm.expectRevert(abi.encodeWithSelector(DirectLaunchVaultBase.NotHub.selector, address(this)));
        v.initializeDistribution(address(t), RESERVE, "", bytes32(0));

        t.mint(address(portal), 2 * RESERVE);
        vm.startPrank(address(portal));
        t.approve(address(v), 2 * RESERVE);
        vm.expectRevert(StreakVault.InvalidDistribution.selector);
        v.initializeDistribution(address(usd), RESERVE, "", bytes32(0)); // wrong token
        vm.expectRevert(StreakVault.InvalidDistribution.selector);
        v.initializeDistribution(address(t), RESERVE - 1, "", bytes32(0)); // wrong amount
        v.initializeDistribution(address(t), RESERVE, "", bytes32(0));
        vm.expectRevert(StreakVault.InvalidDistribution.selector);
        v.initializeDistribution(address(t), RESERVE, "", bytes32(0)); // only once
        vm.stopPrank();
        assertEq(t.balanceOf(address(v)), RESERVE);
    }

    function test_claim_aSingleMemberTakesEverything() public {
        MockLauncher l = new MockLauncher(address(usd));
        l.setDays(alice, 4);
        (StreakVault v, MockErc20 t) = _handBuilt(l);
        t.mint(address(v), RESERVE);
        usd.mint(address(v), 777 ether + 1);
        vm.prank(alice);
        v.claim();
        assertEq(t.balanceOf(alice), RESERVE);
        assertEq(usd.balanceOf(alice), 777 ether + 1);
        assertEq(usd.balanceOf(address(v)), 0);
    }

    // ── description and schema ───────────────────────────────────────────────

    function test_description_disclosesEveryoneWhoIsPaid() public {
        _launchRound();
        _claim(alice);
        string memory d = vault.description();
        assertTrue(LibString.startsWith(d, string.concat("StreakVault of the ", PRODUCT_NAME, " round of launcher 0x")));
        assertTrue(LibString.contains(d, LibString.toHexString(address(launcher))));
        assertTrue(LibString.contains(d, LibString.toHexString(attester)));
        assertTrue(LibString.contains(d, "500000000000000000000000 wei of reserved tokens"));
        assertTrue(
            LibString.contains(d, "received so far: 2800000000000000000000 wei; paid out: 1400000000000000000000 wei")
        );
        assertTrue(LibString.contains(d, "a member with d of the 6 check-ins counted at launch can claim d/6"));
        assertTrue(LibString.contains(d, "Members with no check-in receive nothing"));
        assertTrue(LibString.contains(d, "The other 20% of the tax is burned"));
        assertTrue(LibString.contains(d, "no share for the creator, the sponsors or the attester"));
        assertTrue(LibString.contains(d, "attested, not proven"));
        _assertCopyIsClean(d);
    }

    function test_uiSchema_listsTheClaimMethods() public {
        _launchRound();
        VaultUISchema memory s = vault.vaultUISchema();
        assertEq(s.vaultType, "StreakVault");
        assertEq(s.methods.length, 4);
        assertEq(s.methods[0].name, "claimable");
        assertEq(s.methods[0].outputs.length, 2);
        assertEq(s.methods[1].name, "daysOf");
        assertEq(s.methods[2].name, "quoteReceived");
        assertEq(s.methods[3].name, "claim");
        assertTrue(s.methods[3].isWriteMethod);
        assertEq(s.methods[3].inputs.length, 0);
        _assertCopyIsClean(s.description);
        _assertCopyIsClean(vaultFactory.vaultDataSchema().description);
    }

    function _assertCopyIsClean(string memory s) internal pure {
        string memory lower = LibString.lower(s);
        string[5] memory banned = ["trustless", "bet ", "gambl", "jackpot", "stake"];
        for (uint256 i; i < banned.length; ++i) {
            assertFalse(LibString.contains(lower, banned[i]), banned[i]);
        }
    }

    // ── the vault factory ────────────────────────────────────────────────────

    function test_factory_onlyThePortalCreatesVaults() public {
        vm.expectRevert(abi.encodeWithSelector(DirectLaunchVaultFactoryBase.NotHub.selector, address(this)));
        vaultFactory.newVault(address(1), address(launcher), 0, "");
        assertEq(vaultFactory.launcherFactory(), address(factory));
        assertEq(vaultFactory.VAULT_SLOT_BPS(), 8000);
        assertTrue(vaultFactory.isQuoteTokenSupported(address(usd)));
        assertFalse(vaultFactory.isQuoteTokenSupported(address(0)));
        assertEq(vaultFactory.tokenCreationPolicies().length, 3);
    }

    function test_factory_rejectsALauncherFromAnotherFactory() public {
        // A second Launcher factory that points at our vault factory, which does not name it back.
        CheckInLauncherFactory other =
            new CheckInLauncherFactory(address(portal), guardian, address(vaultFactory), address(usd));
        RoundConfig memory c = _config();
        c.checkInGoal = 1;
        vm.prank(creator);
        CheckInLauncher l = CheckInLauncher(portal.newLauncher{value: 0.005 ether}(address(other), abi.encode(c)));
        _join(l, alice);
        _checkIn(l, alice, _today());
        vm.expectRevert(abi.encodeWithSelector(StreakVaultFactory.NotFromLauncherFactory.selector, address(l)));
        l.launch();
        assertFalse(l.launched());
    }

    function test_factory_upgradesAreGuardianOnly() public {
        address newImpl = address(new StreakVault());
        vm.expectRevert(abi.encodeWithSelector(DirectLaunchVaultFactoryBase.NotGuardian.selector, address(this)));
        vaultFactory.upgradeVaultImplementation(newImpl);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(DirectLaunchVaultFactoryBase.NotGuardian.selector, creator));
        vaultFactory.upgradeVaultImplementation(newImpl);
    }
}
