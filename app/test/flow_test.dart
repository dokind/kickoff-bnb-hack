// The join sheet's two steps, the check-in on the web and on a phone,
// onboarding and routing, the result, Wallet, "Add a round" and the
// new-round screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/config.dart';
import 'package:pacepact/router.dart';
import 'package:pacepact/screens/account_screen.dart';
import 'package:pacepact/screens/add_round_sheet.dart';
import 'package:pacepact/screens/checkin_sheet.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/screens/invite_sheet.dart';
import 'package:pacepact/screens/join_sheet.dart';
import 'package:pacepact/screens/new_round_screen.dart';
import 'package:pacepact/screens/onboarding_screen.dart';
import 'package:pacepact/screens/result_screen.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/theme/tokens.dart';
import 'package:pacepact/util/format.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/dot_matrix.dart';
import 'package:pacepact/widgets/gauges.dart';
import 'package:pacepact/widgets/main_tabs.dart';
import 'package:pacepact/widgets/tab_bar.dart';
import 'package:web3dart/web3dart.dart';

import 'support.dart';

Finder button(String label) =>
    find.byWidgetPredicate((w) => w is PillButton && w.label == label);

bool enabled(WidgetTester tester, String label) =>
    tester.widget<PillButton>(button(label)).onPressed != null;

/// Scrolls the pill into view (the test font is wide, so screens are tall)
/// and presses it.
Future<void> press(WidgetTester tester, String label) async {
  await tester.ensureVisible(button(label));
  await tester.pump();
  await tester.tap(button(label));
}

Future<void> pumpBody(WidgetTester tester, Widget body) async {
  usePhone(tester);
  await tester.pumpWidget(inApp(body));
  await settle(tester);
}

/// The whole app with its router, as main.dart builds it.
Future<void> pumpApp(
  WidgetTester tester,
  AppState state, {
  String? location,
}) async {
  usePhone(tester);
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

/// The new-round screen in a router beside Home, in a build that has its
/// contract addresses (the tests' own build has none).
Future<void> pumpNewRound(WidgetTester tester, AppState state) async {
  usePhone(tester);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: inAppTheme,
      routerConfig: GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => HomeScreen(state: state),
          ),
          GoRoute(
            path: '/new',
            builder: (_, _) => NewRoundScreen(state: state, missing: const []),
          ),
        ],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: AppBackdrop(child: child!),
      ),
    ),
  );
  await settle(tester, 12);
}

/// Presses the chip that says [text] in the picker with [key].
Future<void> pick(WidgetTester tester, String key, String text) async {
  final chip = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.text(text),
  );
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await settle(tester);
}

/// The control the keyboard is on: a pressable's name, an action row's
/// title, or the key of a text field.
String? focusedName() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final field = context.findAncestorWidgetOfExactType<TextField>();
  if (field != null) return '${field.key}';
  return context.findAncestorWidgetOfExactType<Pressable>()?.label ??
      context.findAncestorWidgetOfExactType<ActionRow>()?.title;
}

/// Presses Tab until the keyboard is on [name]; fails when it never gets
/// there. Returns every control it passed on the way, [name] included.
Future<List<String?>> tabTo(WidgetTester tester, String name) async {
  final passed = <String?>[];
  for (var i = 0; i < 40 && focusedName() != name; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    passed.add(focusedName());
  }
  expect(focusedName(), name, reason: 'Tab reaches "$name"');
  return passed;
}

/// A round being started that the test lets through when it says so, and a
/// membership read it can hold open the same way.
class SlowChain extends FakeChain {
  Completer<void>? holdCreate;
  Completer<void>? holdMember;

  @override
  Future<bool> isMemberOf(String launcher, String member) async {
    await holdMember?.future;
    return super.isMemberOf(launcher, member);
  }

  @override
  Future<String> createRound(
    EthPrivateKey key, {
    required String name,
    required String symbol,
    required BigInt deposit,
    required int liquidityBps,
    required int checkInGoal,
    required DateTime deadline,
    void Function()? onMined,
  }) async {
    await holdCreate?.future;
    return super.createRound(
      key,
      name: name,
      symbol: symbol,
      deposit: deposit,
      liquidityBps: liquidityBps,
      checkInGoal: checkInGoal,
      deadline: deadline,
      onMined: onMined,
    );
  }
}

const unlistedNoteText =
    'Not shown in the public list. Anyone with the link can still join, and '
    'the chain is public.';

void main() {
  tearDown(() {
    bannerNote.value = null;
    auroraTone.value = AuroraPalette.ink;
  });

  group('join sheet', () {
    testWidgets('shows the deposit and where it goes', (tester) async {
      final state = await makeState();
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

      expect(find.text('Pay the deposit'), findsOneWidget);
      expect(find.text('Deposit'), findsOneWidget);
      // Every amount reads as test money.
      expect(find.text('1,000 test USD'), findsOneWidget);
      expect(find.text('To the prize'), findsOneWidget);
      expect(find.text('700 test USD · 70%'), findsOneWidget);
      expect(find.text('Into the shop'), findsOneWidget);
      expect(find.text('300 test USD · 30%'), findsOneWidget);
      expect(find.text('If it launches'), findsOneWidget);
      expect(find.text('Last day to launch'), findsOneWidget);
      expect(find.text('2 Dec 2026'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d USD')), findsNothing);
      // The two steps. The first says plainly what it stands in for.
      await tester.scrollUntilVisible(
        find.textContaining('Testnet: free test dollars.'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(
          'Testnet: free test dollars. On mainnet this step is paying with '
          'a stablecoin.',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Pay deposit'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Approves, then pays 1,000 test USD'),
        findsOneWidget,
      );
    });

    testWidgets('one press mints, approves and joins, step by step', (
      tester,
    ) async {
      final gate = Completer<void>();
      final chain = FakeChain()..joinGate = gate.future;
      final state = await makeState(chain: chain);
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

      // One button does every step: the wallet holds no test USD yet.
      expect(button('Get test dollars'), findsNothing);
      expect(button('Join with test dollars · 1,000 test USD'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.tap(button('Join with test dollars · 1,000 test USD'));
      await settle(tester);

      // The dollars are minted and approved; the join is on its way. The
      // steps say so, from what the state really did.
      expect(chain.calls, ['mint 1000']);
      expect(find.byKey(const Key('join-progress')), findsOneWidget);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('join-progress')),
          matching: find.text('Pay the deposit'),
        ),
        findsOneWidget,
      );
      expect(state.steps!.steps, [
        'Get test dollars',
        'Approve test USD',
        'Pay the deposit',
      ]);
      expect(find.text('Joining…'), findsOneWidget);

      gate.complete();
      await settle(tester);
      expect(chain.calls, ['mint 1000', 'join 1000']);
      expect(state.steps, isNull);
      expect(state.isMember, isTrue);
      expect(state.joinTxOf(launcher), '0xj1');
      expect(find.text('YOU\'RE IN.'), findsOneWidget);
      // The round is open: today's check-in is the way on, or later.
      expect(button('Check in now'), findsOneWidget);
      expect(button('Later'), findsOneWidget);
      expect(
        tester.widget<PillButton>(button('Check in now')).kind,
        PillKind.volt,
      );
    });

    testWidgets('a wallet that already holds the deposit starts at step 2', (
      tester,
    ) async {
      final state = await makeState(chain: FakeChain(dollars: 2500));
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));
      expect(button('Get test dollars'), findsNothing);
      expect(button('Pay deposit · 1,000 test USD'), findsOneWidget);
    });

    testWidgets('waits for the faucet\'s gas: "Preparing your wallet"', (
      tester,
    ) async {
      final chain = FakeChain(bnb: 0);
      final state = AppState(
        store: MemoryStore(key: testKey, onboarded: true),
        chain: chain,
        api: FakeServer().api,
        health: FakeHealth(),
        clock: () => fixedNow,
        gasPoll: const Duration(seconds: 3),
        gasPollTries: 5,
      );
      await state.init();
      await state.refresh();
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

      await tester.tap(button('Join with test dollars · 1,000 test USD'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Preparing your wallet:'), findsOneWidget);
      expect(find.text('Preparing your wallet…'), findsOneWidget);
      // The wallet had no fees: that is the first of four steps.
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.text('Prepare your wallet'), findsOneWidget);
      expect(chain.calls, isEmpty, reason: 'nothing is sent without gas');

      // The faucet's transfer arrives, and the join goes all the way.
      chain.bnb = usd(0.03);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.textContaining('Preparing your wallet'), findsNothing);
      expect(chain.calls, ['mint 1000', 'join 1000']);
      expect(find.text('YOU\'RE IN.'), findsOneWidget);
    });

    testWidgets('a failed step is one sentence and the button says Try again', (
      tester,
    ) async {
      final chain = FakeChain(fail: 'mint');
      final state = await makeState(chain: chain);
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

      await tester.tap(button('Join with test dollars · 1,000 test USD'));
      await settle(tester);
      expect(find.text('The mint was rejected. Try again.'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(chain.calls, isEmpty, reason: 'nothing was paid');
      expect(state.steps, isNull);
      // "Try again" runs the whole join again, from the step that failed.
      await tester.tap(button('Try again'));
      await settle(tester);
      expect(chain.calls, ['mint 1000', 'join 1000']);
      expect(find.text('YOU\'RE IN.'), findsOneWidget);
    });

    testWidgets('the two endings and what can be lost, over the pay button', (
      tester,
    ) async {
      final state = await makeState(chain: FakeChain(dollars: 2500));
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

      const lines = [
        // CheckInLauncher.refund(): the whole deposit after a missed
        // deadline.
        'No launch by the deadline: press Refund and your 1,000 test USD '
            'comes back.',
        // The other ending: StreakVault pays by days.
        'It launches: you\'re paid by your days, not by your deposit.',
        // StreakVault: shares by days; no day, no share.
        'It launches and you have no check-ins: nothing comes back.',
        // launch(): liquidityBps of the deposits seeds the pool; Flap burns
        // the LP.
        'It launches: 30% of your deposit goes into the shop, locked forever.',
      ];
      final pay = tester.getRect(button('Pay deposit · 1,000 test USD'));
      var above = 0.0;
      for (final line in lines) {
        expect(find.text(line), findsOneWidget, reason: line);
        final rect = tester.getRect(find.text(line));
        // In order, all of them over the button, none of them hidden.
        expect(rect.top, greaterThan(above), reason: line);
        expect(rect.bottom, lessThanOrEqualTo(pay.top), reason: line);
        above = rect.top;
      }
      // Plain, in the sheet's quiet text, not an error.
      final style = tester.widget<Text>(find.text(lines[2])).style!;
      expect(style.color, AppColors.dark.text2);
      expect(style.fontSize, greaterThanOrEqualTo(12));
      expect(find.byKey(const Key('join-late')), findsNothing);
      // 30% of each deposit goes into the shop: no deposit-back promise.
      expect(find.byKey(const Key('join-keep-up')), findsNothing);
      expect(find.textContaining('the average'), findsNothing);
      expect(find.text('300 test USD · 30%'), findsOneWidget);
    });

    testWidgets('no shop share: the Keep-Up lines, and no shop line', (
      tester,
    ) async {
      final server = FakeServer()..round!['liquidityBps'] = 0;
      final state = await makeState(
        server: server,
        chain: FakeChain(dollars: 2500),
      );
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));
      const lines = [
        'No launch by the deadline: press Refund and your 1,000 test USD '
            'comes back.',
        'It launches: you\'re paid by your days, not by your deposit.',
        // The prize is every deposit, so days at or above the average get
        // at least the deposit back (StreakVault: prize x days / all days).
        'It launches and your days are at least the average: your whole '
            'deposit back, or more.',
        'Fewer days than the average: you get back less.',
        'It launches and you have no check-ins: nothing comes back.',
      ];
      var above = 0.0;
      for (final line in lines) {
        expect(find.text(line), findsOneWidget, reason: line);
        final top = tester.getRect(find.text(line)).top;
        expect(top, greaterThan(above), reason: line);
        above = top;
      }
      expect(find.byKey(const Key('join-keep-up')), findsOneWidget);
      expect(find.textContaining('goes into the shop'), findsNothing);
      expect(find.text('None · a sponsor fills it'), findsOneWidget);
      expect(find.text('1,000 test USD · 100%'), findsOneWidget);
    });

    testWidgets('one check-in from full: a warning, and "Join anyway"', (
      tester,
    ) async {
      final chain = FakeChain(dollars: 2500);
      final server = FakeServer()..round = roundJson(totalCheckIns: 5);
      final state = await makeState(server: server, chain: chain);
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

      const warning =
          'This round can launch before your first check-in. If it does, you '
          'get nothing back.';
      expect(find.text(warning), findsOneWidget);
      expect(
        find.text('5 of 6 check-ins: one more fills the bar.'),
        findsOneWidget,
      );
      // Before paying: over the button.
      expect(
        tester.getRect(find.text(warning)).bottom,
        lessThan(tester.getRect(button('Pay deposit · 1,000 test USD')).top),
      );

      // The first press pays nothing: it asks again, in other words.
      await tester.tap(button('Pay deposit · 1,000 test USD'));
      await settle(tester);
      expect(chain.calls, isEmpty);
      expect(button('Pay deposit · 1,000 test USD'), findsNothing);
      expect(button('Join anyway'), findsOneWidget);
      expect(find.text(warning), findsOneWidget);

      // The second, explicit press pays.
      await tester.tap(button('Join anyway'));
      await settle(tester);
      expect(chain.calls, ['join 1000']);
      expect(find.text('YOU\'RE IN.'), findsOneWidget);
      expect(button('Check in now'), findsOneWidget);
    });

    testWidgets('a small phone: the warning, the lines and the button fit', (
      tester,
    ) async {
      final state = await makeState(
        server: FakeServer()..round = roundJson(totalCheckIns: 5),
        chain: FakeChain(dollars: 2500),
      );
      usePhone(tester, size: const Size(375, 667));
      await tester.pumpWidget(
        inApp(JoinSheet(state: state, round: state.round!)),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      final pay = tester.getRect(button('Pay deposit · 1,000 test USD'));
      expect(pay.bottom, lessThanOrEqualTo(667));
      expect(find.byKey(const Key('join-late')), findsOneWidget);
      // The part over the button scrolls by itself when it is cramped: its
      // window ends over the button and starts with the warning.
      final window = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('join-outcomes')),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(window.bottom, lessThanOrEqualTo(pay.top));
      expect(
        tester.getRect(find.byKey(const Key('join-late'))).top,
        greaterThanOrEqualTo(window.top),
      );
      expect(window.height, greaterThan(100));
    });

    testWidgets('320x568 with text at 1.5: the late sheet still fits', (
      tester,
    ) async {
      final state = await makeState(
        server: FakeServer()..round = roundJson(totalCheckIns: 5),
        chain: FakeChain(dollars: 2500),
      );
      usePhone(tester, size: const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        inApp(JoinSheet(state: state, round: state.round!)),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('join-late')), findsOneWidget);
      final pay = tester.getRect(button('Pay deposit · 1,000 test USD'));
      expect(pay.bottom, lessThanOrEqualTo(568));
    });

    testWidgets('a full bar warns too; a round far from full does not', (
      tester,
    ) async {
      final full = await makeState(
        server: FakeServer()..round = roundJson(totalCheckIns: 6),
        chain: FakeChain(dollars: 2500),
      );
      await pumpBody(tester, JoinSheet(state: full, round: full.round!));
      expect(find.byKey(const Key('join-late')), findsOneWidget);
      expect(find.text('The bar is full: 6 of 6 check-ins.'), findsOneWidget);

      // Three to go with three members: one check-in each fills the bar
      // today, so the round can launch before this wallet's first day.
      final today = await makeState(
        server: FakeServer()..round = roundJson(totalCheckIns: 3),
        chain: FakeChain(dollars: 2500),
      );
      await tester.pumpWidget(const SizedBox());
      await pumpBody(tester, JoinSheet(state: today, round: today.round!));
      expect(find.byKey(const Key('join-late')), findsOneWidget);
      expect(
        find.text('3 of 6 check-ins. The bar can fill today.'),
        findsOneWidget,
      );

      // Four to go with three members (the default round): it cannot fill
      // today, and one press pays, as before.
      final chain = FakeChain(dollars: 2500);
      final open = await makeState(
        server: FakeServer()..round = roundJson(totalCheckIns: 2),
        chain: chain,
      );
      await tester.pumpWidget(const SizedBox());
      await pumpBody(tester, JoinSheet(state: open, round: open.round!));
      expect(find.byKey(const Key('join-late')), findsNothing);
      await tester.tap(button('Pay deposit · 1,000 test USD'));
      await settle(tester);
      expect(chain.calls, ['join 1000']);
    });

    testWidgets('"Check in now" opens today\'s check-in for the same round', (
      tester,
    ) async {
      final chain = FakeChain(dollars: 2500);
      final server = FakeServer();
      final state = await makeState(chain: chain, server: server);
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showJoinSheet(context, state, state.round!),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester, 14);
      await tester.tap(button('Pay deposit · 1,000 test USD'));
      await settle(tester, 14);
      expect(find.text('YOU\'RE IN.'), findsOneWidget);

      await tester.tap(button('Check in now'));
      await settle(tester, 20);
      // The join sheet has closed and the check-in sheet is open on the
      // round that was just joined.
      expect(find.byType(JoinSheet), findsNothing);
      expect(find.byType(CheckInSheet), findsOneWidget);
      expect(
        tester.widget<CheckInSheet>(find.byType(CheckInSheet)).round.id,
        launcher,
      );
      expect(find.text('Check in today'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('steps')), '6214');
      await tester.tap(button('Check in'));
      await settle(tester, 14);
      expect(chain.calls, ['join 1000', 'checkIn 20782']);
      expect(find.text('CHECKED IN.'), findsOneWidget);
    });

    testWidgets('"Later" closes the sheet', (tester) async {
      final state = await makeState(chain: FakeChain(dollars: 2500));
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showJoinSheet(context, state, state.round!),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester, 14);
      await tester.tap(button('Pay deposit · 1,000 test USD'));
      await settle(tester, 14);
      await tester.tap(button('Later'));
      await settle(tester, 14);
      expect(find.byType(JoinSheet), findsNothing);
      expect(find.byType(CheckInSheet), findsNothing);
    });
  });

  group('a Season squad: the join sheet', () {
    const closedNote =
        'The contract still takes joins; the app stops here so everyone '
        'starts fair.';

    testWidgets('before the start: when it starts, and nothing to check in', (
      tester,
    ) async {
      final chain = FakeChain(dollars: 2500, deposit: 100, pool: 1500);
      final state = await makeState(
        server: FakeServer()..round = seasonRoundJson(),
        chain: chain,
      );
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

      expect(
        find.text('Season 1 · Starts Tue 1 Dec. Everyone starts at 0.'),
        findsOneWidget,
      );
      // Under the title.
      expect(
        tester.getRect(find.byKey(const Key('join-season'))).top,
        greaterThan(tester.getRect(find.text('Pay the deposit')).bottom),
      );
      expect(find.text('None · a sponsor fills it'), findsOneWidget);
      expect(find.byKey(const Key('join-keep-up')), findsOneWidget);
      expect(
        find.text(
          'No launch by the deadline: press Refund and your 100 test USD '
          'comes back.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('join-closed-note')), findsNothing);
      expect(find.byKey(const Key('join-late')), findsNothing);

      await tester.tap(button('Pay deposit · 100 test USD'));
      await settle(tester);
      expect(chain.calls, ['join 100']);
      expect(find.text('YOU\'RE IN.'), findsOneWidget);
      // No check-in before the start: no "Check in now", and the sheet says
      // when.
      expect(
        tester.widget<Text>(find.byKey(const Key('join-done-text'))).data,
        '100 test USD is in the round\'s contract. Season 1 check-ins open '
        'Tue 1 Dec (07:00 in Bangkok). Everyone starts at 0.',
      );
      expect(button('Check in now'), findsNothing);
      expect(button('Let\'s go'), findsOneWidget);
    });

    testWidgets('late in the window: the day, and the days left', (
      tester,
    ) async {
      final chain = FakeChain(dollars: 2500, deposit: 100, pool: 1500);
      final state = await makeState(
        server: FakeServer()
          ..round = seasonRoundJson(totalCheckIns: 16, memberCount: 4),
        chain: chain,
        now: DateTime.utc(2026, 12, 5, 9),
      );
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));
      expect(find.text('Season 1 · Day 5 of 30: 26 days left'), findsOneWidget);
      await tester.tap(button('Pay deposit · 100 test USD'));
      await settle(tester);
      expect(chain.calls, ['join 100']);
      // Started: today's check-in is the way on.
      expect(button('Check in now'), findsOneWidget);
    });

    testWidgets('after 7 Dec the app stops offering Join', (tester) async {
      final chain = FakeChain(dollars: 2500, deposit: 100, pool: 1500);
      final state = await makeState(
        server: FakeServer()
          ..round = seasonRoundJson(totalCheckIns: 21, memberCount: 3),
        chain: chain,
        now: DateTime.utc(2026, 12, 8, 9),
      );
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

      final closed = tester.widget<PillButton>(
        find.byKey(const Key('join-closed')),
      );
      expect(closed.label, 'Joining closed 7 Dec');
      expect(closed.onPressed, isNull);
      expect(find.text(closedNote), findsOneWidget);
      // Over the button.
      expect(
        tester.getRect(find.text(closedNote)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('join-closed'))).top,
        ),
      );
      expect(button('Pay deposit · 100 test USD'), findsNothing);
      await tester.tap(find.byKey(const Key('join-closed')));
      await settle(tester);
      expect(chain.calls, isEmpty, reason: 'nothing is paid');
    });

    testWidgets('at 10 members the squad is full', (tester) async {
      final chain = FakeChain(dollars: 2500, deposit: 100, pool: 1500);
      final state = await makeState(
        server: FakeServer()..round = seasonRoundJson(memberCount: 10),
        chain: chain,
      );
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));
      final closed = tester.widget<PillButton>(
        find.byKey(const Key('join-closed')),
      );
      expect(closed.label, 'Squad full');
      expect(closed.onPressed, isNull);
      expect(find.text(closedNote), findsOneWidget);
      // The Season line still says when it starts.
      expect(
        find.text('Season 1 · Starts Tue 1 Dec. Everyone starts at 0.'),
        findsOneWidget,
      );
      // Nine of ten: Join is offered.
      await tester.pumpWidget(const SizedBox());
      final nine = await makeState(
        server: FakeServer()..round = seasonRoundJson(memberCount: 9),
        chain: FakeChain(dollars: 2500, deposit: 100, pool: 1500),
      );
      await pumpBody(tester, JoinSheet(state: nine, round: nine.round!));
      expect(find.byKey(const Key('join-closed')), findsNothing);
      expect(button('Pay deposit · 100 test USD'), findsOneWidget);
    });

    testWidgets('a small phone with large text: the closed sheet fits', (
      tester,
    ) async {
      final state = await makeState(
        server: FakeServer()..round = seasonRoundJson(memberCount: 10),
        chain: FakeChain(dollars: 2500, deposit: 100, pool: 1500),
      );
      usePhone(tester, size: const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        inApp(JoinSheet(state: state, round: state.round!)),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      final pill = tester.getRect(find.byKey(const Key('join-closed')));
      expect(pill.bottom, lessThanOrEqualTo(568));
      // The note leads the part over the button that scrolls by itself.
      final window = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('join-outcomes')),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(window.bottom, lessThanOrEqualTo(pill.top));
      expect(
        tester.getRect(find.byKey(const Key('join-closed-note'))).top,
        greaterThanOrEqualTo(window.top),
      );
    });
  });

  group('a Season squad: the check-in guard', () {
    /// A page with one button that opens the check-in sheet for the round.
    Future<void> pumpOpener(WidgetTester tester, AppState state) async {
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showCheckInSheet(context, state, state.round!),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('before 1 Dec: no sheet, the reason, and no call at all', (
      tester,
    ) async {
      final server = FakeServer()..round = seasonRoundJson();
      final chain = FakeChain(isMember: true, deposit: 100, pool: 1500);
      final state = await makeState(server: server, chain: chain);
      await pumpOpener(tester, state);
      server.requests.clear();

      await tester.tap(find.text('open'));
      await settle(tester, 14);
      expect(find.byType(CheckInSheet), findsNothing);
      expect(
        bannerNote.value!.text,
        'Season 1 check-ins open Tue 1 Dec (07:00 in Bangkok). Everyone '
        'starts at 0.',
      );
      expect(server.requests, isEmpty);
      expect(chain.calls, isEmpty);
    });

    testWidgets('after 30 Dec: "check-ins ended", and no call', (tester) async {
      final server = FakeServer()
        ..round = seasonRoundJson(totalCheckIns: 230, memberCount: 10);
      final chain = FakeChain(isMember: true, deposit: 100, daysOf: 25);
      final state = await makeState(
        server: server,
        chain: chain,
        now: DateTime.utc(2026, 12, 31, 3),
      );
      await pumpOpener(tester, state);
      server.requests.clear();
      await tester.tap(find.text('open'));
      await settle(tester, 14);
      expect(find.byType(CheckInSheet), findsNothing);
      expect(
        bannerNote.value!.text,
        'Season 1 check-ins have ended. The last day was Wed 30 Dec.',
      );
      expect(server.requests, isEmpty);
      expect(chain.calls, isEmpty);
    });

    testWidgets('from 1 Dec, 00:00 UTC the sheet opens as for any round', (
      tester,
    ) async {
      final state = await makeState(
        server: FakeServer()..round = seasonRoundJson(),
        chain: FakeChain(isMember: true, deposit: 100, pool: 1500),
        now: DateTime.utc(2026, 12, 1),
      );
      await pumpOpener(tester, state);
      await tester.tap(find.text('open'));
      await settle(tester, 14);
      expect(find.byType(CheckInSheet), findsOneWidget);
      expect(bannerNote.value, isNull);
    });
  });

  group('check-in', () {
    testWidgets('web: a number field labelled self-reported, then the tx', (
      tester,
    ) async {
      final chain = FakeChain(isMember: true);
      final server = FakeServer();
      final state = await makeState(chain: chain, server: server);
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));

      expect(find.text('Self-reported, testnet only'), findsOneWidget);
      // The caveats onboarding no longer shows in a browser are here, where
      // the steps are typed.
      expect(
        find.textContaining('A browser cannot read health data.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your step count goes to our server, which signs the day: '
          'check-ins are attested, not proven. Only the day goes on chain.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('steps')), findsOneWidget);
      // An empty field says what to type and cannot be sent: a number shown
      // as a placeholder once read as if it were filled in.
      expect(find.text('Type today\'s steps'), findsOneWidget);
      await tester.tap(button('Check in'));
      await settle(tester);
      expect(server.bodies['/rounds/$launcher/checkin'], isNull);
      expect(find.text('Type today\'s steps first.'), findsOneWidget);
      // Typing clears the sentence and the button is "Check in" again.
      await tester.enterText(find.byKey(const Key('steps')), '6214');
      await tester.pump();
      expect(find.text('Type today\'s steps first.'), findsNothing);
      await tester.tap(button('Check in'));
      await settle(tester);

      expect(server.bodies['/rounds/$launcher/checkin']!['steps'], 6214);
      expect(server.bodies['/rounds/$launcher/checkin']!['source'], 'self');
      // The app sends checkIn(dayIndex, attesterSignature) itself.
      expect(chain.calls, ['checkIn 20782']);
      expect(find.text('CHECKED IN.'), findsOneWidget);
      final link = tester.widget<LinkRow>(find.byType(LinkRow));
      expect(link.label, 'Transaction');
      expect(link.url, startsWith('https://testnet.bscscan.com/tx/0xc1c1'));
    });

    testWidgets('web: too few steps is said before anything is sent', (
      tester,
    ) async {
      final server = FakeServer();
      final state = await makeState(
        chain: FakeChain(isMember: true),
        server: server,
      );
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));

      await tester.enterText(find.byKey(const Key('steps')), '12');
      await tester.tap(button('Check in'));
      await settle(tester);
      expect(
        find.text(
          'A check-in needs at least 1,000 steps today. You have 12 so far.',
        ),
        findsOneWidget,
      );
      expect(server.count('POST /rounds/$launcher/checkin'), 0);
      expect(button('Try again'), findsOneWidget);
    });

    testWidgets('phone: today\'s steps are read from Health and posted', (
      tester,
    ) async {
      final chain = FakeChain(isMember: true);
      final server = FakeServer();
      final state = await makeState(
        chain: chain,
        server: server,
        health: FakeHealth(available: true, steps: 6214),
      );
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));

      expect(find.text('6,214'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.byKey(const Key('steps')), findsNothing);
      expect(find.text('Self-reported, testnet only'), findsNothing);
      await tester.tap(button('Check in'));
      await settle(tester);
      expect(server.bodies['/rounds/$launcher/checkin']!['steps'], 6214);
      expect(
        server.bodies['/rounds/$launcher/checkin']!['source'],
        'healthkit',
      );
      expect(chain.calls, ['checkIn 20782']);
      expect(find.text('CHECKED IN.'), findsOneWidget);
    });

    testWidgets('phone: under the minimum the action waits', (tester) async {
      final health = FakeHealth(available: true, steps: 300);
      final state = await makeState(
        chain: FakeChain(isMember: true),
        health: health,
      );
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));

      expect(find.text('300'), findsOneWidget);
      expect(find.text('Keep going'), findsOneWidget);
      expect(enabled(tester, 'Check in'), isFalse);
      health.steps = 1200;
      await tester.tap(button('Sync again'));
      await settle(tester);
      expect(find.text('1,200'), findsOneWidget);
      expect(enabled(tester, 'Check in'), isTrue);
    });

    testWidgets('phone: no steps read is no dead end; typed steps go as '
        '"self"', (tester) async {
      final chain = FakeChain(isMember: true);
      final server = FakeServer();
      final health = FakeHealth(available: true, steps: 0);
      final state = await makeState(
        chain: chain,
        server: server,
        health: health,
      );
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));

      expect(find.text('No steps from Health Connect today.'), findsOneWidget);
      expect(button('Sync again'), findsOneWidget);
      expect(button('Fix in Health Connect'), findsOneWidget);
      expect(enabled(tester, 'Check in'), isFalse);
      await tester.ensureVisible(find.text('Type today\'s steps instead'));
      await tester.pump();
      await tester.tap(find.text('Type today\'s steps instead'));
      await settle(tester);
      expect(find.text('Self-reported, testnet only'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('steps')), '4321');
      await press(tester, 'Check in');
      await settle(tester);
      expect(server.bodies['/rounds/$launcher/checkin']!['steps'], 4321);
      expect(server.bodies['/rounds/$launcher/checkin']!['source'], 'self');
      expect(chain.calls, ['checkIn 20782']);
      expect(find.text('CHECKED IN.'), findsOneWidget);
    });

    testWidgets('the server\'s refusal is shown as its own sentence', (
      tester,
    ) async {
      final server = FakeServer()
        ..checkInStatus = 409
        ..checkIn = {
          'error': 'already_checked_in',
          'message': 'You already checked in today.',
        };
      final chain = FakeChain(isMember: true);
      final state = await makeState(chain: chain, server: server);
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));

      await tester.enterText(find.byKey(const Key('steps')), '6214');
      await tester.tap(button('Check in'));
      await settle(tester);
      expect(find.text('You already checked in today.'), findsOneWidget);
      expect(chain.calls, isEmpty);
    });

    testWidgets('signed but not on chain yet: "Finish check-in"', (
      tester,
    ) async {
      final chain = FakeChain(isMember: true, fail: 'checkIn');
      final server = FakeServer();
      final state = await makeState(chain: chain, server: server);
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));

      await tester.enterText(find.byKey(const Key('steps')), '6214');
      await tester.tap(button('Check in'));
      await settle(tester);
      expect(find.text('The checkIn was rejected. Try again.'), findsOneWidget);
      expect(find.byKey(const Key('steps')), findsNothing);
      await tester.tap(button('Try again'));
      await settle(tester);
      expect(
        server.count('POST /rounds/$launcher/checkin'),
        1,
        reason: 'asked once',
      );
      expect(chain.calls, ['checkIn 20782']);
      expect(find.text('CHECKED IN.'), findsOneWidget);
    });
  });

  group('onboarding and routing', () {
    testWidgets('a new device in a browser: hero, one button, then Home', (
      tester,
    ) async {
      final store = MemoryStore();
      final server = FakeServer();
      final state = await makeState(
        wallet: false,
        store: store,
        server: server,
        chain: FakeChain(bnb: 0),
      );
      await pumpApp(tester, state, location: '/account');

      // Everything starts at onboarding: a hero line, a sentence, a button.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('RUN THE\nSTAKES.'), findsOneWidget);
      expect(find.byType(PillButton), findsOneWidget);
      expect(find.textContaining('wallet'), findsNothing);
      // The sub-line: what any round asks, with no number that a round
      // reached by a link could contradict.
      expect(
        find.text(
          'Put in a test deposit. Show up each day. Split the prize with '
          'everyone who did.',
        ),
        findsOneWidget,
      );

      await press(tester, 'Get started');
      await settle(tester, 12);
      // The wallet was made silently and the faucet asked in the background.
      expect(store.key, isNotNull);
      expect(server.count('POST /faucet'), 1);
      // A browser has no health store to connect, so the step that would
      // only list caveats is skipped: they are in the check-in sheet.
      expect(find.text('CHECK IN\nIN THE BROWSER'), findsNothing);
      expect(button('Continue'), findsNothing);
      expect(store.onboarded, isTrue);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(button('Join Morning Movers · 1,000 USD'), findsOneWidget);
    });

    testWidgets('a phone: connect the health store, or not now', (
      tester,
    ) async {
      final health = FakeHealth(available: true);
      final state = await makeState(
        wallet: false,
        store: MemoryStore(),
        health: health,
      );
      await pumpApp(tester, state);

      await press(tester, 'Get started');
      await settle(tester, 12);
      // A phone keeps the step: it asks for the one permission it needs.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(state.onboarded, isFalse);
      expect(find.text('CONNECT\nHEALTH CONNECT'), findsOneWidget);
      expect(find.text('Steps today'), findsOneWidget);
      expect(find.text('Check-ins are attested, not proven.'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Not now')).height,
        greaterThanOrEqualTo(44),
      );
      await press(tester, 'Allow access');
      await settle(tester, 12);
      expect(health.asked, 1);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('"Not now" skips the permission and still finishes', (
      tester,
    ) async {
      final health = FakeHealth(available: true);
      final state = await makeState(
        wallet: false,
        store: MemoryStore(),
        health: health,
      );
      await pumpApp(tester, state);
      await press(tester, 'Get started');
      await settle(tester, 12);
      await tester.ensureVisible(find.text('Not now'));
      await tester.pump();
      await tester.tap(find.text('Not now'));
      await settle(tester, 12);
      expect(health.asked, 0);
      expect(state.onboarded, isTrue);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('a returning device opens Home and never onboarding', (
      tester,
    ) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/onboarding');
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('the floating bar goes from Home to Wallet and back', (
      tester,
    ) async {
      final state = await makeState();
      await pumpApp(tester, state);
      await tester.tap(find.byTooltip('Wallet'));
      await settle(tester, 12);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.text('WALLET'), findsOneWidget);
      expect(
        tester.widget<FloatingTabBar>(find.byType(FloatingTabBar)).current,
        MainTabs.wallet,
      );
      await tester.tap(find.byTooltip('Home'));
      await settle(tester, 12);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('/wallet is the Wallet screen too', (tester) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/wallet');
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.text('WALLET'), findsOneWidget);
    });

    testWidgets('addresses of earlier builds lead Home', (tester) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/clubs');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('/r/<launcher> opens Home with that round selected', (
      tester,
    ) async {
      final server = FakeServer()
        ..more.addAll([
          roundJson(at: launcherB, name: 'Lumpini Striders'),
          roundJson(at: launcherC, name: 'Night Owls'),
        ]);
      // Unlisted: the public list leaves it out, the link still opens it.
      server.unlisted.add(launcherC);
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(server: server, store: store);
      expect(state.selected, launcher);
      expect(state.rounds.map((r) => r.id), [launcher, launcherB]);

      await pumpApp(tester, state, location: '/r/$launcherC');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.selected, launcherC);
      expect(state.rounds.map((r) => r.id), contains(launcherC));
      expect(find.text('Night Owls'), findsOneWidget);
      expect(find.text('Unlisted'), findsOneWidget);
      // Kept: the round stays on this device's slider and is the one
      // selected at the next launch.
      expect(store.rounds!['selected'], launcherC);
      final again = await makeState(server: server, store: store);
      expect(again.selected, launcherC);
    });

    testWidgets('/r/<launcher> survives onboarding on a new device', (
      tester,
    ) async {
      final server = FakeServer()
        ..more.add(roundJson(at: launcherB, name: 'Lumpini Striders'));
      server.unlisted.add(launcherB);
      final store = MemoryStore();
      final state = await makeState(
        wallet: false,
        store: store,
        server: server,
      );
      await pumpApp(tester, state, location: '/r/$launcherB');

      // No wallet yet: the first-run steps come first, and they name the
      // round the link was for and its deposit.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(state.selected, isNull);
      await settle(tester);
      expect(
        find.text(
          'You\'re invited to Lumpini Striders. Put in 1,000 test USD, show '
          'up each day, and split the prize with everyone who did.',
        ),
        findsOneWidget,
      );
      // In a browser there is no permission to ask for: "Get started" is
      // the only step.
      await press(tester, 'Get started');
      await settle(tester, 12);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.selected, launcherB);
      expect(find.text('Lumpini Striders'), findsOneWidget);
      expect(button('Join Lumpini Striders · 1,000 USD'), findsOneWidget);
    });

    testWidgets('a link to something that is not a round says so', (
      tester,
    ) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/r/$launcherD');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.selected, launcher);
      expect(bannerNote.value!.text, 'That link does not lead to a round.');
      // A link that is not an address at all just leads Home.
      final other = await makeState();
      await pumpApp(tester, other, location: '/r/nonsense');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('the result opens only after the launch', (tester) async {
      final open = await makeState();
      await pumpApp(tester, open, location: '/result');
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('"Claim · Morning Movers" on Home opens the result', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(
          launched: true,
          isMember: true,
          daysOf: 3,
          totalCheckIns: 6,
          claimableTokens: 250000,
          claimableQuote: 1050,
        ),
        server: FakeServer()
          ..round = roundJson(launched: true, totalCheckIns: 6),
      );
      await pumpApp(tester, state);
      await tester.tap(button('Claim · Morning Movers'));
      await settle(tester, 12);
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text('THE COIN\nIS LIVE.'), findsOneWidget);
      // Back leads Home again.
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, 12);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('result', () {
    testWidgets('token links, your days, your share, and Claim', (
      tester,
    ) async {
      final chain = FakeChain(
        launched: true,
        isMember: true,
        daysOf: 3,
        totalCheckIns: 6,
        claimableTokens: 250000,
        claimableQuote: 1068.59,
      );
      final state = await makeState(
        chain: chain,
        server: FakeServer()
          ..round = roundJson(launched: true, totalCheckIns: 6),
      );
      await pumpBody(tester, ResultScreen(state: state));

      expect(find.text(tokenAddress), findsOneWidget);
      final links = tester.widgetList<LinkRow>(find.byType(LinkRow)).toList();
      expect(links[0].label, 'View on BscScan testnet');
      expect(links[0].url, 'https://testnet.bscscan.com/token/$tokenAddress');
      expect(links[1].label, 'Open on Flap');
      expect(links[1].url, 'https://flap.sh/bnb-testnet/$tokenAddress');

      // Your days and your part of the whole.
      expect(find.text('Your days'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('/ 6'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);

      // Your share: test USD in dot-matrix numerals, and tokens.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('250,000'),
        200,
        scrollable: list,
      );
      expect(
        tester.widget<DotMatrixText>(find.byType(DotMatrixText)).text,
        '1,068.59',
      );
      expect(find.text('coins'), findsOneWidget);
      // The tax reaches the piggy bank for the coin's first 30 days only.
      await tester.scrollUntilVisible(
        find.byKey(const Key('result-tax')),
        200,
        scrollable: list,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('result-tax'))).data,
        'Tax arrives for 30 days after the launch, and only when people '
        'trade. Claim again whenever there is more.',
      );

      await tester.tap(button('Claim'));
      await settle(tester);
      expect(chain.calls, ['claim']);
      expect(button('Nothing more to claim yet'), findsOneWidget);
      expect(enabled(tester, 'Nothing more to claim yet'), isFalse);
      await tester.scrollUntilVisible(
        find.textContaining('250,000 coins · 1,068.59 test USD'),
        200,
        scrollable: list,
      );
    });

    testWidgets('no days: nothing to claim, and no Claim button', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(launched: true, totalCheckIns: 6),
        server: FakeServer()
          ..round = roundJson(launched: true, totalCheckIns: 6),
      );
      await pumpBody(tester, ResultScreen(state: state));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.textContaining('there is no share to claim'),
        200,
        scrollable: list,
      );
      expect(button('Claim'), findsNothing);
      expect(find.text(tokenAddress), findsOneWidget);
    });
  });

  group('wallet', () {
    testWidgets('the balance first, then the address; nothing about rounds', (
      tester,
    ) async {
      final state = await makeState(chain: FakeChain(dollars: 1000));
      await pumpBody(tester, AccountScreen(state: state, showBar: false));

      expect(find.text('WALLET'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsNothing);
      expect(
        tester.widget<DotMatrixText>(find.byType(DotMatrixText)).text,
        '1,000',
      );
      expect(find.text('test USD'), findsOneWidget);
      // One name for it everywhere: "test BNB", as the sentences say.
      expect(find.text('0.03 test BNB'), findsOneWidget);
      expect(find.textContaining('tBNB'), findsNothing);
      expect(find.text('BSC testnet'), findsOneWidget);
      expect(
        find.text('Test money on BSC testnet. It has no real value.'),
        findsOneWidget,
      );
      // The gauge nobody could read is gone.
      expect(find.byType(TickGauge), findsNothing);
      // The balance is the first thing under the title.
      expect(
        tester.getTopLeft(find.byType(BalanceCard)).dy,
        lessThan(tester.getTopLeft(find.text('Address')).dy),
      );

      // The list: address, back up, another wallet, about.
      expect(find.text(shortAddress(state.address)), findsOneWidget);
      expect(find.text('Back up your key'), findsOneWidget);
      expect(find.text('Use another wallet'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      for (final row in tester.widgetList<ActionRow>(find.byType(ActionRow))) {
        expect(
          tester.getSize(find.byWidget(row)).height,
          greaterThanOrEqualTo(48),
          reason: row.title,
        );
      }

      // No round controls here any more, and the key is not on the screen.
      expect(find.byKey(const Key('round-name')), findsNothing);
      expect(find.byKey(const Key('open-round')), findsNothing);
      expect(find.byKey(const Key('round-unlisted')), findsNothing);
      expect(find.byType(ChipPicker<int>), findsNothing);
      expect(button('Start round'), findsNothing);
      expect(button('Open round'), findsNothing);
      expect(
        find.textContaining(RegExp('round', caseSensitive: false)),
        findsNothing,
      );
      expect(find.text(testKeyHex), findsNothing);
    });

    testWidgets('the money in open rounds, and the wallet on BscScan', (
      tester,
    ) async {
      final chain = FakeChain(isMember: true, dollars: 250)
        ..others[launcherB] = FakeChain(isMember: true, deposit: 500)
        ..others[launcherC] = FakeChain(isMember: true, launched: true)
        ..others[launcherD] = FakeChain();
      final server = FakeServer()
        ..more.addAll([
          roundJson(at: launcherB, name: 'Lumpini Striders')
            ..['deposit'] = '500',
          // Launched: its deposit has left the contract.
          roundJson(at: launcherC, name: 'Night Owls', launched: true),
          // Not a member.
          roundJson(at: launcherD, name: 'Sunrise Club'),
        ]);
      final state = await makeState(chain: chain, server: server);
      await pumpBody(tester, AccountScreen(state: state, showBar: false));

      final row = find.byKey(const Key('wallet-in-rounds'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.text('In rounds: 1,500 test USD'),
        ),
        findsOneWidget,
      );
      // One row per round, each with its deposit; each opens Your round.
      for (final (at, name, amount) in [
        (launcher, 'Morning Movers', '1,000 test USD'),
        (launcherB, 'Lumpini Striders', '500 test USD'),
      ]) {
        final line = find.byKey(Key('wallet-round-$at'));
        expect(
          find.descendant(of: row, matching: line),
          findsOneWidget,
          reason: name,
        );
        expect(
          find.descendant(of: line, matching: find.text(name)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: line, matching: find.text(amount)),
          findsOneWidget,
        );
      }
      // Under the balance, inside its card.
      expect(
        find.descendant(of: find.byType(BalanceCard), matching: row),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(row).dy,
        greaterThan(tester.getTopLeft(find.byType(DotMatrixText)).dy),
      );
      expect(find.textContaining('Night Owls'), findsNothing);
      expect(find.textContaining('Sunrise Club'), findsNothing);

      final link = tester.widget<LinkRow>(
        find.byKey(const Key('wallet-bscscan')),
      );
      expect(link.label, 'View on BscScan');
      expect(link.url, 'https://testnet.bscscan.com/address/${state.address}');
    });

    testWidgets('no open round: no "In rounds" line, the link stays', (
      tester,
    ) async {
      final state = await makeState(chain: FakeChain(dollars: 1000));
      await pumpBody(tester, AccountScreen(state: state, showBar: false));
      expect(find.byKey(const Key('wallet-in-rounds')), findsNothing);
      expect(find.byKey(const Key('wallet-bscscan')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('wallet-bscscan'))).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('pressing the address row copies the address', (tester) async {
      final state = await makeState();
      await pumpBody(tester, AccountScreen(state: state, showBar: false));
      await tester.ensureVisible(find.text('Address'));
      await tester.pump();
      await tester.tap(find.text('Address'));
      await settle(tester);
      expect(bannerNote.value!.text, 'Address copied.');
    });

    testWidgets('small screen, large text: "Address" and the address whole', (
      tester,
    ) async {
      final state = await makeState();
      final short = shortAddress(state.address);
      RenderParagraph paragraph(String text) =>
          tester.renderObject<RenderParagraph>(find.text(text));

      // Room for both (the test font is wide, so a wide screen): the
      // address at the right of the title, on its line.
      await pumpBody(tester, AccountScreen(state: state, showBar: false));
      tester.view.physicalSize = const Size(480, 844);
      await settle(tester);
      final title = tester.getRect(find.text('Address'));
      final value = tester.getRect(find.text(short));
      expect(value.left, greaterThan(title.right));
      expect((value.center.dy - title.center.dy).abs(), lessThan(4));

      // 320 wide with larger text: the two do not fit on one line, so the
      // address goes under the title. Neither is broken up. (The test font
      // is about twice as wide as the app's, so 1.1 here is past 1.5 there;
      // and the screen is tall so the list stays on it.)
      tester.view.physicalSize = const Size(320, 1400);
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(tester);
      final oneLine = tester.getSize(find.text('About')).height;
      expect(tester.getSize(find.text('Address')).height, oneLine);
      expect(
        tester.getSize(find.text('Address')).width,
        greaterThanOrEqualTo(paragraph('Address').getMaxIntrinsicWidth(100)),
      );
      expect(paragraph(short).didExceedMaxLines, isFalse);
      expect(
        tester.getRect(find.text(short)).top,
        greaterThanOrEqualTo(tester.getRect(find.text('Address')).bottom),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a screen reader presses each control; the card is no button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final chain = FakeChain(dollars: 1000);
      final state = await makeState(chain: chain);
      await pumpApp(tester, state, location: '/account');

      // "Get test dollars" is a button of its own, not the whole balance
      // card, and it can be pressed.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Get test dollars')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^BALANCE'))),
        isSemantics(isButton: false, hasTapAction: false),
      );
      tester.semantics.tap(find.semantics.byLabel('Get test dollars'));
      await settle(tester);
      expect(chain.calls, ['mint 1000']);

      // The bar: each of the three says what it is and can be pressed.
      for (final label in ['Home', 'Add a round', 'Wallet']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasTapAction: true, isFocusable: true),
          reason: label,
        );
      }
      tester.semantics.tap(find.semantics.byLabel('Add a round'));
      await settle(tester, 12);
      expect(find.byType(AddRoundSheet), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('from the keyboard: "Get test dollars", the rows, the bar', (
      tester,
    ) async {
      final chain = FakeChain(dollars: 1000);
      final state = await makeState(chain: chain);
      await pumpApp(tester, state, location: '/account');

      await tabTo(tester, 'Get test dollars');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(chain.calls, ['mint 1000']);

      // The four rows, then the bar: nothing is left out.
      final passed = await tabTo(tester, 'Add a round');
      expect(
        passed,
        containsAllInOrder([
          'Address',
          'Back up your key',
          'Use another wallet',
          'About',
          'Home',
          'Add a round',
        ]),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester, 12);
      expect(find.byType(AddRoundSheet), findsOneWidget);
    });

    testWidgets('"Get test dollars" mints one deposit, like the join sheet', (
      tester,
    ) async {
      final chain = FakeChain(dollars: 1000, fail: 'mint');
      final state = await makeState(chain: chain);
      await pumpBody(tester, AccountScreen(state: state, showBar: false));

      await press(tester, 'Get test dollars');
      await settle(tester);
      // A failure is one sentence, and the button is the way on.
      expect(find.text('The mint was rejected. Try again.'), findsOneWidget);
      expect(chain.calls, isEmpty);
      await press(tester, 'Try again');
      await settle(tester);
      expect(chain.calls, ['mint 1000']);
      expect(
        tester.widget<DotMatrixText>(find.byType(DotMatrixText)).text,
        '2,000',
      );
      expect(bannerNote.value!.text, '1,000 test USD added.');
      expect(button('Get test dollars'), findsOneWidget);
    });

    testWidgets('"Get test dollars" waits for the faucet\'s gas', (
      tester,
    ) async {
      final chain = FakeChain(bnb: 0);
      final state = AppState(
        store: MemoryStore(key: testKey, onboarded: true),
        chain: chain,
        api: FakeServer().api,
        health: FakeHealth(),
        clock: () => fixedNow,
        gasPoll: const Duration(seconds: 3),
        gasPollTries: 5,
      );
      await state.init();
      await state.refresh();
      await pumpBody(tester, AccountScreen(state: state, showBar: false));

      await press(tester, 'Get test dollars');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Preparing your wallet…'), findsOneWidget);
      expect(
        find.text('Preparing your wallet: a little test BNB is on its way.'),
        findsOneWidget,
      );
      expect(chain.calls, isEmpty, reason: 'nothing is sent without gas');
      chain.bnb = usd(0.03);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(chain.calls, ['mint 1000']);
    });

    testWidgets('the back-up sheet hides the key every time it opens', (
      tester,
    ) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/account');

      Future<void> open() async {
        await tester.ensureVisible(find.text('Back up your key'));
        await tester.pump();
        await tester.tap(find.text('Back up your key'));
        await settle(tester, 12);
      }

      await open();
      expect(find.byType(BackupKeySheet), findsOneWidget);
      // On the darker palette, so its sentences keep their contrast.
      expect(
        tester.widget<SheetFrame>(find.byType(SheetFrame)).palette,
        AuroraPalette.ink,
      );
      expect(
        find.text(
          'This key is the wallet. The app keeps it on this device and '
          'nowhere else. If you delete the app or clear this site\'s data '
          'without a copy, the wallet is gone.',
        ),
        findsOneWidget,
      );
      // The key shows only after the person asks for it.
      final toggle = find.byKey(const Key('backup-show'));
      expect(
        find.descendant(of: toggle, matching: find.text('Show key')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: toggle,
          matching: find.text(
            'Anyone who sees it can take what is in this wallet.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(testKeyHex), findsNothing);
      expect(button('Copy key'), findsNothing);
      await tester.tap(toggle);
      await settle(tester);
      expect(find.text(testKeyHex), findsOneWidget);
      await tester.tap(button('Copy key'));
      await settle(tester);
      expect(bannerNote.value!.text, 'Key copied.');

      // Closed and opened again: hidden again.
      bannerNote.value = null; // the banner is over the barrier's top edge
      await tester.pump();
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);
      expect(find.byType(BackupKeySheet), findsNothing);
      expect(find.text(testKeyHex), findsNothing);
      await open();
      expect(find.byType(BackupKeySheet), findsOneWidget);
      expect(find.text(testKeyHex), findsNothing);
      expect(tester.widget<CapsuleToggle>(toggle).value, isFalse);
    });

    testWidgets('"Use another wallet" takes a pasted key', (tester) async {
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(store: store);
      await pumpApp(tester, state, location: '/account');
      await tester.ensureVisible(find.text('Use another wallet'));
      await tester.pump();
      await tester.tap(find.text('Use another wallet'));
      await settle(tester, 12);
      expect(find.byType(ImportKeySheet), findsOneWidget);
      expect(
        tester.widget<SheetFrame>(find.byType(SheetFrame)).palette,
        AuroraPalette.ink,
      );
      // Where the pasted key is kept, in the back-up sheet's own words.
      expect(
        find.text(
          'Paste a private key (64 hex characters). It replaces the wallet '
          'on this device. The app keeps it on this device and nowhere else. '
          'Back up the current key first if you still need it.',
        ),
        findsOneWidget,
      );
      // The placeholder is read like the app's other quiet sentences.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('import-key')))
            .decoration!
            .hintStyle!
            .color,
        AppColors.dark.text2,
      );

      expect(enabled(tester, 'Replace wallet'), isFalse);
      await tester.enterText(find.byKey(const Key('import-key')), 'zz' * 32);
      await settle(tester);
      await tester.tap(button('Replace wallet'));
      await settle(tester);
      expect(find.textContaining('That is not a private key'), findsOneWidget);
      expect(store.key!.address, testKey.address);
    });

    testWidgets('"About" says what a check-in proves, and names Flap', (
      tester,
    ) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/account');
      await tester.ensureVisible(find.text('About'));
      await tester.pump();
      await tester.tap(find.text('About'));
      await settle(tester, 12);
      expect(find.byType(AboutSheet), findsOneWidget);
      expect(
        tester.widget<SheetFrame>(find.byType(SheetFrame)).palette,
        AuroraPalette.ink,
      );
      expect(find.text('Built on Flap'), findsOneWidget);
      expect(
        find.textContaining('is not run or endorsed by Flap.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Check-ins are attested, not proven:'),
        findsOneWidget,
      );
      // Running is the first club, not the only one.
      expect(
        find.text(
          'Running is the first club. It works for any group where showing '
          'up can be stamped.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('scrolled to the end, the list ends above the tab bar', (
      tester,
    ) async {
      final state = await makeState();
      usePhone(tester, size: const Size(390, 560));
      await tester.pumpWidget(
        MaterialApp.router(
          theme: inAppTheme,
          routerConfig: buildRouter(state, initialLocation: '/account'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: AppBackdrop(child: child!),
          ),
        ),
      );
      await settle(tester, 12);
      final list = find.byKey(const Key('wallet-list'));
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            )
            .position
            .maxScrollExtent,
        greaterThan(0),
        reason: 'the screen is short enough to scroll',
      );
      await tester.drag(list, const Offset(0, -3000));
      await settle(tester, 12);
      expect(
        tester.getBottomLeft(find.byKey(const Key('wallet-about'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(FloatingTabBar)).dy),
      );
    });
  });

  group('add a round', () {
    testWidgets('"+" opens the sheet and is never the selected place', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final state = await makeState();
      await pumpApp(tester, state);

      FloatingTabBar bar() =>
          tester.widget<FloatingTabBar>(find.byType(FloatingTabBar));
      expect(bar().items.map((i) => i.label), [
        'Home',
        'Add a round',
        'Wallet',
      ]);
      expect(bar().items.map((i) => i.action), [false, true, false]);
      expect(bar().current, MainTabs.home);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Add a round')),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasSelectedState: false,
        ),
      );

      await tester.tap(find.byTooltip('Add a round'));
      await settle(tester, 12);
      // The sheet: two rows, nothing else.
      expect(find.byType(AddRoundSheet), findsOneWidget);
      expect(
        tester.widget<SheetFrame>(find.byType(SheetFrame)).palette,
        AuroraPalette.ink,
      );
      expect(find.text('Add a round'), findsOneWidget);
      expect(find.byType(ActionRow), findsNWidgets(2));
      expect(find.text('Start a round'), findsOneWidget);
      expect(
        find.text('Set the deposit and the goal, then invite people.'),
        findsOneWidget,
      );
      expect(find.text('Open an invite link'), findsOneWidget);
      expect(find.text('Paste a link someone sent you.'), findsOneWidget);
      final sheet = find.byType(AddRoundSheet);
      expect(
        find.descendant(of: sheet, matching: find.byType(PillButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(TextField)),
        findsNothing,
      );

      // Still on Home, and Home is still the selected place.
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);
      expect(find.byType(AddRoundSheet), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(bar().current, MainTabs.home);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Home')),
        isSemantics(hasSelectedState: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Add a round')),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasSelectedState: false,
        ),
      );

      // The same from Wallet: it opens over the place you are on.
      await tester.tap(find.byTooltip('Wallet'));
      await settle(tester, 12);
      await tester.tap(find.byTooltip('Add a round'));
      await settle(tester, 12);
      expect(find.byType(AddRoundSheet), findsOneWidget);
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(bar().current, MainTabs.wallet);
      semantics.dispose();
    });

    testWidgets('"Start a round" opens /new: no tab bar, Back returns', (
      tester,
    ) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/account');
      await tester.tap(find.byTooltip('Add a round'));
      await settle(tester, 12);
      await tester.tap(find.text('Start a round'));
      await settle(tester, 12);

      expect(find.byType(AddRoundSheet), findsNothing);
      expect(find.byType(NewRoundScreen), findsOneWidget);
      expect(find.text('NEW ROUND'), findsOneWidget);
      expect(find.byType(FloatingTabBar), findsNothing);
      expect(find.byType(MainTabs), findsNothing);
      // Back leads to where the person came from.
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, 12);
      expect(find.byType(NewRoundScreen), findsNothing);
      expect(find.byType(AccountScreen), findsOneWidget);
    });

    testWidgets('/new opened directly: no tab bar, and Back leads Home', (
      tester,
    ) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/new');
      expect(find.byType(NewRoundScreen), findsOneWidget);
      expect(find.byType(FloatingTabBar), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, 12);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('/new on a new device starts at onboarding', (tester) async {
      final state = await makeState(wallet: false, store: MemoryStore());
      await pumpApp(tester, state, location: '/new');
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(NewRoundScreen), findsNothing);
    });

    testWidgets('"Open an invite link" takes a pasted link or address', (
      tester,
    ) async {
      final server = FakeServer()
        ..more.add(roundJson(at: launcherB, name: 'Night Owls'));
      server.unlisted.add(launcherB);
      final state = await makeState(server: server);
      await pumpApp(tester, state);
      await tester.tap(find.byTooltip('Add a round'));
      await settle(tester, 12);
      await tester.tap(find.text('Open an invite link'));
      await settle(tester, 12);

      // The same sheet, now the link form.
      expect(find.byType(OpenLinkForm), findsOneWidget);
      expect(find.text('Open an invite link'), findsOneWidget);
      expect(find.text('INVITE LINK'), findsOneWidget);
      expect(find.text('Paste the link'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('open-round')))
            .decoration!
            .hintStyle!
            .color,
        AppColors.dark.text2,
      );
      expect(find.text('Start a round'), findsNothing);
      expect(enabled(tester, 'Open round'), isFalse);

      await tester.enterText(find.byKey(const Key('open-round')), 'hello');
      await settle(tester);
      await tester.tap(button('Open round'));
      await settle(tester);
      expect(
        find.text(
          'That isn\'t a round link. Paste the whole link, or the round\'s '
          'address.',
        ),
        findsOneWidget,
      );

      // An address our factory never made: said in the sheet, next to the
      // field, and not a second time in the banner.
      await tester.enterText(find.byKey(const Key('open-round')), launcherD);
      await settle(tester);
      await tester.tap(button('Open round'));
      await settle(tester, 12);
      expect(find.text('That link does not lead to a round.'), findsOneWidget);
      expect(bannerNote.value, isNull);
      expect(state.selected, launcher);
      expect(find.byType(OpenLinkForm), findsOneWidget);

      // A link to an unlisted round opens it: the sheet closes on Home with
      // that round selected.
      await tester.enterText(
        find.byKey(const Key('open-round')),
        'https://run.example/#/r/${launcherB.toUpperCase().replaceFirst('0X', '0x')}',
      );
      await settle(tester);
      await tester.tap(button('Open round'));
      await settle(tester, 12);
      expect(state.selected, launcherB);
      expect(state.round!.name, 'Night Owls');
      expect(bannerNote.value!.text, 'Round opened.');
      expect(find.byType(AddRoundSheet), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(button('Join Night Owls · 1,000 USD'), findsOneWidget);
    });

    testWidgets('a link opened from Wallet ends on Home', (tester) async {
      final server = FakeServer()
        ..more.add(roundJson(at: launcherB, name: 'Night Owls'));
      final state = await makeState(server: server);
      await pumpApp(tester, state, location: '/account');
      await tester.tap(find.byTooltip('Add a round'));
      await settle(tester, 12);
      await tester.tap(find.text('Open an invite link'));
      await settle(tester, 12);
      await tester.enterText(find.byKey(const Key('open-round')), launcherB);
      await settle(tester);
      await tester.tap(button('Open round'));
      await settle(tester, 12);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.selected, launcherB);
    });
  });

  group('new round', () {
    test('"The deal" is worked out in money from the choices', () {
      expect(
        NewRoundScreen.dealLines(
          deposit: 1000,
          bps: 3000,
          goal: 6,
          daysOpen: 7,
        ),
        [
          'Join: 1,000 test USD each, paid once.',
          'Prize: 700 test USD of each deposit, shared by days shown up.',
          'Shop: 300 test USD of each deposit (the coin\'s trading pool).',
          'Coins: 1,000,000 made at launch. Half go into the shop, half '
              'into the group\'s piggy bank, split by days.',
          'Tax: 3% on buys, 5% on sells for 30 days. 80% to the piggy bank, '
              '20% burned.',
          'Launch needs both: 6 check-ins and 1,500 test USD of shop money.',
          'Who launches: anyone, once both are there.',
          'No launch in 7 days: each member presses Refund and gets their '
              'deposit back.',
        ],
      );
      expect(
        NewRoundScreen.floorLine(deposit: 1000, bps: 3000),
        'Flap sets that floor. At this deposit it takes 5 people, or a '
        'sponsor.',
      );
      expect(
        NewRoundScreen.dealLines(
          deposit: 2000,
          bps: 5000,
          goal: 30,
          daysOpen: 1,
        ),
        [
          'Join: 2,000 test USD each, paid once.',
          'Prize: 1,000 test USD of each deposit, shared by days shown up.',
          'Shop: 1,000 test USD of each deposit (the coin\'s trading pool).',
          'Coins: 1,000,000 made at launch. Half go into the shop, half '
              'into the group\'s piggy bank, split by days.',
          'Tax: 3% on buys, 5% on sells for 30 days. 80% to the piggy bank, '
              '20% burned.',
          'Launch needs both: 30 check-ins and 1,500 test USD of shop '
              'money.',
          'Who launches: anyone, once both are there.',
          'No launch in 1 day: each member presses Refund and gets their '
              'deposit back.',
        ],
      );
      expect(
        NewRoundScreen.floorLine(deposit: 2000, bps: 5000),
        'Flap sets that floor. At this deposit it takes 2 people, or a '
        'sponsor.',
      );
      // The whole deposit in the pool: one line says there is no prize and
      // where the deposit goes, instead of "0 test USD ... shared" and a
      // "Token pool" line that repeats the deposit.
      expect(
        NewRoundScreen.dealLines(
          deposit: 2000,
          bps: 10000,
          goal: 3,
          daysOpen: 30,
        ),
        [
          'Join: 2,000 test USD each, paid once.',
          'Prize: none. The whole deposit goes into the shop.',
          'Coins: 1,000,000 made at launch. Half go into the shop, half '
              'into the group\'s piggy bank, split by days.',
          'Tax: 3% on buys, 5% on sells for 30 days. 80% to the piggy bank, '
              '20% burned.',
          'Launch needs both: 3 check-ins and 1,500 test USD of shop money.',
          'Who launches: anyone, once both are there.',
          'No launch in 30 days: each member presses Refund and gets their '
              'deposit back.',
        ],
      );
      expect(
        NewRoundScreen.floorLine(deposit: 2000, bps: 10000),
        'Flap sets that floor. At this deposit it takes 1 person, or a '
        'sponsor.',
      );
      expect(NewRoundScreen.membersForFloor(deposit: 100, bps: 1000), 150);
      // No percentages in the deal's money lines (the tax line is fixed by
      // the coin, not a choice, and says its own), and the coins and the
      // tax are said at every split: they do not depend on the split.
      for (final bps in NewRoundScreen.poolOptions) {
        final lines = NewRoundScreen.dealLines(
          deposit: 500,
          bps: bps,
          goal: 6,
          daysOpen: 7,
        );
        for (final line in lines.where((l) => !l.startsWith('Tax: '))) {
          expect(line.contains('%'), isFalse, reason: line);
        }
        expect(
          lines.where((l) => l.startsWith('Coins: ') || l.startsWith('Tax: ')),
          [
            'Coins: 1,000,000 made at launch. Half go into the shop, half '
                'into the group\'s piggy bank, split by days.',
            'Tax: 3% on buys, 5% on sells for 30 days. 80% to the piggy bank, '
                '20% burned.',
          ],
          reason: '$bps',
        );
      }
    });

    test('the hint under the goal: days to fill, from the choices', () {
      String hint(int deposit, int bps, int goal, int daysOpen) =>
          NewRoundScreen.fillHint(
            deposit: deposit,
            bps: bps,
            goal: goal,
            daysOpen: daysOpen,
          );
      // The defaults: 5 people fill the floor, 6 check-ins take 2 days.
      expect(
        hint(1000, 3000, 6, 7),
        'With 5 people checking in daily, this fills in about 2 days.',
      );
      // The floor needs 10 people at 500: they are who the hint counts.
      expect(
        hint(500, 3000, 12, 3),
        'With 10 people checking in daily, this fills in about 2 days.',
      );
      // Fewer than 5 fill the floor: it still counts 5.
      expect(
        hint(2000, 5000, 30, 7),
        'With 5 people checking in daily, this fills in about 6 days.',
      );
      expect(
        hint(2000, 10000, 3, 30),
        'With 5 people checking in daily, this fills in about 1 day.',
      );
      // Past the round's own length: it says so, on the same line.
      expect(
        hint(1000, 3000, 60, 7),
        'With 5 people checking in daily, this fills in about 12 days, '
        'longer than the round runs.',
      );
      // The arithmetic behind it: one check-in per person per day.
      for (final goal in NewRoundScreen.goalOptions) {
        for (final deposit in NewRoundScreen.depositOptions) {
          for (final bps in NewRoundScreen.poolOptions) {
            final people = NewRoundScreen.membersForFloor(
              deposit: deposit,
              bps: bps,
            );
            final n = people < 5 ? 5 : people;
            expect(
              hint(deposit, bps, goal, 30),
              startsWith(
                'With ${formatCount(n)} people checking in daily, this '
                'fills in about ${days((goal / n).ceil())}',
              ),
            );
          }
        }
      }
    });

    test('"Launch needs both" is its own line of the deal', () {
      for (final goal in NewRoundScreen.goalOptions) {
        final lines = NewRoundScreen.dealLines(
          deposit: 1000,
          bps: 3000,
          goal: goal,
          daysOpen: 7,
        );
        expect(
          lines,
          contains(
            'Launch needs both: ${formatCount(goal)} check-ins and 1,500 '
            'test USD of shop money.',
          ),
        );
        // Every amount in the deal is test money.
        for (final line in lines) {
          expect(line, isNot(matches(RegExp(r'\d USD'))), reason: line);
        }
      }
    });

    test('0% to the shop: a sponsor fills it, every deposit is prize', () {
      expect(NewRoundScreen.poolOptions.first, 0);
      expect(
        AppConfig.defaultLiquidityBps,
        3000,
        reason: '30% stays the default',
      );
      expect(NewRoundScreen.poolLabel(0), '0% · a sponsor fills the shop');
      expect(NewRoundScreen.poolLabel(3000), '30%');
      expect(
        NewRoundScreen.poolLine(0),
        'Needs a sponsor\'s shop money to launch. Every deposit is prize.',
      );
      // The default's honest line: 30% is locked in the shop at launch; the
      // prize is the other 70%, so the average member gets at least 70%.
      expect(
        NewRoundScreen.poolLine(3000),
        '30% of each deposit becomes locked shop money at launch. Keep up '
        'with the average and you get at least 70% back, plus coins and tax.',
      );
      expect(
        NewRoundScreen.poolLine(1000),
        '10% of each deposit becomes locked shop money at launch. Keep up '
        'with the average and you get at least 90% back, plus coins and tax.',
      );
      expect(
        NewRoundScreen.poolLine(10000),
        'The whole deposit becomes locked shop money at launch. No prize: '
        'only coins and tax.',
      );
      expect(
        NewRoundScreen.dealLines(deposit: 100, bps: 0, goal: 30, daysOpen: 30),
        [
          'Join: 100 test USD each, paid once.',
          'Prize: 100 test USD of each deposit, shared by days shown up.',
          'Shop: a sponsor fills it (the coin\'s trading pool). No deposit '
              'goes in.',
          'Coins: 1,000,000 made at launch. Half go into the shop, half '
              'into the group\'s piggy bank, split by days.',
          'Tax: 3% on buys, 5% on sells for 30 days. 80% to the piggy bank, '
              '20% burned.',
          'Launch needs both: 30 check-ins and 1,500 test USD of shop money.',
          'Who launches: anyone, once both are there.',
          'No launch in 30 days: each member presses Refund and gets their '
              'deposit back.',
        ],
      );
      expect(
        NewRoundScreen.floorLine(deposit: 100, bps: 0),
        'Flap sets that floor. Here only a sponsor fills it.',
      );
    });

    testWidgets('the 0% choice: its line, the deal, and the round it starts', (
      tester,
    ) async {
      final chain = FakeChain();
      final state = await makeState(chain: chain);
      await pumpNewRound(tester, state);
      await tester.enterText(find.byKey(const Key('round-name')), 'Squad A');
      await tester.pump();
      await tester.ensureVisible(find.text('More options'));
      await tester.pump();
      await tester.tap(find.text('More options'));
      await settle(tester);
      // The default first: 30%, with its honest line.
      expect(
        tester.widget<Text>(find.byKey(const Key('round-pool-line'))).data,
        startsWith('30% of each deposit becomes locked shop money'),
      );
      await pick(tester, 'round-pool', '0% · a sponsor fills the shop');
      expect(
        tester.widget<Text>(find.byKey(const Key('round-pool-line'))).data,
        'Needs a sponsor\'s shop money to launch. Every deposit is prize.',
      );
      expect(find.text('Shop 0% · Listed'), findsOneWidget);
      expect(
        find.text(
          'Shop: a sponsor fills it (the coin\'s trading pool). No deposit '
          'goes in.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Flap sets that floor. Here only a sponsor fills it.'),
        findsOneWidget,
      );
      // The chip fits a 360pt phone's row on its own line, whole.
      final chip = find.descendant(
        of: find.byKey(const Key('round-pool')),
        matching: find.byType(AppChip),
      );
      expect(tester.getSize(chip.first).height, greaterThanOrEqualTo(44));

      await press(tester, 'Start round');
      await settle(tester, 12);
      expect(chain.calls, ['createRound Squad A SA 1000 0 6']);
    });

    testWidgets('one job: the name, three choices, the deal, one button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final state = await makeState();
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));

      expect(find.text('NEW ROUND'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byType(FloatingTabBar), findsNothing);
      expect(find.text('Morning Movers'), findsOneWidget); // the placeholder
      // The name is public and for good: the field says so.
      expect(find.text('NAME'), findsOneWidget);
      expect(
        find.text(
          'Also the name of the coin. It can\'t be changed after you start.',
        ),
        findsOneWidget,
      );
      // Each choice says what it does. "test USD" is said once, in the
      // label, not on every chip.
      expect(find.text('DEPOSIT · TEST USD'), findsOneWidget);
      expect(find.text('Each person pays this once to join.'), findsOneWidget);
      expect(find.text('GOAL'), findsOneWidget);
      expect(
        find.text(
          'Check-ins the group needs to launch the coin. One per person per '
          'day.',
        ),
        findsOneWidget,
      );
      expect(find.text('RUNS FOR'), findsOneWidget);
      expect(
        find.text(
          'Not launched by then? Each member presses Refund and gets their '
          'deposit back.',
        ),
        findsOneWidget,
      );
      List<String> chips(String key) => [
        for (final chip in tester.widgetList<AppChip>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(AppChip),
          ),
        ))
          chip.text,
      ];
      expect(chips('round-deposit'), ['100', '500', '1,000', '2,000']);
      expect(chips('round-goal'), ['3', '6', '12', '30', '60']);
      expect(chips('round-days'), [
        '1 day',
        '3 days',
        '7 days',
        '14 days',
        '30 days',
      ]);
      // A chip is a full touch target.
      for (final chip in find.byType(AppChip).evaluate()) {
        expect(chip.size!.height, greaterThanOrEqualTo(44));
        expect(chip.size!.width, greaterThanOrEqualTo(44));
      }

      // "More options" is closed, says so, and says what is inside.
      expect(find.text('More options'), findsOneWidget);
      expect(find.text('Shop 30% · Listed'), findsOneWidget);
      expect(find.text('TOKEN POOL'), findsNothing);
      expect(find.byKey(const Key('round-unlisted')), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^More options'))),
        isSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );

      // The deal for the defaults, in money, one line each.
      for (final line in [
        'Join: 1,000 test USD each, paid once.',
        'Prize: 700 test USD of each deposit, shared by days shown up.',
        'Shop: 300 test USD of each deposit (the coin\'s trading pool).',
        'Coins: 1,000,000 made at launch. Half go into the shop, half '
            'into the group\'s piggy bank, split by days.',
        'Tax: 3% on buys, 5% on sells for 30 days. 80% to the piggy bank, '
            '20% burned.',
        'Launch needs both: 6 check-ins and 1,500 test USD of shop money.',
        'Who launches: anyone, once both are there.',
        'No launch in 7 days: each member presses Refund and gets their '
            'deposit back.',
        'Flap sets that floor. At this deposit it takes 5 people, or a '
            'sponsor.',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(find.text('THE DEAL'), findsOneWidget);

      // For a screen reader each control is one thing with its own press:
      // the back control, a chip with and without a spoken name, the
      // button. Each label and its sentence are read together, just before
      // their control; the deal is read as one.
      for (final label in [
        'Back',
        '1,000 test USD',
        '6 check-ins',
        '7 days',
        'Start round',
      ]) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasTapAction: true, isFocusable: true),
          reason: label,
        );
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('6 check-ins')),
        isSemantics(hasSelectedState: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('12 check-ins')),
        isSemantics(hasSelectedState: true, isSelected: false),
      );
      expect(
        find.bySemanticsLabel(
          'NAME\nAlso the name of the coin. It can\'t be changed after you '
          'start.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'GOAL\nCheck-ins the group needs to launch the coin. One per '
          'person per day.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^THE DEAL\nJoin: 1,000 test USD each, paid once\.\n'),
        ),
        findsOneWidget,
      );
      // A press from the screen reader changes the choice.
      tester.semantics.tap(find.semantics.byLabel('12 check-ins'));
      await settle(tester);
      expect(
        find.text(
          'Launch needs both: 12 check-ins and 1,500 test USD of shop '
          'money.',
        ),
        findsOneWidget,
      );
      // The example name is fainter than a typed one would be.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('round-name')))
            .decoration!
            .hintStyle!
            .color,
        AppColors.dark.text3,
      );

      // One button, pinned under the form, with what it costs.
      expect(find.byType(PillButton), findsOneWidget);
      expect(button('Start round'), findsOneWidget);
      expect(
        find.text(
          'Costs about 0.006 test BNB in fees. You join from Home like '
          'everyone else.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(button('Start round')).dy,
        greaterThan(844 / 2),
        reason: 'pinned at the bottom',
      );
      semantics.dispose();
    });

    testWidgets('the deal follows the choices, "More options" included', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final state = await makeState();
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));

      final hint = find.byKey(const Key('round-goal-hint'));
      expect(
        tester.widget<Text>(hint).data,
        'With 5 people checking in daily, this fills in about 2 days.',
      );
      await pick(tester, 'round-deposit', '500');
      await pick(tester, 'round-goal', '12');
      await pick(tester, 'round-days', '3 days');
      // The hint follows the choices, on one line under the goal's chips.
      expect(
        tester.widget<Text>(hint).data,
        'With 10 people checking in daily, this fills in about 2 days.',
      );
      expect(
        tester.getRect(hint).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('round-goal'))).bottom,
        ),
      );
      expect(
        tester.getRect(hint).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('RUNS FOR')).top),
      );
      for (final line in [
        'Join: 500 test USD each, paid once.',
        'Prize: 350 test USD of each deposit, shared by days shown up.',
        'Shop: 150 test USD of each deposit (the coin\'s trading pool).',
        'Coins: 1,000,000 made at launch. Half go into the shop, half '
            'into the group\'s piggy bank, split by days.',
        'Tax: 3% on buys, 5% on sells for 30 days. 80% to the piggy bank, '
            '20% burned.',
        'Launch needs both: 12 check-ins and 1,500 test USD of shop '
            'money.',
        'Who launches: anyone, once both are there.',
        'No launch in 3 days: each member presses Refund and gets their '
            'deposit back.',
        'Flap sets that floor. At this deposit it takes 10 people, or a '
            'sponsor.',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }

      // "More options" opens from the keyboard: Tab to it, Enter.
      String? focused() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ActionRow>()
          ?.title;
      for (var i = 0; i < 24 && focused() != 'More options'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focused(), 'More options');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^More options'))),
        isSemantics(hasExpandedState: true, isExpanded: true),
      );
      expect(find.text('SHOP MONEY'), findsOneWidget);
      expect(
        find.text(
          'The part of each deposit that goes into the coin\'s shop at '
          'launch. The rest is the prize.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<AppChip>(
              find.descendant(
                of: find.byKey(const Key('round-pool')),
                matching: find.byType(AppChip),
              ),
            )
            .map((c) => (c.text, c.selected)),
        [
          ('0% · a sponsor fills the shop', false),
          ('10%', false),
          ('30%', true),
          ('50%', false),
          ('100%', false),
        ],
      );
      // The default's honest line, under the chips.
      expect(
        tester.widget<Text>(find.byKey(const Key('round-pool-line'))).data,
        '30% of each deposit becomes locked shop money at launch. Keep up '
        'with the average and you get at least 70% back, plus coins and tax.',
      );
      // The existing switch, with its existing words.
      final toggle = find.byKey(const Key('round-unlisted'));
      expect(
        find.descendant(of: toggle, matching: find.text('Unlisted')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: toggle, matching: find.text(unlistedNoteText)),
        findsOneWidget,
      );

      // For a screen reader the switch is one thing: its name, what it
      // means, whether it is on, and a press of its own.
      await tester.ensureVisible(toggle);
      await tester.pump();
      final unlisted = find.bySemanticsLabel('Unlisted. $unlistedNoteText');
      expect(
        tester.getSemantics(unlisted),
        isSemantics(
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
          isFocusable: true,
        ),
      );
      tester.semantics.tap(
        find.semantics.byLabel('Unlisted. $unlistedNoteText'),
      );
      await settle(tester);
      expect(tester.getSemantics(unlisted), isSemantics(isToggled: true));
      expect(find.text('Shop 30% · Unlisted'), findsOneWidget);
      tester.semantics.tap(
        find.semantics.byLabel('Unlisted. $unlistedNoteText'),
      );
      await settle(tester);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('30% of each deposit into the shop'),
        ),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );

      await pick(tester, 'round-pool', '100%');
      expect(find.text('Shop 100% · Listed'), findsOneWidget);
      expect(
        find.text('Prize: none. The whole deposit goes into the shop.'),
        findsOneWidget,
      );
      expect(find.textContaining('Shop: '), findsNothing);
      // The coins and the tax are the same lines as at every other split.
      for (final line in [
        'Coins: 1,000,000 made at launch. Half go into the shop, half into '
            'the group\'s piggy bank, split by days.',
        'Tax: 3% on buys, 5% on sells for 30 days. 80% to the piggy bank, '
            '20% burned.',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(
        find.text(
          'Flap sets that floor. At this deposit it takes 3 people, or a '
          'sponsor.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('no name: one sentence by the field, and the cursor in it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final chain = FakeChain();
      final state = await makeState(chain: chain);
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));

      TextField name() =>
          tester.widget<TextField>(find.byKey(const Key('round-name')));
      expect(name().focusNode!.hasFocus, isFalse);
      await press(tester, 'Start round');
      await settle(tester);
      expect(find.text('Give your round a name.'), findsOneWidget);
      expect(name().focusNode!.hasFocus, isTrue);
      expect(chain.calls, isEmpty);
      // Announced by itself: the sentence is its own node, not the form.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Give your round a name.')),
        isSemantics(isLiveRegion: true),
      );
      // Next to the field, not down by the button; and the button is still
      // "Start round": nothing failed.
      final field = tester.getRect(find.byKey(const Key('round-name')));
      final said = tester.getRect(find.text('Give your round a name.'));
      expect(said.top, greaterThan(field.bottom));
      expect(said.top - field.bottom, lessThan(40));
      expect(button('Start round'), findsOneWidget);
      expect(button('Try again'), findsNothing);

      // Only spaces is no name either.
      await tester.enterText(find.byKey(const Key('round-name')), '   ');
      await settle(tester);
      expect(find.text('Give your round a name.'), findsNothing);
      await press(tester, 'Start round');
      await settle(tester);
      expect(find.text('Give your round a name.'), findsOneWidget);
      expect(chain.calls, isEmpty);
      semantics.dispose();
    });

    testWidgets('the whole form works from the keyboard, in reading order', (
      tester,
    ) async {
      final chain = FakeChain();
      final state = await makeState(chain: chain);
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));

      // Tab goes through the form top to bottom and reaches the pinned
      // button last, wherever the form is scrolled to.
      final order = await tabTo(tester, 'Start round');
      expect(order, [
        'Back',
        "[<'round-name'>]",
        '100 test USD',
        '500 test USD',
        '1,000 test USD',
        '2,000 test USD',
        '3 check-ins',
        '6 check-ins',
        '12 check-ins',
        '30 check-ins',
        '60 check-ins',
        '1 day',
        '3 days',
        '7 days',
        '14 days',
        '30 days',
        'More options',
        'Start round',
      ]);
      // Where the keyboard is shows: a ring on the button.
      expect(
        find.descendant(
          of: button('Start round'),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.foregroundPainter != null,
          ),
        ),
        findsOneWidget,
      );
      // Enter on the button is a press: no name yet, so it says so and the
      // cursor goes to the field.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Give your round a name.'), findsOneWidget);
      expect(focusedName(), "[<'round-name'>]");
      expect(chain.calls, isEmpty);

      // Space chooses a chip.
      await tabTo(tester, '500 test USD');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(find.text('Join: 500 test USD each, paid once.'), findsOneWidget);

      // "More options" opens, and what is in it is reached the same way.
      await tabTo(tester, 'More options');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      await tabTo(tester, '50% of each deposit into the shop');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Shop 50% · Listed'), findsOneWidget);
      await tabTo(tester, 'Unlisted. $unlistedNoteText');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(tester);
      expect(find.text('Shop 50% · Unlisted'), findsOneWidget);

      // Typing in the name field and Enter does not start anything: the
      // name is for good, so the round starts from its button only.
      await tester.enterText(find.byKey(const Key('round-name')), 'Night Owls');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(chain.calls, isEmpty);
      await tabTo(tester, 'Start round');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester, 12);
      expect(chain.calls, ['createRound Night Owls NO 500 5000 6']);
    });

    testWidgets('small phone, keyboard up: the name and its error stay in '
        'sight', (tester) async {
      final state = await makeState();
      await pumpNewRound(tester, state);
      tester.view.physicalSize = const Size(320, 568);
      await settle(tester);

      final field = find.byKey(const Key('round-name'));
      final bar = find.byKey(const Key('new-round-action'));
      const fee =
          'Costs about 0.006 test BNB in fees. You join from Home like '
          'everyone else.';
      expect(find.text(fee), findsOneWidget);
      // Where the pinned action stops being see-through.
      double opaqueFrom() => tester.getRect(bar).top + BottomFade.defaultRise;
      // The list ends there: nothing of it is behind the button.
      expect(
        tester.getRect(find.byKey(const Key('new-round-list'))).bottom,
        moreOrLessEquals(opaqueFrom(), epsilon: 0.5),
      );

      // The cursor in the field and the keyboard up.
      await tester.tap(field);
      await settle(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 253);
      await settle(tester, 12);
      // The bar is the button alone now, on top of the keyboard.
      expect(find.text(fee), findsNothing);
      expect(tester.getRect(bar).bottom, moreOrLessEquals(568 - 253));
      expect(tester.getRect(button('Start round')).bottom, lessThan(568 - 253));
      // The field is above the bar, fade included: it can be read while
      // typing.
      expect(tester.getRect(field).top, greaterThan(0));
      expect(
        tester.getRect(field).bottom,
        lessThanOrEqualTo(tester.getRect(bar).top),
      );

      // No name: the sentence shows above the bar too, with its field.
      await tester.tap(button('Start round'));
      await settle(tester, 12);
      final said = tester.getRect(find.text('Give your round a name.'));
      expect(said.bottom, lessThanOrEqualTo(tester.getRect(bar).top + 0.5));
      expect(tester.getRect(field).top, greaterThan(0));
      expect(tester.getRect(field).bottom, lessThan(said.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'too little test BNB: the sentence says where more comes from',
      (tester) async {
        // The faucet has filled this wallet before; it does not again.
        final chain = FakeChain(bnb: 0.001);
        final state = await makeState(chain: chain);
        await pumpBody(tester, NewRoundScreen(state: state, missing: const []));
        await tester.enterText(
          find.byKey(const Key('round-name')),
          'Night Owls',
        );
        await settle(tester);
        await press(tester, 'Start round');
        await settle(tester, 12);
        expect(
          find.text(
            'Starting a round needs about 0.006 test BNB in fees and this '
            'wallet has less. Send test BNB to your address (Wallet, then '
            'Address), then try again.',
          ),
          findsOneWidget,
        );
        expect(chain.calls, isEmpty);
        // With more in the wallet, the button is the way on.
        chain.bnb = usd(0.03);
        await press(tester, 'Try again');
        await settle(tester, 12);
        expect(chain.calls, ['createRound Night Owls NO 1000 3000 6']);
      },
    );

    testWidgets('started from Home: Home does not read again under the '
        'screen, so the new round stays selected', (tester) async {
      final chain = SlowChain();
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Night Owls'));
      server.unlisted.add(createdLauncher);
      final state = await makeState(chain: chain, server: server);
      // Home, with the new-round screen pushed over it: Home stays alive
      // underneath, as it does behind the "+".
      usePhone(tester);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => HomeScreen(state: state),
          ),
          GoRoute(
            path: '/new',
            builder: (_, _) => NewRoundScreen(state: state, missing: const []),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: inAppTheme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: AppBackdrop(child: child!),
          ),
        ),
      );
      await settle(tester, 12);
      unawaited(router.push('/new'));
      await settle(tester, 12);
      expect(find.byType(NewRoundScreen), findsOneWidget);
      expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);

      await tester.enterText(find.byKey(const Key('round-name')), 'Night Owls');
      await settle(tester);
      // The round is on its way to the chain, and stays there for a while.
      chain.holdCreate = Completer<void>();
      chain.holdMember = Completer<void>();
      final reads = server.count('GET /rounds');
      await press(tester, 'Start round');
      await settle(tester);
      expect(find.text('Starting your round…'), findsOneWidget);
      // Home's twenty seconds pass. A read started now would list the
      // rounds as they were and, finishing after the round is started, put
      // the list back without it.
      await tester.pump(const Duration(seconds: 21));
      await settle(tester);
      expect(server.count('GET /rounds'), reads, reason: 'no read under /new');
      chain.holdCreate!.complete();
      await settle(tester, 12);
      chain.holdMember!.complete();
      await settle(tester, 12);

      expect(state.rounds.map((r) => r.id), contains(createdLauncher));
      expect(state.selected, createdLauncher);
      // The invite sheet opened by itself; under it, the done state.
      expect(find.byType(InviteSheet), findsOneWidget);
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);
      expect(find.text('ROUND STARTED'), findsOneWidget);
      expect(enabled(tester, 'Invite people'), isTrue);
      await press(tester, 'Go to round');
      await settle(tester, 12);
      expect(find.byType(NewRoundScreen), findsNothing);
      expect(state.selected, createdLauncher);
      expect(button('Join Night Owls · 1,000 USD'), findsOneWidget);
    });

    testWidgets('"Go to round" opens Home on the new round, whatever is '
        'selected by then', (tester) async {
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Night Owls'));
      final state = await makeState(server: server);
      await pumpNewRound(tester, state);
      await tester.enterText(find.byKey(const Key('round-name')), 'Night Owls');
      await settle(tester);
      await press(tester, 'Start round');
      await settle(tester, 12);
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);
      expect(find.text('ROUND STARTED'), findsOneWidget);
      // Something else moved the selection while this screen was open.
      state.select(launcher);
      await settle(tester);
      expect(state.selected, launcher);
      await press(tester, 'Go to round');
      await settle(tester, 12);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.selected, createdLauncher);
    });

    testWidgets('a failure is one sentence and the button says Try again', (
      tester,
    ) async {
      final chain = FakeChain(fail: 'createRound');
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Night Owls'));
      server.unlisted.add(createdLauncher);
      final state = await makeState(chain: chain, server: server);
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));

      await tester.enterText(find.byKey(const Key('round-name')), 'Night Owls');
      await settle(tester);
      await press(tester, 'Start round');
      await settle(tester, 12);
      expect(
        find.text('The createRound was rejected. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(button('Start round'), findsNothing);
      expect(find.text('ROUND STARTED'), findsNothing);
      await press(tester, 'Try again');
      await settle(tester, 12);
      expect(chain.calls, ['createRound Night Owls NO 1000 3000 6']);
      expect(state.selected, createdLauncher);
    });

    testWidgets('started: the round by its name, invite, and on to Home', (
      tester,
    ) async {
      final chain = FakeChain();
      // The server finds the new round on chain when it is asked about it.
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Lumpini Striders'));
      server.unlisted.add(createdLauncher); // not shown until registered
      final state = await makeState(chain: chain, server: server);
      expect(state.rounds, hasLength(1));
      await pumpNewRound(tester, state);

      await tester.enterText(
        find.byKey(const Key('round-name')),
        'Lumpini Striders',
      );
      await settle(tester);
      await press(tester, 'Start round');
      await settle(tester, 12);
      // The defaults: 1,000 test USD, 30% to the pool, 6 check-ins.
      expect(chain.calls, ['createRound Lumpini Striders LS 1000 3000 6']);
      // The creator is not made a member: joining is the same step as for
      // everyone else.
      expect(state.isMember, isFalse);

      // Registered with the server as listed, signed by the creator.
      expect(server.bodies['/rounds'], {
        'launcher': createdLauncher,
        'unlisted': false,
        'signature': VerifierApi.sign(
          testKey,
          'Cypher Run round $createdLauncher listed',
        ),
      });
      // On this wallet's own slider at once, and selected.
      expect(state.rounds.map((r) => r.id), contains(createdLauncher));
      expect(state.selected, createdLauncher);

      // The invite sheet opens by itself. This build has no web address, so
      // it hands out the round's address.
      expect(find.byType(InviteSheet), findsOneWidget);
      expect(find.text('INVITE'), findsOneWidget);
      expect(find.byKey(const Key('invite-link')), findsOneWidget);
      // The creator can change the listing from the sheet.
      expect(find.byKey(const Key('invite-unlisted')), findsOneWidget);

      await tester.tapAt(const Offset(195, 20)); // the barrier closes it
      await settle(tester, 12);
      expect(find.byType(InviteSheet), findsNothing);

      // The same screen, now done: the name is the headline, not an address.
      expect(find.byType(NewRoundScreen), findsOneWidget);
      expect(find.text('NEW ROUND'), findsNothing);
      expect(find.text('ROUND STARTED'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('round-started-name'))).data,
        'Lumpini Striders',
      );
      expect(
        find.text('It\'s on your Home. Invite people to fill the bar.'),
        findsOneWidget,
      );
      expect(find.text(createdLauncher), findsNothing);
      expect(find.textContaining('0x5000'), findsNothing);
      expect(
        find.text('Listed: everyone sees it in the list on Home.'),
        findsOneWidget,
      );
      expect(find.byType(FloatingTabBar), findsNothing);
      expect(find.byKey(const Key('round-name')), findsNothing);
      final link = tester.widget<LinkRow>(find.byType(LinkRow));
      expect(link.label, 'View on BscScan testnet');
      expect(link.url, 'https://testnet.bscscan.com/address/$createdLauncher');
      expect(button('Save again'), findsNothing);

      // "Invite people" opens the invite sheet for that round again.
      await press(tester, 'Invite people');
      await settle(tester, 12);
      expect(find.byType(InviteSheet), findsOneWidget);
      expect(
        tester.widget<InviteSheet>(find.byType(InviteSheet)).round.id,
        createdLauncher,
      );
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);

      // "Go to round": Home, with the new round already selected.
      await press(tester, 'Go to round');
      await settle(tester, 12);
      expect(find.byType(NewRoundScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.selected, createdLauncher);
      expect(button('Join Lumpini Striders · 1,000 USD'), findsOneWidget);
    });

    testWidgets('the "Unlisted" switch says exactly what it means', (
      tester,
    ) async {
      final chain = FakeChain();
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Night Owls'));
      server.unlisted.add(createdLauncher);
      final state = await makeState(chain: chain, server: server);
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));

      expect(unlistedNote, unlistedNoteText);
      await tester.ensureVisible(find.text('More options'));
      await tester.pump();
      await tester.tap(find.text('More options'));
      await settle(tester);
      final toggle = find.byKey(const Key('round-unlisted'));
      expect(
        find.descendant(of: toggle, matching: find.text('Unlisted')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: toggle, matching: find.text(unlistedNoteText)),
        findsOneWidget,
      );
      expect(tester.widget<CapsuleToggle>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await settle(tester);
      expect(tester.widget<CapsuleToggle>(toggle).value, isTrue);
      expect(find.text('Shop 30% · Unlisted'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('round-name')), 'Night Owls');
      await settle(tester);
      await press(tester, 'Start round');
      await settle(tester, 12);

      // The registration call: the pinned text, signed by the creator.
      expect(server.count('POST /rounds'), 1);
      expect(server.bodies['/rounds'], {
        'launcher': createdLauncher,
        'unlisted': true,
        // `cast wallet sign` of
        // "Cypher Run round 0x5000000000000000000000000000000000000005 unlisted"
        // with the test key.
        'signature':
            '0x58bda5a011556af75fbdba9d39ba7677f3113815c2ca2a34472697986fc0d01b'
            '1281f1e8678eb8c4bfb4f25665236318f3eafd66d1fce79887613ef18ae790a31c',
      });
      // Unlisted: not in the public list, still on its creator's slider.
      expect(state.knownRound(createdLauncher)!.registered, isTrue);
      expect(state.knownRound(createdLauncher)!.unlisted, isTrue);
      expect(state.selected, createdLauncher);
      expect(state.round!.unlisted, isTrue);

      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);
      expect(find.text('ROUND STARTED'), findsOneWidget);
      expect(find.text('Unlisted. $unlistedNoteText'), findsOneWidget);
    });

    testWidgets('a listing the server did not save says so, with a way on', (
      tester,
    ) async {
      // The server has not found the new round on chain yet.
      final server = FakeServer();
      final state = await makeState(server: server);
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));
      await tester.ensureVisible(find.text('More options'));
      await tester.pump();
      await tester.tap(find.text('More options'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('round-unlisted')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('round-unlisted')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('round-name')), 'Night Owls');
      await settle(tester);
      await press(tester, 'Start round');
      await settle(tester, 12);
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);

      // Still on this device's slider, from what was sent to the chain.
      expect(state.selected, createdLauncher);
      expect(state.round!.name, 'Night Owls');
      expect(state.knownRound(createdLauncher)!.registered, isFalse);
      // The done state names the round, and says plainly what is not saved.
      expect(find.text('ROUND STARTED'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('round-started-name'))).data,
        'Night Owls',
      );
      final listing = find.byKey(const Key('round-listing'));
      expect(
        find.descendant(
          of: listing,
          matching: find.textContaining(
            'has not found this round on chain yet',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: listing,
          matching: find.text(
            'Until it is saved as unlisted, the round can show in the public '
            'list.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Unlisted. Not shown'), findsNothing);

      // The server finds it; "Save again" goes through.
      server.more.add(roundJson(at: createdLauncher, name: 'Night Owls'));
      await press(tester, 'Save again');
      await settle(tester, 12);
      expect(state.knownRound(createdLauncher)!.registered, isTrue);
      expect(server.unlisted, contains(createdLauncher));
      expect(find.textContaining('Unlisted. Not shown'), findsOneWidget);
      expect(button('Save again'), findsNothing);
    });

    testWidgets('a build without addresses says which values are missing', (
      tester,
    ) async {
      final state = await makeState();
      await pumpBody(
        tester,
        NewRoundScreen(
          state: state,
          missing: const ['CHECKIN_LAUNCHER_FACTORY', 'ATTESTER_ADDRESS'],
        ),
      );
      expect(find.text('NEW ROUND'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text('This build cannot start a round yet.'), findsOneWidget);
      expect(find.text('CHECKIN_LAUNCHER_FACTORY'), findsOneWidget);
      expect(find.text('ATTESTER_ADDRESS'), findsOneWidget);
      expect(button('Start round'), findsNothing);
      expect(find.byKey(const Key('round-name')), findsNothing);
    });
  });
}
