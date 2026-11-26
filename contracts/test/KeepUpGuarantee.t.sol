// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {CheckInLauncher, RoundConfig} from "src/CheckInLauncher.sol";
import {StreakVault} from "src/StreakVault.sol";
import {RoundBase} from "test/RoundBase.sol";

/// @notice The Keep-Up Guarantee, checked on our real contracts (the mock Portal of RoundBase stands in for
///         Flap; the Launcher, the piggy bank and their factories run unchanged). No RPC needed.
///
///         Frozen at launch: N members who each paid the same deposit D, T check-ins in all, your d days.
///         The piggy bank (StreakVault) pays you floor(Q * d / T) of all the test USD it ever received,
///         Q = the prize + the tax so far. The prize is everything the Launcher holds beyond the shop money:
///         N*D - floor(N*D*L/10000), plus any test USD sent to the Launcher directly. So when d * N >= T
///         (your days are at least the average T / N, counting 0-day members and late joiners):
///
///           L = 0      a sponsored Season (the shop is sponsor money only): at least D back
///           L = 3000   the default round (30% of each deposit builds the shop): at least floor(7 * D / 10)
///           any L      at least floor(D * (10000 - L) / 10000)
///
///         Coins and tax come on top and are never promised. Not covered, and pinned below as the honest edge:
///         if somebody launches on day k before your check-in that day, you can end just under the average and
///         get less than D, but never less than (k - 1) / k of it (about 96.7% at k = 30).
contract KeepUpGuaranteeTest is RoundBase {
    uint256 internal constant SEASON_DAYS = 30;
    uint256 internal constant MAX_MEMBERS = 20;
    /// @dev Flap's floor at our factory's 1x multiplier on testnet: the mock Portal refuses a smaller shop.
    uint256 internal constant SHOP_FLOOR = 1500 ether;
    uint256 internal constant RESERVE = 500_000 ether;
    /// @dev Season 1's deadline: 31 Dec 2026 23:59:59 UTC.
    uint256 internal constant SEASON1_DEADLINE = 1798761599;
    /// @dev Tue 1 Dec 2026, the first Season 1 check-in day (UTC day number).
    uint256 internal constant SEASON1_FIRST_DAY = 20788;

    /// @dev Raw fuzz input, bounded in `_build`.
    struct Seeds {
        uint8 members;
        uint8[20] streaks;
        uint8[20] joinDays;
        uint256 deposit;
        uint256 sponsor;
        uint256 stray;
        uint256 tax;
        uint256 goal;
    }

    /// @dev One round as it is played.
    struct Round {
        CheckInLauncher launcher;
        StreakVault vault;
        uint256 n;
        uint256 deposit;
        uint256 bps;
        uint256 sponsor;
        uint256 stray;
        uint256 tax;
        uint256 goal;
        uint256 total;
        address[] members;
        uint256[] streak;
        uint256[] joinDay;
    }

    // ── the property, fuzzed ─────────────────────────────────────────────────

    /// @dev Sponsored Season, 0% of deposits to the shop: keep up with the average, get the whole deposit back
    ///      or more. 1 to 20 members, 0 to 30 days each, late joiners, any deposit, any sponsor at or above the
    ///      floor, stray test USD and up to 1e30 wei of tax in two parts with claims in between.
    /// forge-config: default.fuzz.runs = 1024
    function test_keepUp_sponsoredSeason_depositBackOrMore(Seeds memory s) public {
        Round memory r = _playAndLaunch(s, 0);
        assertEq(_guaranteed(r), r.deposit, "with 0% to the shop the bound is the whole deposit");
    }

    /// @dev Default round, 30% of each deposit to the shop: keep up with the average, get at least 70% back.
    /// forge-config: default.fuzz.runs = 1024
    function test_keepUp_defaultRound_atLeast70Percent(Seeds memory s) public {
        Round memory r = _playAndLaunch(s, 3000);
        assertEq(_guaranteed(r), r.deposit * 7 / 10, "with 30% to the shop the bound is 70% of the deposit");
    }

    /// @dev Any shop share from 0% to 100%: the bound is the part of the deposit that stays prize.
    /// forge-config: default.fuzz.runs = 1024
    function test_keepUp_anyShopShare(Seeds memory s, uint256 bps) public {
        _playAndLaunch(s, bound(bps, 0, 10_000));
    }

    // ── worked examples (the numbers said on stage) ──────────────────────────

    /// @dev Season 1 Squad A as configured: 10 members x 100 test USD, 0% to the shop, a 1,500 sponsor, goal 240,
    ///      created on 26 Nov with the real deadline. Check-ins 1 to 30 Dec: 6 members x 30 days + 3 x 20 + 1 x 0
    ///      = 240, so the average is 24 days. 30 days: 125 test USD + 62,500 coins. 20 days: 83.33 + 41,666.67.
    ///      0 days: nothing. Split by days, never a return.
    function test_keepUp_season1SquadExample() public {
        RoundConfig memory c = _config();
        c.name = "Season 1 Squad A";
        c.deposit = 100 ether;
        c.liquidityBps = 0;
        c.checkInGoal = 240;
        c.deadline = SEASON1_DEADLINE;
        CheckInLauncher l = _open(c);
        portal.setFloor(SHOP_FLOOR);

        address[10] memory squad;
        for (uint256 i; i < 10; ++i) {
            squad[i] = address(uint160(0x5A0A_0000 + i));
            _join(l, squad[i]); // pre-season: everyone starts at 0
        }
        _sponsor(l, sponsorWallet, SHOP_FLOOR);

        vm.warp(SEASON1_FIRST_DAY * 1 days + 1 hours); // Tue 1 Dec, 08:00 in Bangkok
        for (uint256 day; day < SEASON_DAYS; ++day) {
            for (uint256 i; i < 10; ++i) {
                if (i < 6 || (i < 9 && day < 20)) _checkIn(l, squad[i], _today());
            }
            if (day + 1 < SEASON_DAYS) vm.warp(block.timestamp + 1 days);
        }
        assertEq(_today(), SEASON1_FIRST_DAY + 29, "Wed 30 Dec");
        assertEq(l.totalCheckIns(), 240, "the bar is full");

        vm.prank(stranger);
        l.launch();
        StreakVault v = StreakVault(l.vault());
        assertEq(usd.balanceOf(portal.POOL()), SHOP_FLOOR, "the shop is the sponsor's money only");
        assertEq(v.quoteReceived(), 1000 ether, "every deposit is prize");

        (uint256 coins, uint256 back) = v.claimable(squad[0]);
        assertEq(back, 125 ether, "30 days, above the average of 24: more than the 100 deposit");
        assertEq(coins, 62_500 ether);
        (coins, back) = v.claimable(squad[6]);
        assertEq(back, uint256(1000 ether) * 20 / 240, "20 days: 83.33");
        assertEq(coins, RESERVE * 20 / 240, "41,666.67 coins");
        assertLt(back, 100 ether, "below the average: less than the deposit");
        (coins, back) = v.claimable(squad[9]);
        assertEq(coins + back, 0, "0 days: nothing");
    }

    /// @dev Round 1 replayed with 0% to the shop: 3 x 500, a 1,500 sponsor, 2 / 1 / 0 days give 1,000 / 500 / 0
    ///      before tax. The average member (1 day; the average is 3 / 3) gets exactly the deposit back.
    function test_keepUp_round1AtZeroShopShare() public {
        RoundConfig memory c = _config();
        c.deposit = 500 ether;
        c.liquidityBps = 0;
        c.checkInGoal = 3;
        CheckInLauncher l = _open(c);
        portal.setFloor(SHOP_FLOOR);
        _join(l, alice);
        _join(l, bob);
        _join(l, carol);
        _sponsor(l, sponsorWallet, SHOP_FLOOR);
        uint256 d = _today();
        _checkIn(l, alice, d - 1);
        _checkIn(l, alice, d);
        _checkIn(l, bob, d);

        vm.prank(stranger);
        l.launch();
        StreakVault v = StreakVault(l.vault());
        (, uint256 back) = v.claimable(alice);
        assertEq(back, 1000 ether, "2 days of 3");
        (, back) = v.claimable(bob);
        assertEq(back, 500 ether, "the average member: exactly the deposit");
        (uint256 coins, uint256 rest) = v.claimable(carol);
        assertEq(coins + rest, 0, "0 days: nothing");
    }

    /// @dev The honest edge: 10 members x 100, 0% to the shop. Nine check in all 30 days. On day 30 somebody
    ///      launches before you check in, so you end with 29 days against an average of 29.9: 96.99 test USD,
    ///      under the deposit but not under 29/30 of it. Hence "check in early in your UTC day".
    function test_keepUp_launchBeforeYourCheckIn_isTheDocumentedEdge() public {
        uint256 k = SEASON_DAYS;
        RoundConfig memory c = _config();
        c.deposit = 100 ether;
        c.liquidityBps = 0;
        c.checkInGoal = 240;
        c.deadline = block.timestamp + 40 days;
        CheckInLauncher l = _open(c);
        portal.setFloor(SHOP_FLOOR);
        address[10] memory squad;
        for (uint256 i; i < 10; ++i) {
            squad[i] = address(uint160(0x5A0B_0000 + i));
            _join(l, squad[i]);
        }
        _sponsor(l, sponsorWallet, SHOP_FLOOR);
        address you = squad[9];

        for (uint256 day; day < k; ++day) {
            for (uint256 i; i < 9; ++i) {
                _checkIn(l, squad[i], _today());
            }
            if (day + 1 < k) {
                _checkIn(l, you, _today());
                vm.warp(block.timestamp + 1 days);
            }
        }
        vm.prank(stranger);
        l.launch(); // day 30, before your check-in

        assertEq(l.daysOf(you), k - 1);
        assertEq(l.totalCheckIns(), 9 * k + (k - 1));
        assertFalse(l.daysOf(you) * 10 >= l.totalCheckIns(), "you are just under the average: not covered");
        (, uint256 back) = StreakVault(l.vault()).claimable(you);
        assertEq(back, uint256(1000 ether) * 29 / 299, "96.99 test USD");
        assertLt(back, 100 ether, "under the deposit");
        assertGe(back * k, 100 ether * (k - 1), "but never under (k - 1) / k of it");
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    /// @dev Plays a whole round from the seeds with `bps` of the deposits to the shop, launches it, checks the
    ///      guarantee in the launch transaction, lets tax arrive with claims in between, and checks every payout.
    function _playAndLaunch(Seeds memory s, uint256 bps) internal returns (Round memory r) {
        r = _build(s, bps);
        _openRound(r);
        _play(r);
        _launch(r);
        _checkAtLaunch(r);
        _taxAndClaims(r);
        _checkPaid(r);
    }

    /// @dev What a member at or above the average is guaranteed, in test USD: the part of the deposit that is prize.
    function _guaranteed(Round memory r) internal pure returns (uint256) {
        return r.deposit * (10_000 - r.bps) / 10_000;
    }

    function _build(Seeds memory s, uint256 bps) internal pure returns (Round memory r) {
        r.n = bound(s.members, 1, MAX_MEMBERS);
        r.deposit = bound(s.deposit, 1, 1e27);
        r.bps = bps;
        r.sponsor = bound(s.sponsor, SHOP_FLOOR, 1e30);
        r.stray = bound(s.stray, 0, 1e27);
        r.tax = bound(s.tax, 0, 1e30);
        r.members = new address[](r.n);
        r.streak = new uint256[](r.n);
        r.joinDay = new uint256[](r.n);
        for (uint256 i; i < r.n; ++i) {
            r.members[i] = address(uint160(0x5EA5_0000 + i));
            // Joins from day 0 (before the first check-in) to day 30 (after the last one: a late joiner with no
            // days, who still counts in the average). Days are consecutive from the join day.
            r.joinDay[i] = bound(s.joinDays[i], 0, SEASON_DAYS);
            r.streak[i] = bound(s.streaks[i], 0, SEASON_DAYS - r.joinDay[i]);
            r.total += r.streak[i];
        }
        if (r.total == 0) {
            // A launch needs at least one check-in.
            r.joinDay[0] = 0;
            r.streak[0] = 1;
            r.total = 1;
        }
        r.goal = bound(s.goal, 1, r.total);
    }

    function _openRound(Round memory r) internal {
        RoundConfig memory c = _config();
        c.deposit = r.deposit;
        c.liquidityBps = r.bps;
        c.checkInGoal = r.goal;
        c.deadline = block.timestamp + (SEASON_DAYS + 5) * 1 days;
        r.launcher = _open(c);
        portal.setFloor(SHOP_FLOOR);
    }

    /// @dev Day 0 to day 30: members join on their join day, then check in on each of their days.
    function _play(Round memory r) internal {
        for (uint256 day; day <= SEASON_DAYS; ++day) {
            for (uint256 i; i < r.n; ++i) {
                if (r.joinDay[i] == day) _join(r.launcher, r.members[i]);
                if (day >= r.joinDay[i] && day < r.joinDay[i] + r.streak[i]) {
                    _checkIn(r.launcher, r.members[i], _today());
                }
            }
            if (day < SEASON_DAYS) vm.warp(block.timestamp + 1 days);
        }
        assertEq(r.launcher.memberCount(), r.n);
        assertEq(r.launcher.totalCheckIns(), r.total);
    }

    function _launch(Round memory r) internal {
        _sponsor(r.launcher, sponsorWallet, r.sponsor);
        if (r.stray != 0) usd.mint(address(r.launcher), r.stray); // a plain transfer: it becomes prize
        vm.prank(stranger);
        r.launcher.launch();
        r.vault = StreakVault(r.launcher.vault());

        uint256 deposits = r.n * r.deposit;
        uint256 shopShare = deposits * r.bps / 10_000;
        assertEq(usd.balanceOf(portal.POOL()), r.sponsor + shopShare, "the shop: sponsor money + the deposits' share");
        assertEq(
            r.vault.quoteReceived(), deposits - shopShare + r.stray, "the prize: the rest, in the same transaction"
        );
    }

    /// @dev The guarantee already holds in the launch transaction, before any tax.
    function _checkAtLaunch(Round memory r) internal view {
        uint256 floorBack = _guaranteed(r);
        uint256 received = r.vault.quoteReceived();
        for (uint256 i; i < r.n; ++i) {
            (, uint256 back) = r.vault.claimable(r.members[i]);
            assertEq(back, received * r.streak[i] / r.total, "share = received x days / all days");
            if (r.streak[i] * r.n >= r.total) assertGe(back, floorBack, "kept up: covered at launch");
        }
    }

    /// @dev Even members claim the prize share at once; a third of the tax arrives; odd members claim; the rest
    ///      arrives; everyone with something to claim claims.
    function _taxAndClaims(Round memory r) internal {
        for (uint256 i; i < r.n; i += 2) {
            _claimIfAny(r, i);
        }
        uint256 first = r.tax / 3;
        usd.mint(address(r.vault), first);
        for (uint256 i = 1; i < r.n; i += 2) {
            _claimIfAny(r, i);
        }
        usd.mint(address(r.vault), r.tax - first);
        for (uint256 i; i < r.n; ++i) {
            _claimIfAny(r, i);
        }
    }

    function _claimIfAny(Round memory r, uint256 i) internal {
        (uint256 coins, uint256 back) = r.vault.claimable(r.members[i]);
        if (coins == 0 && back == 0) return;
        vm.prank(r.members[i]);
        r.vault.claim();
    }

    /// @dev Members held nothing but the deposit they paid in, so their test USD balance is what they were paid.
    function _checkPaid(Round memory r) internal view {
        uint256 floorBack = _guaranteed(r);
        uint256 received = r.vault.quoteReceived();
        assertEq(received, r.n * r.deposit - r.n * r.deposit * r.bps / 10_000 + r.stray + r.tax, "prize + tax");
        IERC20 coin = IERC20(r.launcher.token());
        uint256 top;
        for (uint256 i; i < r.n; ++i) {
            uint256 paid = usd.balanceOf(r.members[i]);
            assertEq(paid, received * r.streak[i] / r.total, "paid by days, not by dollars");
            assertEq(coin.balanceOf(r.members[i]), RESERVE * r.streak[i] / r.total, "coins by days");
            if (r.streak[i] * r.n >= r.total) assertGe(paid, floorBack, "kept up with the average: covered");
            if (r.streak[i] > r.streak[top]) top = i;
        }
        // "If nobody showed up more than you": the member with the most days is always at or above the average.
        assertGe(usd.balanceOf(r.members[top]), floorBack, "the top member is always covered");
    }
}
