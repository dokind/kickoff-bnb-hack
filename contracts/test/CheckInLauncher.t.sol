// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {LibString} from "solady/utils/LibString.sol";

import {LauncherFactoryBase} from "src/flap/LauncherFactoryBase.sol";
import {CheckInLauncher, RoundConfig} from "src/CheckInLauncher.sol";
import {CheckInLauncherFactory} from "src/CheckInLauncherFactory.sol";
import {PRODUCT_NAME} from "src/Product.sol";
import {RoundBase, MockPortal} from "test/RoundBase.sol";

/// @notice Every rule of a round against a mock Portal, no RPC needed: join, sponsor, check in with the
///         attester's signature, launch by anyone once the bar is full, refunds after a missed deadline.
contract CheckInLauncherTest is RoundBase {
    event Joined(address indexed member, uint256 amount);
    event Sponsored(address indexed sponsor, uint256 amount);
    event CheckedIn(address indexed member, uint256 indexed day, uint256 daysOfMember, uint256 totalCheckIns);
    event Launched(
        address indexed token, address indexed pool, address indexed vault, uint256 poolQuote, uint256 prizeQuote
    );
    event Refunded(address indexed account, uint256 amount);

    // ── config ───────────────────────────────────────────────────────────────

    function test_open_storesTheConfig() public view {
        assertEq(launcher.deposit(), DEPOSIT);
        assertEq(launcher.liquidityBps(), LIQUIDITY_BPS);
        assertEq(launcher.checkInGoal(), GOAL);
        assertEq(launcher.deadline(), deadline);
        assertEq(launcher.attester(), attester);
        assertEq(launcher.creator(), creator);
        assertEq(launcher.quoteToken(), address(usd));
        assertEq(launcher.vaultFactory(), address(vaultFactory));
        assertEq(launcher.name(), "Morning Movers");
        assertEq(launcher.symbol(), "MOVE");
        assertEq(launcher.memberCount(), 0);
        assertEq(launcher.totalCheckIns(), 0);
        assertEq(launcher.poolQuoteNow(), 0);
        assertEq(launcher.prizeQuoteNow(), 0);
        assertFalse(launcher.launched());
        assertFalse(launcher.canLaunch());
        assertEq(launcher.currentDay(), START / 1 days);
        assertEq(portal.saltLocker(bytes32(uint256(1))), address(launcher), "the Launcher locked its own salt");
        assertEq(portal.getLauncher(address(launcher)).launcherFactory, address(factory));
    }

    function _expectRejected(RoundConfig memory c, bytes memory err) internal {
        vm.prank(creator);
        vm.expectRevert(err);
        portal.newLauncher{value: 0.005 ether}(address(factory), abi.encode(c));
    }

    function test_factory_rejectsBadConfigs() public {
        RoundConfig memory c = _config();
        c.name = "";
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.EmptyField.selector));

        c = _config();
        c.symbol = "";
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.EmptyField.selector));

        c = _config();
        c.salt = bytes32(0);
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.EmptyField.selector));

        c = _config();
        c.attester = address(0);
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.ZeroAddress.selector));

        c = _config();
        c.deposit = 0;
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.InvalidDeposit.selector));

        c = _config();
        c.liquidityBps = 10_001;
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.InvalidLiquidityBps.selector, 10_001));

        c = _config();
        c.checkInGoal = 0;
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.InvalidCheckInGoal.selector));

        c = _config();
        c.deadline = block.timestamp; // must be in the future
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.InvalidDeadline.selector, c.deadline));

        c = _config();
        c.deadline = block.timestamp + 90 days + 1; // at most 90 days ahead
        _expectRejected(c, abi.encodeWithSelector(CheckInLauncherFactory.InvalidDeadline.selector, c.deadline));
    }

    function test_factory_acceptsTheEdgesOfTheConfig() public {
        RoundConfig memory c = _config();
        c.liquidityBps = 0; // all deposits are prize; the pool is sponsor money only
        c.checkInGoal = 1;
        c.deadline = block.timestamp + 90 days;
        CheckInLauncher l = _open(c);
        assertEq(l.liquidityBps(), 0);

        c = _config();
        c.liquidityBps = 10_000; // all deposits go to the pool; no prize
        assertEq(_open(c).liquidityBps(), 10_000);
    }

    function test_factory_rejectsTrailingBytesAndAnotherLayout() public {
        RoundConfig memory c = _config();
        vm.prank(creator);
        vm.expectRevert(CheckInLauncherFactory.InvalidData.selector);
        portal.newLauncher{value: 0.005 ether}(address(factory), bytes.concat(abi.encode(c), bytes32(0)));

        // The previous product's ten-field tuple does not decode into a valid round.
        vm.prank(creator);
        vm.expectRevert();
        portal.newLauncher{value: 0.005 ether}(
            address(factory),
            abi.encode(
                OldClubConfig(
                    c.name, c.symbol, c.meta, c.salt, 1500 ether, 500 ether, deadline, deadline + 1, attester, 20_000
                )
            )
        );
    }

    function test_factory_onlyThePortalCreatesLaunchers() public {
        RoundConfig memory c = _config();
        vm.expectRevert(abi.encodeWithSelector(LauncherFactoryBase.NotHub.selector, address(this)));
        factory.newLauncher{value: 0.005 ether}(creator, abi.encode(c));
    }

    function test_schema_listsTheNineFieldsInOrder() public view {
        string[9] memory names =
            ["name", "symbol", "meta", "salt", "deposit", "liquidityBps", "checkInGoal", "deadline", "attester"];
        string[9] memory types =
            ["string", "string", "string", "bytes32", "uint256", "uint256", "uint256", "time", "address"];
        assertEq(factory.launcherDataSchema().fields.length, 9);
        for (uint256 i; i < 9; ++i) {
            assertEq(factory.launcherDataSchema().fields[i].name, names[i]);
            assertEq(factory.launcherDataSchema().fields[i].fieldType, types[i]);
        }
        assertEq(factory.factorySpecVersion(), "lf-v1");
        assertEq(factory.DEFAULT_LIQUIDITY_BPS(), 3000);
    }

    /// @dev The payload the app builds for `Portal.newLauncher`. Pinned so the app and the verifier can
    ///      test their own encoders against the same bytes. If the struct changes, this test fails.
    function test_roundConfigEncodingVector() public pure {
        RoundConfig memory c;
        c.name = "Morning Movers";
        c.symbol = "MOVE";
        c.meta = "";
        c.salt = bytes32(uint256(0xab));
        c.deposit = 1000 ether;
        c.liquidityBps = 3000;
        c.checkInGoal = 6;
        c.deadline = 1796342400; // 2026-12-04T00:00:00Z
        c.attester = 0xFCAd0B19bB29D4674531d6f115237E16AfCE377c;
        bytes memory data = abi.encode(c);
        assertEq(data.length, 480, "15 words");
        assertEq(data, ROUND_CONFIG_VECTOR);
    }

    function test_description_isFlapJsonAndStatesWhatTheAttesterCannotDo() public view {
        string memory d = launcher.description();
        assertTrue(LibString.startsWith(d, '{"v":1,"name":"Morning Movers","symbol":"MOVE","quoteToken":"0x'));
        assertTrue(LibString.contains(d, '"targetRaise":"0"'), "no raise target: the launch opens on check-ins");
        assertTrue(LibString.contains(d, '"poolTokenRatio":"500000000000000000"'));
        assertTrue(LibString.contains(d, string.concat('"titleEn":"', PRODUCT_NAME, ": check in to launch")));
        assertTrue(LibString.contains(d, "check-ins are attested, not proven"));
        assertTrue(LibString.contains(d, "cannot launch the token, cannot stop a launch once the bar is full"));
        assertTrue(LibString.contains(d, "Sponsors, the creator and the attester receive nothing"));
        assertTrue(LibString.contains(d, "20% of the tax is burned"));
        assertTrue(LibString.contains(d, unicode"证明方不能发射代币"));
        assertTrue(LibString.endsWith(d, '"}'));
        _assertCopyIsClean(d);
        _assertCopyIsClean(factory.launcherDataSchema().description);
    }

    /// @dev Words the product copy must not use.
    function _assertCopyIsClean(string memory s) internal pure {
        string memory lower = LibString.lower(s);
        string[5] memory banned = ["trustless", "bet ", "gambl", "jackpot", "stake"];
        for (uint256 i; i < banned.length; ++i) {
            assertFalse(LibString.contains(lower, banned[i]), banned[i]);
        }
    }

    // ── join ─────────────────────────────────────────────────────────────────

    function test_join_paysTheDepositAndMakesAMember() public {
        usd.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        usd.approve(address(launcher), DEPOSIT);
        vm.expectEmit(address(launcher));
        emit Joined(alice, DEPOSIT);
        launcher.join();
        vm.stopPrank();

        assertTrue(launcher.isMember(alice));
        assertFalse(launcher.isMember(bob));
        assertEq(launcher.memberCount(), 1);
        assertEq(launcher.totalDeposits(), DEPOSIT);
        assertEq(usd.balanceOf(alice), 0);
        assertEq(usd.balanceOf(address(launcher)), DEPOSIT);
        assertEq(launcher.poolQuoteNow(), 300 ether, "30% of the deposit would seed the pool");
        assertEq(launcher.prizeQuoteNow(), 700 ether, "the rest is the prize");
    }

    function test_join_twiceReverts() public {
        _join(alice);
        usd.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        usd.approve(address(launcher), DEPOSIT);
        vm.expectRevert(CheckInLauncher.AlreadyMember.selector);
        launcher.join();
        vm.stopPrank();
        assertEq(launcher.memberCount(), 1);
        assertEq(launcher.totalDeposits(), DEPOSIT);
    }

    function test_join_openAtTheDeadlineAndClosedAfterIt() public {
        vm.warp(deadline);
        _join(alice);
        vm.warp(deadline + 1);
        usd.mint(bob, DEPOSIT);
        vm.startPrank(bob);
        usd.approve(address(launcher), DEPOSIT);
        vm.expectRevert(CheckInLauncher.RoundClosed.selector);
        launcher.join();
        vm.stopPrank();
    }

    function test_join_needsTheDepositApproved() public {
        usd.mint(alice, DEPOSIT);
        vm.prank(alice);
        vm.expectRevert();
        launcher.join();
        assertFalse(launcher.isMember(alice));
    }

    // ── sponsor ──────────────────────────────────────────────────────────────

    function test_sponsor_addsToThePoolOnlyAndEarnsNoMembership() public {
        _join(alice);
        usd.mint(sponsorWallet, 600 ether);
        vm.startPrank(sponsorWallet);
        usd.approve(address(launcher), 600 ether);
        vm.expectEmit(address(launcher));
        emit Sponsored(sponsorWallet, 400 ether);
        launcher.sponsor(400 ether);
        launcher.sponsor(200 ether); // any number of times
        vm.stopPrank();

        assertEq(launcher.sponsoredBy(sponsorWallet), 600 ether);
        assertEq(launcher.totalSponsored(), 600 ether);
        assertFalse(launcher.isMember(sponsorWallet));
        assertEq(launcher.memberCount(), 1);
        assertEq(launcher.poolQuoteNow(), 900 ether, "600 sponsored + 30% of one deposit");
        assertEq(launcher.prizeQuoteNow(), 700 ether, "sponsor money adds nothing to the prize");

        // A sponsor is not a member: no check-in, whatever is signed.
        bytes memory sig = _sign(sponsorWallet, _today());
        vm.prank(sponsorWallet);
        vm.expectRevert(CheckInLauncher.NotMember.selector);
        launcher.checkIn(_today(), sig);
    }

    function test_sponsor_zeroAmountReverts() public {
        vm.prank(sponsorWallet);
        vm.expectRevert(CheckInLauncher.ZeroAmount.selector);
        launcher.sponsor(0);
    }

    function test_sponsor_closedAfterTheDeadline() public {
        vm.warp(deadline + 1);
        usd.mint(sponsorWallet, 1 ether);
        vm.startPrank(sponsorWallet);
        usd.approve(address(launcher), 1 ether);
        vm.expectRevert(CheckInLauncher.RoundClosed.selector);
        launcher.sponsor(1 ether);
        vm.stopPrank();
    }

    // ── check-in ─────────────────────────────────────────────────────────────

    function test_checkIn_countsOneDayForTheMemberAndTheBar() public {
        _join(alice);
        _join(bob);
        uint256 day = _today();
        bytes memory sig = _sign(alice, day);

        vm.expectEmit(address(launcher));
        emit CheckedIn(alice, day, 1, 1);
        vm.prank(alice);
        launcher.checkIn(day, sig);

        assertEq(launcher.daysOf(alice), 1);
        assertEq(launcher.totalCheckIns(), 1);
        assertTrue(launcher.checkedInOn(alice, day));
        assertFalse(launcher.checkedInOn(alice, day - 1));
        assertFalse(launcher.checkedInOn(bob, day));

        vm.expectEmit(address(launcher));
        emit CheckedIn(bob, day, 1, 2);
        _checkIn(bob, day);
        assertEq(launcher.totalCheckIns(), 2);
    }

    function test_checkIn_digestMatchesThePersonalSignFormula() public view {
        uint256 day = _today();
        assertEq(launcher.checkInDigest(alice, day), _digest(address(launcher), alice, day));
        // The same thing spelled with OpenZeppelin's helper.
        assertEq(
            launcher.checkInDigest(alice, day),
            ECDSA.toEthSignedMessageHash(keccak256(abi.encode(uint256(97), address(launcher), alice, day)))
        );
    }

    function test_checkIn_yesterdayIsAcceptedOnce() public {
        _join(alice);
        uint256 day = _today();
        _checkIn(alice, day - 1);
        _checkIn(alice, day);
        assertEq(launcher.daysOf(alice), 2);
        assertEq(launcher.totalCheckIns(), 2);
    }

    function test_checkIn_revertsForANonMember() public {
        _join(alice);
        uint256 day = _today();
        // Even with a valid signature from the attester for that very wallet.
        bytes memory sig = _sign(stranger, day);
        vm.prank(stranger);
        vm.expectRevert(CheckInLauncher.NotMember.selector);
        launcher.checkIn(day, sig);
        assertEq(launcher.totalCheckIns(), 0);
    }

    function test_checkIn_revertsForTheWrongSigner() public {
        _join(alice);
        uint256 day = _today();
        // Signed correctly, but by a key that is not the attester's: the member's own, or anyone's.
        bytes memory sig = _signWith(0xBADBAD, address(launcher), alice, day);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        launcher.checkIn(day, sig);
        assertEq(launcher.daysOf(alice), 0);
    }

    function test_checkIn_signatureIsBoundToWalletDayRoundAndChain() public {
        _join(alice);
        _join(bob);
        uint256 day = _today();

        // Another wallet's signature.
        bytes memory forBob = _sign(bob, day);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        launcher.checkIn(day, forBob);

        // Another day's signature.
        bytes memory forYesterday = _sign(alice, day - 1);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        launcher.checkIn(day, forYesterday);

        // Another round's signature, same attester.
        CheckInLauncher other = _open(_config());
        _join(other, alice);
        bytes memory forThisRound = _sign(alice, day);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        other.checkIn(day, forThisRound);

        // Another chain's signature.
        vm.chainId(56);
        bytes memory forMainnet = _sign(alice, day);
        vm.chainId(97);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        launcher.checkIn(day, forMainnet);

        assertEq(launcher.totalCheckIns(), 0);
        assertEq(other.totalCheckIns(), 0);
    }

    function test_checkIn_revertsForAMalformedSignature() public {
        _join(alice);
        uint256 day = _today();
        bytes memory good = _sign(alice, day);

        bytes memory empty;
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        launcher.checkIn(day, empty);

        bytes memory short = new bytes(64);
        for (uint256 i; i < 64; ++i) {
            short[i] = good[i];
        }
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        launcher.checkIn(day, short);

        bytes memory badV = bytes.concat(short, bytes1(uint8(5)));
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.InvalidSignature.selector);
        launcher.checkIn(day, badV);

        assertEq(launcher.totalCheckIns(), 0);
    }

    function test_checkIn_revertsOnAReplayedDay() public {
        _join(alice);
        uint256 day = _today();
        bytes memory sig = _sign(alice, day);
        vm.prank(alice);
        launcher.checkIn(day, sig);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.AlreadyCheckedIn.selector, day));
        launcher.checkIn(day, sig);

        // Still a replay the next day, when that day has become "yesterday".
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.AlreadyCheckedIn.selector, day));
        launcher.checkIn(day, sig);

        assertEq(launcher.daysOf(alice), 1);
        assertEq(launcher.totalCheckIns(), 1);
    }

    function test_checkIn_revertsForAFutureDay() public {
        _join(alice);
        uint256 day = _today();
        bytes memory sig = _sign(alice, day + 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.InvalidDay.selector, day + 1, day));
        launcher.checkIn(day + 1, sig);

        // One second before midnight UTC tomorrow is still the future.
        vm.warp((day + 1) * 1 days - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.InvalidDay.selector, day + 1, day));
        launcher.checkIn(day + 1, sig);

        // At midnight it is today.
        vm.warp((day + 1) * 1 days);
        vm.prank(alice);
        launcher.checkIn(day + 1, sig);
        assertEq(launcher.daysOf(alice), 1);
    }

    function test_checkIn_revertsForADayOlderThanYesterday() public {
        _join(alice);
        uint256 day = _today();
        bytes memory sig = _sign(alice, day - 2);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.InvalidDay.selector, day - 2, day));
        launcher.checkIn(day - 2, sig);

        // A signature for today expires two days later.
        bytes memory today = _sign(alice, day);
        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.InvalidDay.selector, day, day + 2));
        launcher.checkIn(day, today);
    }

    function test_checkIn_closedAfterTheDeadline() public {
        _join(alice);
        vm.warp(deadline);
        _checkIn(alice, _today()); // still open at the deadline itself

        vm.warp(deadline + 1);
        uint256 day = _today();
        bytes memory sig = _sign(alice, day - 1);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.CheckInsClosed.selector);
        launcher.checkIn(day - 1, sig);
    }

    function test_checkIn_closedOnceLaunched() public {
        _fillTheBar();
        _sponsor(sponsorWallet, 600 ether);
        vm.prank(stranger);
        launcher.launch();

        // carol has not checked in today, and the attester signs it, but the bar is closed.
        uint256 day = _today();
        bytes memory sig = _sign(carol, day);
        vm.prank(carol);
        vm.expectRevert(CheckInLauncher.CheckInsClosed.selector);
        launcher.checkIn(day, sig);
        assertEq(launcher.daysOf(carol), 1);
        assertEq(launcher.totalCheckIns(), GOAL);
    }

    // ── launch ───────────────────────────────────────────────────────────────

    function test_launch_revertsBelowTheGoalForEveryone() public {
        _join(alice);
        _join(bob);
        _join(carol);
        _sponsor(sponsorWallet, 600 ether);
        uint256 d = _today();
        _checkIn(alice, d - 1);
        _checkIn(alice, d);
        _checkIn(bob, d);
        _checkIn(carol, d);
        _checkIn(bob, d - 1);
        assertEq(launcher.totalCheckIns(), GOAL - 1);
        assertFalse(launcher.canLaunch());

        // Nobody can launch one check-in short: not the attester, the creator, a member or the sponsor.
        address[6] memory callers = [attester, creator, alice, sponsorWallet, guardian, stranger];
        for (uint256 i; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(CheckInLauncher.GoalNotReached.selector, GOAL - 1, GOAL));
            launcher.launch();
        }
        assertFalse(launcher.launched());
        assertEq(portal.launches(), 0);
    }

    function test_launch_byAnyoneSplitsTheMoneyBetweenPoolAndPrize() public {
        _fillTheBar();
        _sponsor(sponsorWallet, 600 ether);
        assertEq(launcher.totalDeposits(), 3000 ether);
        assertEq(launcher.poolQuoteNow(), 1500 ether, "600 sponsored + 30% of 3000");
        assertEq(launcher.prizeQuoteNow(), 2100 ether, "70% of 3000");
        assertTrue(launcher.canLaunch());

        // The fourth topic (the vault) is not known in advance; the amounts are.
        vm.expectEmit(false, true, false, true, address(launcher));
        emit Launched(address(0), portal.POOL(), address(0), 1500 ether, 2100 ether);
        vm.prank(stranger); // no role, no deposit
        launcher.launch();

        assertTrue(launcher.launched());
        assertFalse(launcher.launching());
        assertFalse(launcher.canLaunch());
        assertTrue(portal.launcherWasLaunching(), "the launching flag is up during the Portal call");
        assertEq(portal.launches(), 1);
        assertEq(portal.lastLaunchCaller(), address(launcher));
        assertEq(portal.lastPoolQuote(), 1500 ether);

        address vault = launcher.vault();
        assertTrue(vault != address(0));
        assertEq(launcher.pool(), portal.POOL());
        assertEq(usd.balanceOf(portal.POOL()), 1500 ether, "sponsor money + liquidity part in the pool");
        assertEq(usd.balanceOf(vault), 2100 ether, "the prize is in the vault, in the same transaction");
        assertEq(usd.balanceOf(address(launcher)), 0, "nothing is left in the Launcher");
        assertEq(usd.allowance(address(launcher), address(portal)), 0);
        assertEq(launcher.prizeQuote(), 2100 ether);
        assertEq(launcher.prizeQuoteNow(), 2100 ether);
        assertEq(launcher.poolQuoteNow(), 1500 ether, "unchanged after the launch");
        // The totals and the days are frozen.
        assertEq(launcher.totalDeposits(), 3000 ether);
        assertEq(launcher.totalSponsored(), 600 ether);
        assertEq(launcher.memberCount(), 3);
        assertEq(launcher.daysOf(alice), 3);
        assertEq(launcher.daysOf(bob), 2);
        assertEq(launcher.daysOf(carol), 1);
    }

    function test_launch_onlyOnce() public {
        _fillTheBar();
        _sponsor(sponsorWallet, 600 ether);
        launcher.launch();
        vm.expectRevert(CheckInLauncher.AlreadyLaunched.selector);
        launcher.launch();
        assertEq(portal.launches(), 1);
    }

    function test_launch_allowedAtTheDeadline() public {
        _fillTheBar();
        vm.warp(deadline);
        vm.prank(stranger);
        launcher.launch();
        assertTrue(launcher.launched());
    }

    function test_launch_revertsAfterTheDeadline() public {
        _fillTheBar();
        vm.warp(deadline + 1);
        assertFalse(launcher.canLaunch());
        vm.prank(stranger);
        vm.expectRevert(CheckInLauncher.LaunchClosed.selector);
        launcher.launch();
        assertFalse(launcher.launched());
        assertEq(portal.launches(), 0);
    }

    function test_launch_belowThePortalFloorRevertsUntilASponsorTopsUp() public {
        portal.setFloor(1500 ether);
        _fillTheBar();
        assertEq(launcher.poolQuoteNow(), 900 ether, "30% of three deposits is below the floor");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(MockPortal.BelowFloor.selector, 900 ether, 1500 ether));
        launcher.launch();
        // The failed launch changed nothing: the round is still open.
        assertFalse(launcher.launched());
        assertFalse(launcher.launching());
        assertEq(usd.balanceOf(address(launcher)), 3000 ether);
        assertEq(usd.allowance(address(launcher), address(portal)), 0);

        _sponsor(sponsorWallet, 600 ether);
        assertEq(launcher.poolQuoteNow(), 1500 ether);
        vm.prank(stranger);
        launcher.launch();
        assertTrue(launcher.launched());
        assertEq(usd.balanceOf(launcher.vault()), 2100 ether);
    }

    function test_launch_revertsWithNothingForThePool() public {
        RoundConfig memory c = _config();
        c.liquidityBps = 0;
        c.checkInGoal = 1;
        CheckInLauncher l = _open(c);
        _join(l, alice);
        _checkIn(l, alice, _today());
        assertEq(l.poolQuoteNow(), 0);
        assertFalse(l.canLaunch());
        vm.expectRevert(CheckInLauncher.NoPoolQuote.selector);
        l.launch();

        // With sponsor money the pool is the sponsor money and the whole deposit is the prize.
        _sponsor(l, sponsorWallet, 50 ether);
        l.launch();
        assertEq(usd.balanceOf(portal.POOL()), 50 ether);
        assertEq(usd.balanceOf(l.vault()), DEPOSIT);
    }

    function test_launch_poolAndPrizeAlwaysAddUpToTheDeposits(uint256 deposit_, uint256 bps, uint8 members) public {
        deposit_ = bound(deposit_, 1, 1e30);
        bps = bound(bps, 1, 10_000);
        uint256 n = bound(members, 1, 5);
        RoundConfig memory c = _config();
        c.deposit = deposit_;
        c.liquidityBps = bps;
        c.checkInGoal = n;
        CheckInLauncher l = _open(c);
        for (uint256 i; i < n; ++i) {
            address m = address(uint160(0xF00D0000 + i));
            _join(l, m);
            _checkIn(l, m, _today());
        }
        uint256 total = n * deposit_;
        uint256 poolQuote = l.poolQuoteNow();
        assertEq(poolQuote, total * bps / 10_000);
        vm.assume(poolQuote != 0);

        l.launch();
        assertEq(usd.balanceOf(portal.POOL()), poolQuote);
        assertEq(usd.balanceOf(l.vault()), total - poolQuote, "the prize is exactly the rest");
        assertEq(usd.balanceOf(address(l)), 0, "no dust in the Launcher");
    }

    function test_launch_strayQuoteSentToTheLauncherBecomesPrize() public {
        _fillTheBar();
        _sponsor(sponsorWallet, 600 ether);
        usd.mint(address(launcher), 7 ether); // a plain transfer, not sponsor()
        assertEq(launcher.poolQuoteNow(), 1500 ether);
        assertEq(launcher.prizeQuoteNow(), 2107 ether);
        launcher.launch();
        assertEq(usd.balanceOf(launcher.vault()), 2107 ether);
        assertEq(usd.balanceOf(address(launcher)), 0);
    }

    function test_afterLaunch_noJoinNoSponsorNoRefund() public {
        _fillTheBar();
        _sponsor(sponsorWallet, 600 ether);
        launcher.launch();

        usd.mint(dave, DEPOSIT);
        vm.startPrank(dave);
        usd.approve(address(launcher), DEPOSIT);
        vm.expectRevert(CheckInLauncher.RoundClosed.selector);
        launcher.join();
        vm.expectRevert(CheckInLauncher.RoundClosed.selector);
        launcher.sponsor(1 ether);
        vm.stopPrank();

        vm.warp(deadline + 1);
        assertEq(launcher.refundable(alice), 0);
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund();
        vm.prank(sponsorWallet);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund();
    }

    // ── refund ───────────────────────────────────────────────────────────────

    function test_refund_closedUntilTheDeadlineHasPassed() public {
        _join(alice);
        _sponsor(sponsorWallet, 100 ether);
        assertEq(launcher.refundable(alice), 0);

        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund();

        vm.warp(deadline); // the launch is still possible at the deadline itself
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund();
        vm.prank(sponsorWallet);
        vm.expectRevert(CheckInLauncher.RefundUnavailable.selector);
        launcher.refund();
    }

    function test_refund_membersGetTheFullDepositAndSponsorsTheirContribution() public {
        _join(alice);
        _join(bob);
        _sponsor(sponsorWallet, 600 ether);
        _checkIn(alice, _today());
        _checkIn(bob, _today()); // two of six: the bar never fills

        vm.warp(deadline + 1);
        assertEq(launcher.refundable(alice), DEPOSIT);
        assertEq(launcher.refundable(sponsorWallet), 600 ether);
        assertEq(launcher.refundable(stranger), 0);

        vm.expectEmit(address(launcher));
        emit Refunded(alice, DEPOSIT);
        vm.prank(alice);
        launcher.refund();
        assertEq(usd.balanceOf(alice), DEPOSIT, "the full deposit, not 70% of it");
        assertFalse(launcher.isMember(alice));
        assertEq(launcher.memberCount(), 1);
        assertEq(launcher.totalDeposits(), DEPOSIT);

        vm.expectEmit(address(launcher));
        emit Refunded(sponsorWallet, 600 ether);
        vm.prank(sponsorWallet);
        launcher.refund();
        assertEq(usd.balanceOf(sponsorWallet), 600 ether);
        assertEq(launcher.sponsoredBy(sponsorWallet), 0);
        assertEq(launcher.totalSponsored(), 0);

        vm.prank(bob);
        launcher.refund();
        assertEq(usd.balanceOf(bob), DEPOSIT);
        assertEq(usd.balanceOf(address(launcher)), 0, "everything went back to who paid it");
        assertEq(launcher.memberCount(), 0);
        assertEq(launcher.totalDeposits(), 0);
        assertFalse(launcher.launched());
        assertEq(portal.launches(), 0);
    }

    function test_refund_aMemberWhoAlsoSponsoredGetsBothAtOnce() public {
        _join(alice);
        _sponsor(alice, 250 ether);
        vm.warp(deadline + 1);
        assertEq(launcher.refundable(alice), DEPOSIT + 250 ether);
        vm.expectEmit(address(launcher));
        emit Refunded(alice, DEPOSIT + 250 ether);
        vm.prank(alice);
        launcher.refund();
        assertEq(usd.balanceOf(alice), DEPOSIT + 250 ether);
        assertEq(usd.balanceOf(address(launcher)), 0);
    }

    function test_refund_onlyOnceAndNothingForOthers() public {
        _join(alice);
        _join(bob);
        _sponsor(sponsorWallet, 100 ether);
        vm.warp(deadline + 1);

        vm.prank(alice);
        launcher.refund();
        vm.prank(alice);
        vm.expectRevert(CheckInLauncher.NothingToRefund.selector);
        launcher.refund();

        vm.prank(sponsorWallet);
        launcher.refund();
        vm.prank(sponsorWallet);
        vm.expectRevert(CheckInLauncher.NothingToRefund.selector);
        launcher.refund();

        // The attester, the creator and a stranger paid nothing in and take nothing out.
        address[3] memory others = [attester, creator, stranger];
        for (uint256 i; i < others.length; ++i) {
            vm.prank(others[i]);
            vm.expectRevert(CheckInLauncher.NothingToRefund.selector);
            launcher.refund();
        }
        assertEq(usd.balanceOf(address(launcher)), DEPOSIT, "bob's deposit is still there for bob");
    }

    function test_refund_evenWhenTheBarWasFullButNobodyLaunched() public {
        _fillTheBar();
        assertEq(launcher.totalCheckIns(), GOAL);
        vm.warp(deadline + 1);
        vm.expectRevert(CheckInLauncher.LaunchClosed.selector);
        launcher.launch();
        vm.prank(carol);
        launcher.refund();
        assertEq(usd.balanceOf(carol), DEPOSIT);
    }

    // ── the signature vector ─────────────────────────────────────────────────

    /// @dev Pinned for the verifier (which signs) and the app (which submits). Test key
    ///      0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef, a well-known test value.
    function test_checkInSignatureVector() public {
        uint256 key = 0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        address signer = 0xFCAd0B19bB29D4674531d6f115237E16AfCE377c;
        address launcherAt = 0x1000000000000000000000000000000000000001;
        address wallet = 0x2000000000000000000000000000000000000002;
        uint256 day = 20782; // 2026-11-25 UTC

        bytes32 inner = 0xcbafcc6a3bedc56b8321a9d1f392336f2ecb2f6f507c449622b3597fab79ab07;
        bytes32 digest = 0xc1d54e2ae2bba8b6827381f84e8b5fa7ec86048f467fd60570575dec445aba41;
        bytes memory signature =
            hex"ea91a378e84c0366ee93151c23b319e4ace635db74a3175e585737d4cd9cd5256dc9ee53d41e88ce0ac5b09c04f13e85612648bf490fad7c1e32814fc11b7cdc1c";

        assertEq(vm.addr(key), signer);
        assertEq(keccak256(abi.encode(uint256(97), launcherAt, wallet, day)), inner);
        assertEq(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner)), digest);

        // The contract computes the same digest when it lives at that address on chain 97. (The digest
        // only reads the chain id and the contract's own address, so the bare implementation code will do.)
        vm.etch(launcherAt, factory.beaconImplementation().code);
        assertEq(CheckInLauncher(launcherAt).checkInDigest(wallet, day), digest);

        // The key produces exactly this signature (RFC 6979), and it recovers to the signer.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        assertEq(abi.encodePacked(r, s, v), signature);
        assertEq(v, 28);
        assertEq(ECDSA.recover(digest, signature), signer);
    }

    /// @dev The same vector accepted by a real round: a Launcher whose attester is the test key takes
    ///      a signature built only from the documented formula.
    function test_checkIn_acceptsASignatureFromTheDocumentedFormula() public {
        uint256 key = 0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        RoundConfig memory c = _config();
        c.attester = vm.addr(key);
        CheckInLauncher l = _open(c);
        _join(l, alice);
        uint256 day = _today();
        bytes32 inner = keccak256(abi.encode(uint256(97), address(l), alice, day));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(key, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner)));
        vm.prank(alice);
        l.checkIn(day, abi.encodePacked(r, s, v));
        assertEq(l.daysOf(alice), 1);
    }
}

/// @dev The config tuple of the earlier product (running club seasons), ten fields.
struct OldClubConfig {
    string name;
    string symbol;
    string meta;
    bytes32 salt;
    uint256 targetRaise;
    uint256 joinFee;
    uint256 raiseDeadline;
    uint256 seasonEnd;
    address verifier;
    uint256 kickoffTarget;
}

/// @dev From Foundry, independent of the struct:
///      cast abi-encode "f((string,string,string,bytes32,uint256,uint256,uint256,uint256,address))" \
///        '("Morning Movers","MOVE","",0x00..ab,1000e18,3000,6,1796342400,0xFCAd0B19bB29D4674531d6f115237E16AfCE377c)'
bytes constant ROUND_CONFIG_VECTOR = hex"0000000000000000000000000000000000000000000000000000000000000020"
    hex"0000000000000000000000000000000000000000000000000000000000000120"
    hex"0000000000000000000000000000000000000000000000000000000000000160"
    hex"00000000000000000000000000000000000000000000000000000000000001a0"
    hex"00000000000000000000000000000000000000000000000000000000000000ab"
    hex"00000000000000000000000000000000000000000000003635c9adc5dea00000"
    hex"0000000000000000000000000000000000000000000000000000000000000bb8"
    hex"0000000000000000000000000000000000000000000000000000000000000006"
    hex"000000000000000000000000000000000000000000000000000000006b120280"
    hex"000000000000000000000000fcad0b19bb29d4674531d6f115237e16afce377c"
    hex"000000000000000000000000000000000000000000000000000000000000000e"
    hex"4d6f726e696e67204d6f76657273000000000000000000000000000000000000"
    hex"0000000000000000000000000000000000000000000000000000000000000004"
    hex"4d4f564500000000000000000000000000000000000000000000000000000000"
    hex"0000000000000000000000000000000000000000000000000000000000000000";
