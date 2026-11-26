// Your round (/round/<launcher>): what a member gets back, the receipt of
// their deposit, how the round ends, the one next step in each state, the
// steps of a join as the state really runs them, and the ways in (a round
// card, a deep link, a join from Home).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/router.dart';
import 'package:pacepact/screens/checkin_sheet.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/screens/round_screen.dart';
import 'package:pacepact/util/format.dart';
import 'package:pacepact/util/next_action.dart';
import 'package:pacepact/util/pot.dart';
import 'package:pacepact/widgets/common.dart';

import 'support.dart';

Finder button(String label) =>
    find.byWidgetPredicate((w) => w is PillButton && w.label == label);

/// Your round alone, on a screen tall enough to build every section.
Future<void> pumpRound(WidgetTester tester, AppState state) async {
  usePhone(tester, size: const Size(390, 2600));
  await tester.pumpWidget(inApp(RoundScreen(state: state, launcher: launcher)));
  await settle(tester);
}

/// The whole app with its router, as main.dart builds it.
Future<void> pumpApp(
  WidgetTester tester,
  AppState state, {
  String? location,
}) async {
  usePhone(tester, size: const Size(390, 1400));
  await tester.pumpWidget(
    MaterialApp.router(
      theme: inAppTheme,
      routerConfig: buildRouter(state, initialLocation: location),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: AppBackdrop(child: child!),
      ),
    ),
  );
  await settle(tester, 12);
}

/// The text of [key]'s Text widget.
String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// The ending card marked "Now".
Finder endingNowIn(RoundEnding ending) => find.descendant(
  of: find.byKey(Key('ending-${ending.name}')),
  matching: find.byKey(const Key('ending-now')),
);

void main() {
  tearDown(() {
    bannerNote.value = null;
    auroraTone.value = AuroraPalette.ink;
  });

  group('the next step', () {
    RoundNext next({
      bool member = true,
      bool launched = false,
      bool pastDeadline = false,
      int days = 1,
      bool checkedInToday = false,
      bool barFull = false,
      bool poolShort = false,
      bool hasClaimable = false,
      num refundable = 0,
      bool chainRead = true,
    }) => nextStep(
      member: member,
      launched: launched,
      pastDeadline: pastDeadline,
      days: days,
      checkedInToday: checkedInToday,
      barFull: barFull,
      poolShort: poolShort,
      hasClaimable: hasClaimable,
      refundable: usd(refundable),
      chainRead: chainRead,
    );

    test('open round: join, check in, done for today', () {
      expect(next(member: false), RoundNext.join);
      expect(next(), RoundNext.checkIn);
      expect(next(days: 0), RoundNext.checkIn);
      expect(next(checkedInToday: true), RoundNext.doneToday);
    });

    test('a full bar launches only when the pool meets the floor', () {
      expect(next(barFull: true), RoundNext.launch);
      expect(next(barFull: true, member: false), RoundNext.launch);
      expect(next(barFull: true, poolShort: true), RoundNext.checkIn);
      expect(
        next(barFull: true, poolShort: true, checkedInToday: true),
        RoundNext.doneToday,
      );
    });

    test('after the launch: claim with a share, else the result', () {
      expect(next(launched: true, hasClaimable: true), RoundNext.claim);
      expect(next(launched: true), RoundNext.result);
      expect(next(launched: true, days: 0), RoundNext.result);
      // 0 days never claims, whatever the vault says.
      expect(
        next(launched: true, days: 0, hasClaimable: true),
        RoundNext.result,
      );
    });

    test('after a missed deadline: refund while something is owed', () {
      expect(next(pastDeadline: true, refundable: 100), RoundNext.refund);
      expect(next(pastDeadline: true), RoundNext.ended);
      // The contract could not be read: a member is offered Refund.
      expect(next(pastDeadline: true, chainRead: false), RoundNext.refund);
      expect(
        next(pastDeadline: true, chainRead: false, member: false),
        RoundNext.ended,
      );
      // A launch at the deadline wins over the refund.
      expect(
        next(pastDeadline: true, launched: true, hasClaimable: true),
        RoundNext.claim,
      );
    });

    test('the ending that applies now', () {
      RoundEnding end({bool launched = false, bool past = false, int d = 1}) =>
          endingNow(launched: launched, pastDeadline: past, days: d);
      expect(end(), RoundEnding.withDays);
      expect(end(d: 0), RoundEnding.noDays);
      expect(end(launched: true), RoundEnding.withDays);
      expect(end(launched: true, d: 0), RoundEnding.noDays);
      expect(end(past: true), RoundEnding.refund);
      expect(end(past: true, d: 0), RoundEnding.refund);
    });
  });

  group('the receipt', () {
    test('100 test USD at 30%: 30 to the pool, 70 to the prize', () {
      // The judges' round: deposit 100, goal 12. Two of five check-ins.
      final m = YourMoney(
        deposit: usd(100),
        liquidityBps: 3000,
        prize: usd(350),
        days: 2,
        total: 5,
      );
      expect(m.toPool, usd(30));
      expect(m.toPrize, usd(70));
      expect(m.toPool + m.toPrize, m.deposit);
      expect(m.share, '40%');
      // StreakVault: prize * days / total, rounded down.
      expect(m.projected, usd(140));
      expect(m.projected, shareOf(usd(350), 2, 5));
    });

    test('1,000 test USD at 25%, a third of the check-ins', () {
      final m = YourMoney(
        deposit: usd(1000),
        liquidityBps: 2500,
        prize: usd(2250),
        days: 1,
        total: 3,
      );
      expect(m.toPool, usd(250));
      expect(m.toPrize, usd(750));
      expect(m.share, '33.3%');
      // 2250 / 3 = 750 exactly.
      expect(m.projected, usd(750));
    });

    test('rounding down, as the contracts do', () {
      // 333.33... test USD in base units: never more than the prize.
      final m = YourMoney(
        deposit: BigInt.from(1001),
        liquidityBps: 3333,
        prize: BigInt.from(1000),
        days: 1,
        total: 3,
      );
      expect(m.toPool, BigInt.from(333)); // 1001 * 3333 / 10000 = 333.6
      expect(m.toPrize, BigInt.from(668));
      expect(m.projected, BigInt.from(333));
    });

    test('0 days is 0 and 0%', () {
      final m = YourMoney(
        deposit: usd(100),
        liquidityBps: 3000,
        prize: usd(700),
        days: 0,
        total: 5,
      );
      expect(m.projected, BigInt.zero);
      expect(m.share, '0%');
    });
  });

  group('words', () {
    test('a moment in local time, with its weekday', () {
      expect(formatMoment(DateTime(2026, 11, 30, 7, 34)), 'Mon 30 Nov, 07:34');
      expect(formatMoment(DateTime(2026, 12, 2, 0, 5)), 'Wed 2 Dec, 00:05');
    });

    test('what is left until the deadline', () {
      expect(formatTimeLeft(const Duration(days: 3, hours: 2)), '3 days left');
      expect(formatTimeLeft(const Duration(hours: 25)), '1 day left');
      expect(formatTimeLeft(const Duration(hours: 5, minutes: 59)), '5 h left');
      expect(formatTimeLeft(const Duration(minutes: 40)), '40 min left');
      expect(
        formatTimeLeft(const Duration(seconds: 10)),
        'under a minute left',
      );
      expect(formatTimeLeft(Duration.zero), isNull);
      expect(formatTimeLeft(const Duration(hours: -1)), isNull);
    });

    test('what a check-in did to the share', () {
      expect(
        shareChangeSentence(1, 4, 2, 5),
        'Your share went from 25% to 40%.',
      );
      expect(
        shareChangeSentence(0, 0, 1, 1),
        'Your share went from 0% to 100%.',
      );
      expect(shareChangeSentence(1, 1, 2, 2), 'Your share stays at 100%.');
    });
  });

  group('Your round', () {
    testWidgets('a member with days: the projection, the receipt, the week', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 2, totalCheckIns: 4),
        server: FakeServer()
          ..me = meJson(daysOf: 2, streak: 2, days: ['2026-11-24', today]),
      );
      await pumpRound(tester, state);

      // The header: name, state, the deadline in local time and what is
      // left of it.
      expect(textOf(tester, 'round-name'), 'Morning Movers');
      expect(find.text('Open'), findsOneWidget);
      final deadline = DateTime.utc(2026, 12, 2);
      expect(
        textOf(tester, 'round-deadline'),
        'Closes ${formatMoment(deadline)}',
      );
      expect(textOf(tester, 'round-left'), '6 days left');

      // The hero: 2 of the 4 check-ins of a 2,100 prize, as a projection.
      final hero = find.byKey(const Key('round-hero'));
      expect(
        find.descendant(of: hero, matching: find.text('1,050')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: hero,
          matching: find.text('If it launched now, you\'d get'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('and 50% of the members\' half of the token'),
        findsOneWidget,
      );
      expect(find.textContaining('A projection:'), findsOneWidget);
      expect(
        textOf(tester, 'round-hero-call'),
        'Check in today and your share goes to 60%.',
      );

      // The receipt, row by row.
      final ledger = find.byKey(const Key('round-ledger'));
      for (final (label, value) in [
        ('Deposit paid', '1,000 test USD'),
        ('Goes to the token pool', '300 test USD'),
        ('Goes to the prize', '700 test USD'),
        ('Your days shown up', '2 of 4 check-ins'),
        ('Your share now', '50%'),
      ]) {
        expect(
          find.descendant(of: ledger, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
        expect(
          find.descendant(of: ledger, matching: find.text(value)),
          findsOneWidget,
          reason: value,
        );
      }
      expect(find.text('For good once it launches'), findsOneWidget);

      // How it ends: the launch with days applies now.
      expect(endingNowIn(RoundEnding.withDays), findsOneWidget);
      expect(find.byKey(const Key('ending-now')), findsOneWidget);
      expect(
        find.textContaining('If it launched now: 1,050 test USD and 50%'),
        findsOneWidget,
      );
      expect(
        find.text('Not launched by ${formatMoment(deadline)}'),
        findsOneWidget,
      );
      expect(
        find.text('Your 1,000 test USD comes back with Refund.'),
        findsOneWidget,
      );

      // The week and today.
      expect(textOf(tester, 'round-today'), 'Today: not yet');

      // One action: check in.
      expect(button('Check in'), findsOneWidget);
      expect(find.byType(PillButton), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d USD')), findsNothing);
    });

    testWidgets('0 days: 0 test USD so far, and a call to check in', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 0, totalCheckIns: 2),
      );
      await pumpRound(tester, state);

      final hero = find.byKey(const Key('round-hero'));
      expect(find.descendant(of: hero, matching: find.text('0')), findsOne);
      expect(
        find.descendant(of: hero, matching: find.text('test USD so far')),
        findsOneWidget,
      );
      expect(
        textOf(tester, 'round-hero-call'),
        'Check in today to earn a share.',
      );
      expect(endingNowIn(RoundEnding.noDays), findsOneWidget);
      expect(find.text('Your share now'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(button('Check in'), findsOneWidget);
    });

    testWidgets('checked in today: done, and when the next one opens', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(
          isMember: true,
          daysOf: 1,
          totalCheckIns: 3,
          checkedInToday: true,
        ),
      );
      await pumpRound(tester, state);
      final opens = formatTime(nextUtcDay(fixedNow).toLocal());
      expect(textOf(tester, 'round-hint'), 'Next check-in opens at $opens.');
      final done = tester.widget<PillButton>(button('Done for today'));
      expect(done.onPressed, isNull);
      expect(textOf(tester, 'round-today'), 'Today: checked in');
      expect(find.byKey(const Key('round-hero-call')), findsNothing);
    });

    testWidgets('after the launch: what the vault holds, and Claim', (
      tester,
    ) async {
      final chain = FakeChain(
        isMember: true,
        launched: true,
        daysOf: 2,
        totalCheckIns: 3,
        claimableQuote: 822.32,
        claimableTokens: 1000,
      );
      final state = await makeState(
        chain: chain,
        server: FakeServer()
          ..round = roundJson(launched: true, totalCheckIns: 3),
      );
      await pumpRound(tester, state);

      expect(find.text('Launched'), findsOneWidget);
      expect(find.text('Yours from the vault so far'), findsOneWidget);
      expect(find.text('822.32'), findsOneWidget);
      expect(find.text('Your share'), findsOneWidget);
      expect(endingNowIn(RoundEnding.withDays), findsOneWidget);
      expect(find.text('In the token pool for good'), findsOneWidget);
      // Check-ins are closed: no "today" line.
      expect(find.byKey(const Key('round-today')), findsNothing);

      await tester.tap(button('Claim · 822.32 test USD'));
      await settle(tester);
      expect(chain.calls, ['claim']);
      expect(bannerNote.value!.text, 'Your share is in your wallet.');
      expect(state.steps, isNull);
      // Claimed: what the vault paid stays the hero; the next step is the
      // result.
      expect(find.text('822.32'), findsOneWidget);
      expect(
        find.text('All claimed so far. Trading tax keeps adding to it.'),
        findsOneWidget,
      );
      expect(button('See the result'), findsOneWidget);
    });

    testWidgets('launched with 0 days: nothing comes back', (tester) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, launched: true, totalCheckIns: 3),
        server: FakeServer()
          ..round = roundJson(launched: true, totalCheckIns: 3),
      );
      await pumpRound(tester, state);
      expect(
        find.text('You had 0 days at launch, so nothing comes back.'),
        findsOneWidget,
      );
      expect(endingNowIn(RoundEnding.noDays), findsOneWidget);
      expect(button('See the result'), findsOneWidget);
    });

    testWidgets('after the deadline: Refund gives the deposit back', (
      tester,
    ) async {
      final chain = FakeChain(
        isMember: true,
        daysOf: 1,
        totalCheckIns: 2,
        refundable: 1000,
      );
      final state = await makeState(
        chain: chain,
        now: DateTime.utc(2026, 12, 3, 9),
      );
      await pumpRound(tester, state);

      expect(find.text('Ended'), findsOneWidget);
      expect(find.byKey(const Key('round-left')), findsNothing);
      expect(find.text('Comes back to you'), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
      expect(endingNowIn(RoundEnding.refund), findsOneWidget);
      expect(find.textContaining('Refund is open now'), findsOneWidget);
      expect(find.text('Comes back with Refund'), findsNWidgets(2));

      await tester.tap(button('Refund · 1,000 test USD'));
      await settle(tester);
      expect(chain.calls, ['refund']);
      expect(bannerNote.value!.text, 'Your deposit is back.');
      expect(state.refundedFrom(launcher), isTrue);
      expect(find.text('test USD, back in your wallet'), findsOneWidget);
      expect(
        tester.widget<PillButton>(button('Round ended')).onPressed,
        isNull,
      );
    });

    testWidgets('a full bar with enough in the pool: Launch, step by step', (
      tester,
    ) async {
      final chain = FakeChain(
        isMember: true,
        daysOf: 2,
        totalCheckIns: 6,
        pool: 1500,
        checkedInToday: true,
      );
      final state = await makeState(
        chain: chain,
        server: FakeServer()..round = roundJson(totalCheckIns: 6),
      );
      final seen = <String>[];
      state.addListener(() {
        final s = state.steps;
        if (s != null && (seen.isEmpty || seen.last != s.steps[s.current])) {
          seen.add(s.steps[s.current]);
        }
      });
      await pumpRound(tester, state);
      expect(find.text('Bar full'), findsOneWidget);
      await tester.tap(button('Launch Morning Movers'));
      await settle(tester);
      expect(chain.calls, ['launch']);
      // The steps moved only as the state did them.
      expect(seen, ['Launch on Flap', 'Read the result']);
      expect(bannerNote.value!.text, 'Launched. The token is live.');
    });

    testWidgets('not a member: one button to join', (tester) async {
      final state = await makeState();
      await pumpRound(tester, state);
      expect(find.text('Join to earn a share'), findsOneWidget);
      expect(find.byKey(const Key('round-ledger')), findsNothing);
      expect(button('Join · 1,000 test USD'), findsOneWidget);
    });
  });

  group('joining, step by step', () {
    test('a wallet without the deposit: get, approve, pay', () async {
      final gate = Completer<void>();
      final chain = FakeChain()..joinGate = gate.future;
      final state = await makeState(chain: chain);
      final run = state.joinRound(launcher: launcher);
      await pumpEventQueue();
      final steps = state.stepsFor(StepAction.join, launcher: launcher)!;
      expect(steps.steps, [
        ActionSteps.getDollars,
        ActionSteps.approve,
        ActionSteps.pay,
      ]);
      // Minted and approved: the join itself is running.
      expect(steps.steps[steps.current], ActionSteps.pay);
      expect(chain.calls, ['mint 1000']);
      gate.complete();
      expect(await run, '0xj1');
      expect(state.steps, isNull);
      expect(chain.calls, ['mint 1000', 'join 1000']);
    });

    test('a wallet that holds the deposit: approve, pay', () async {
      final chain = FakeChain(dollars: 2500);
      final state = await makeState(chain: chain);
      final seen = <String>[];
      state.addListener(() {
        final s = state.steps;
        if (s != null) {
          expect(s.steps, [ActionSteps.approve, ActionSteps.pay]);
          if (seen.isEmpty || seen.last != s.steps[s.current]) {
            seen.add(s.steps[s.current]);
          }
        }
      });
      await state.joinRound(launcher: launcher);
      expect(seen, [ActionSteps.approve, ActionSteps.pay]);
      expect(chain.calls, ['join 1000']);
    });

    test('a failed step ends the steps', () async {
      final state = await makeState(chain: FakeChain(fail: 'join'));
      await expectLater(state.joinRound(launcher: launcher), throwsException);
      expect(state.steps, isNull);
    });
  });

  group('the ways in', () {
    testWidgets('a deep link opens Your round; back leads Home', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 2, totalCheckIns: 4),
      );
      await pumpApp(tester, state, location: '/round/$launcher');
      expect(find.byType(RoundScreen), findsOneWidget);
      expect(textOf(tester, 'round-name'), 'Morning Movers');
      expect(state.selected, launcher);

      await tester.tap(find.byKey(const Key('round-back')));
      await settle(tester, 12);
      expect(find.byType(RoundScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('a deep link in capitals, and one to nothing', (tester) async {
      final state = await makeState(chain: FakeChain(isMember: true));
      await pumpApp(
        tester,
        state,
        location: '/round/${launcher.toUpperCase().replaceFirst('0X', '0x')}',
      );
      expect(find.byType(RoundScreen), findsOneWidget);
      expect(textOf(tester, 'round-name'), 'Morning Movers');

      await pumpApp(tester, state, location: '/round/not-a-round');
      expect(find.byType(RoundScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('a deep link before onboarding keeps the round', (
      tester,
    ) async {
      final store = MemoryStore();
      final state = await makeState(wallet: false, store: store);
      await pumpApp(tester, state, location: '/round/$launcher');
      expect(find.byType(RoundScreen), findsNothing);
      // Remembered for after the first-run step.
      expect(
        (store.rounds!['known'] as List).map((k) => k['launcher']),
        contains(launcher),
      );
    });

    testWidgets('the card of a round you are in opens Your round', (
      tester,
    ) async {
      final state = await makeState(chain: FakeChain(isMember: true));
      await pumpApp(tester, state, location: '/');
      expect(find.text('You\'re in · Your round'), findsOneWidget);
      await tester.tap(find.byKey(const Key('round-card-open')));
      await settle(tester, 12);
      expect(find.byType(RoundScreen), findsOneWidget);
      // Back pops to Home.
      await tester.tap(find.byKey(const Key('round-back')));
      await settle(tester, 12);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('THE PRIZE "You" row opens Your round', (tester) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 3),
      );
      await pumpApp(tester, state, location: '/');
      await tester.ensureVisible(find.byKey(const Key('pot-you-open')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pot-you-open')));
      await settle(tester, 12);
      expect(find.byType(RoundScreen), findsOneWidget);
    });

    testWidgets('the Wallet\'s "In rounds" row opens Your round', (
      tester,
    ) async {
      final state = await makeState(chain: FakeChain(isMember: true));
      await pumpApp(tester, state, location: '/account');
      final row = find.byKey(const Key('wallet-round-$launcher'));
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await settle(tester, 12);
      expect(find.byType(RoundScreen), findsOneWidget);
    });

    testWidgets('a screen reader can open the Wallet\'s round row', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final state = await makeState(chain: FakeChain(isMember: true));
      await pumpApp(tester, state, location: '/account');
      final row = find.byKey(const Key('wallet-round-$launcher'));
      await tester.ensureVisible(row);
      await tester.pump();
      final label = RegExp('^Your round Morning Movers, ');
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(isButton: true, hasTapAction: true, isFocusable: true),
      );
      tester.semantics.tap(find.semantics.byLabel(label));
      await settle(tester, 12);
      expect(find.byType(RoundScreen), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('joining from Home lands on Your round, Check in ready', (
      tester,
    ) async {
      final chain = FakeChain();
      final state = await makeState(chain: chain);
      await pumpApp(tester, state, location: '/');
      await tester.tap(button('Join Morning Movers · 1,000 USD'));
      await settle(tester, 14);
      await tester.tap(button('Join with test dollars · 1,000 test USD'));
      await settle(tester, 14);

      expect(chain.calls, ['mint 1000', 'join 1000']);
      expect(find.byType(RoundScreen), findsOneWidget);
      expect(
        bannerNote.value!.text,
        'You\'re in. Check in today to start your share.',
      );
      expect(find.byKey(const Key('round-checkin')), findsOneWidget);
      expect(find.byKey(const Key('round-join-tx')), findsOneWidget);
    });

    testWidgets('a check-in shows the new share, then Your round again', (
      tester,
    ) async {
      final chain = FakeChain(isMember: true, daysOf: 1, totalCheckIns: 3);
      final server = FakeServer()
        ..members = [
          {
            'address': '0x2000000000000000000000000000000000000002',
            'daysOf': 2,
            'streak': 2,
            'checkedInToday': true,
          },
        ];
      final state = await makeState(chain: chain, server: server);
      await pumpApp(tester, state, location: '/round/$launcher');
      expect(find.text('33.3%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('round-checkin')));
      await settle(tester, 14);
      await tester.enterText(find.byKey(const Key('steps')), '6214');
      await tester.tap(
        find.descendant(
          of: find.byType(CheckInSheet),
          matching: button('Check in'),
        ),
      );
      await settle(tester, 14);
      expect(chain.calls, ['checkIn 20782']);
      expect(
        textOf(tester, 'checkin-share-moved'),
        'Your share went from 33.3% to 50%.',
      );
      expect(button('Back to your round'), findsOneWidget);

      // A moment later the sheet closes by itself on Your round.
      await tester.pump(CheckInSheet.linger);
      await settle(tester, 14);
      expect(find.byType(CheckInSheet), findsNothing);
      expect(find.byType(RoundScreen), findsOneWidget);
      expect(button('Done for today'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });
  });
}
