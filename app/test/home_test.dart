// Home: one widget test per state of its primary action, plus the bar, the
// prize, the members and the states with no round to show.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/dot_matrix.dart';
import 'package:pacepact/widgets/gauges.dart';

import 'support.dart';

Future<void> pumpHome(WidgetTester tester, AppState state) async {
  usePhone(tester);
  await tester.pumpWidget(inApp(HomeScreen(state: state, showBar: false)));
  await settle(tester);
}

/// The one primary action: the pill with [label].
Finder action(String label) =>
    find.byWidgetPredicate((w) => w is PillButton && w.label == label);

bool enabled(WidgetTester tester, String label) =>
    tester.widget<PillButton>(action(label)).onPressed != null;

void main() {
  testWidgets(
    'not joined: "Join Morning Movers · 1,000 USD" opens the join sheet',
    (tester) async {
      final state = await makeState();
      await pumpHome(tester, state);

      expect(action('Join Morning Movers · 1,000 USD'), findsOneWidget);
      expect(find.byType(PillButton), findsOneWidget, reason: 'one action');
      expect(find.text('Round open · not joined yet'), findsOneWidget);
      // The streak is the hero numeral.
      expect(find.text('YOUR STREAK'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      expect(find.text('days'), findsOneWidget);

      await tester.tap(action('Join Morning Movers · 1,000 USD'));
      await settle(tester, 10);
      expect(find.text('Pay the deposit'), findsOneWidget);
    },
  );

  testWidgets(
    'joined, not checked in: "Check in · Morning Movers" opens the check-in',
    (tester) async {
      final state = await makeState(chain: FakeChain(isMember: true));
      await pumpHome(tester, state);

      expect(action('Check in · Morning Movers'), findsOneWidget);
      expect(enabled(tester, 'Check in · Morning Movers'), isTrue);
      expect(find.text('Not checked in today'), findsOneWidget);
      expect(
        find.text('Self-reported in the browser. Testnet only.'),
        findsOneWidget,
      );

      await tester.tap(action('Check in · Morning Movers'));
      await settle(tester, 10);
      expect(find.text('Self-reported, testnet only'), findsOneWidget);
    },
  );

  testWidgets('checked in: the action is disabled with a hint about tomorrow', (
    tester,
  ) async {
    final state = await makeState(
      chain: FakeChain(isMember: true, checkedInToday: true, daysOf: 7),
      server: FakeServer()
        ..me = meJson(daysOf: 7, streak: 7, checkedInToday: true),
    );
    await pumpHome(tester, state);

    expect(action('Checked in'), findsOneWidget);
    expect(enabled(tester, 'Checked in'), isFalse);
    // 15:00 UTC: the next UTC day is nine hours away.
    expect(
      find.text('Come back tomorrow. The next day starts in 9 h.'),
      findsOneWidget,
    );
    expect(find.text('Checked in today'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.text('7 days in this round'), findsOneWidget);
  });

  testWidgets('bar full: anyone can "Launch Morning Movers"', (tester) async {
    final chain = FakeChain(totalCheckIns: 6, pool: 1500);
    final state = await makeState(
      chain: chain,
      server: FakeServer()
        ..round = roundJson(totalCheckIns: 6, poolQuoteNow: '1500'),
    );
    await pumpHome(tester, state);

    expect(state.isMember, isFalse);
    expect(action('Launch Morning Movers'), findsOneWidget);
    expect(enabled(tester, 'Launch Morning Movers'), isTrue);
    expect(
      find.text('The bar is full. Anyone can launch the token now.'),
      findsOneWidget,
    );

    await tester.tap(action('Launch Morning Movers'));
    await settle(tester);
    expect(chain.calls, ['launch']);
    // The same screen moves on to the result.
    expect(action('See the result · Morning Movers'), findsOneWidget);
    expect(bannerNote.value!.text, 'Launched. The token is live.');
    bannerNote.value = null;
  });

  testWidgets('bar full but the pool is short: launch waits for a sponsor', (
    tester,
  ) async {
    final chain = FakeChain(isMember: true, totalCheckIns: 6, pool: 900);
    final state = await makeState(
      chain: chain,
      server: FakeServer()..round = roundJson(totalCheckIns: 6),
    );
    await pumpHome(tester, state);

    expect(enabled(tester, 'Launch Morning Movers'), isFalse);
    expect(
      find.text(
        'The bar is full, but the launch pool is 600 USD short of what Flap '
        'needs.',
      ),
      findsOneWidget,
    );
    await tester.tap(action('Sponsor the launch pool'));
    await settle(tester, 10);
    expect(find.text('Sponsor the launch pool'), findsNWidgets(2));
    // The sheet starts with what is missing.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sponsor-amount')))
          .controller!
          .text,
      '600',
    );
    await tester.tap(action('Add to the launch pool'));
    await settle(tester, 10);
    expect(chain.calls, ['mint 600', 'sponsor 600']);
    expect(enabled(tester, 'Launch Morning Movers'), isTrue);
    bannerNote.value = null;
  });

  testWidgets('a failed launch is one sentence; the button is the retry', (
    tester,
  ) async {
    final chain = FakeChain(totalCheckIns: 6, pool: 1500, fail: 'launch');
    final state = await makeState(
      chain: chain,
      server: FakeServer()..round = roundJson(totalCheckIns: 6),
    );
    await pumpHome(tester, state);

    await tester.tap(action('Launch Morning Movers'));
    await settle(tester);
    expect(find.text('The launch was rejected. Try again.'), findsOneWidget);
    expect(chain.calls, isEmpty);
    await tester.tap(action('Launch Morning Movers'));
    await settle(tester);
    expect(chain.calls, ['launch']);
    bannerNote.value = null;
  });

  testWidgets('launched, with days: "Claim · Morning Movers"', (tester) async {
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
        ..round = roundJson(launched: true, totalCheckIns: 6)
        ..me = meJson(daysOf: 3, streak: 3),
    );
    await pumpHome(tester, state);

    expect(action('Claim · Morning Movers'), findsOneWidget);
    expect(enabled(tester, 'Claim · Morning Movers'), isTrue);
    expect(find.text('Token launched'), findsOneWidget);
    expect(
      find.text('The token launched. Your share is waiting in the vault.'),
      findsOneWidget,
    );
  });

  testWidgets('launched, no days: "See the result · Morning Movers"', (
    tester,
  ) async {
    final state = await makeState(
      chain: FakeChain(launched: true, totalCheckIns: 6),
      server: FakeServer()..round = roundJson(launched: true, totalCheckIns: 6),
    );
    await pumpHome(tester, state);
    expect(action('See the result · Morning Movers'), findsOneWidget);
    expect(action('Claim · Morning Movers'), findsNothing);
  });

  testWidgets('deadline missed: "Deposit back · Morning Movers", then ended', (
    tester,
  ) async {
    final chain = FakeChain(isMember: true, refundable: 1000);
    final state = await makeState(now: DateTime.utc(2026, 12, 3), chain: chain);
    await pumpHome(tester, state);

    expect(find.text('Round ended'), findsOneWidget); // the badge
    await tester.tap(action('Deposit back · Morning Movers'));
    await settle(tester);
    expect(chain.calls, ['refund']);
    expect(action('Round ended'), findsOneWidget);
    expect(enabled(tester, 'Round ended'), isFalse);
    bannerNote.value = null;
  });

  testWidgets('the bar, the prize and the members sit under the action', (
    tester,
  ) async {
    final server = FakeServer()
      ..members = [
        {
          'address': '0x2000000000000000000000000000000000000002',
          'daysOf': 2,
          'streak': 2,
          'checkedInToday': true,
        },
        {
          'address': testAddress,
          'daysOf': 1,
          'streak': 1,
          'checkedInToday': false,
        },
      ];
    final state = await makeState(
      chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 3, pool: 900),
      server: server,
    );
    await pumpHome(tester, state);

    // The round's card: the bar is everyone's check-ins against the goal,
    // as a tick gauge. The count is the chain's (3), not the server's (2).
    expect(find.text('Morning Movers'), findsOneWidget);
    expect(find.text('THE BAR'), findsOneWidget);
    expect(find.text('3 / 6 check-ins'), findsOneWidget);
    expect(find.text('Closes 2 Dec 2026'), findsOneWidget);
    expect(find.text('Prize so far 2,100 USD'), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget);
    expect(find.text('You\'re in'), findsOneWidget);
    expect(find.byType(TickGauge), findsOneWidget);
    expect(tester.widget<TickGauge>(find.byType(TickGauge)).progress, 0.5);

    // The prize so far, in dot-matrix numerals.
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('LAUNCH POOL'),
      200,
      scrollable: list,
    );
    expect(find.text('PRIZE SO FAR'), findsOneWidget);
    expect(
      tester.widget<DotMatrixText>(find.byType(DotMatrixText)).text,
      '2,100',
    );
    expect(find.text('LAUNCH POOL'), findsOneWidget);
    expect(find.text('900'), findsOneWidget);
    expect(find.text('of 1,500 USD Flap needs'), findsOneWidget);

    // Members: address, days, streak. The person's own row says "You".
    await tester.scrollUntilVisible(find.text('You'), 200, scrollable: list);
    expect(find.text('0x2000…0002'), findsOneWidget);
    expect(find.text('2 days · streak 2 · in today'), findsOneWidget);
    expect(find.text('1 day · streak 1'), findsOneWidget);

    // What the server can and cannot do is said plainly.
    await tester.scrollUntilVisible(
      find.textContaining('attested by Cypher Run\'s server, not proven'),
      200,
      scrollable: list,
    );
    expect(
      find.textContaining('cannot launch early, block a launch or move funds'),
      findsOneWidget,
    );
  });

  testWidgets('no round open: a card and "Look again"', (tester) async {
    final server = FakeServer()..round = null;
    final state = await makeState(server: server);
    await pumpHome(tester, state);

    expect(find.text('NO ROUND\nRIGHT NOW.'), findsOneWidget);
    expect(find.text('YOUR STREAK'), findsNothing);
    server.round = roundJson();
    await tester.tap(action('Look again'));
    await settle(tester);
    expect(action('Join Morning Movers · 1,000 USD'), findsOneWidget);
  });

  testWidgets('server unreachable: one sentence and Retry, no host name', (
    tester,
  ) async {
    final server = FakeServer()..offline = true;
    final state = await makeState(server: server);
    await pumpHome(tester, state);

    expect(find.text(VerifierApi.unreachable), findsOneWidget);
    expect(find.textContaining('localhost'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('server.test'), findsNothing);

    server.offline = false;
    await tester.tap(action('Retry'));
    await settle(tester);
    expect(find.text(VerifierApi.unreachable), findsNothing);
    expect(action('Join Morning Movers · 1,000 USD'), findsOneWidget);
  });

  testWidgets('wide screens keep the centred 480px column', (tester) async {
    usePhone(tester, size: const Size(1280, 800));
    final state = await makeState();
    await tester.pumpWidget(
      MaterialApp(
        theme: inAppTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AppBackdrop(child: child!),
        ),
        home: HomeScreen(state: state, showBar: false),
      ),
    );
    await settle(tester);
    final home = tester.getSize(find.byType(HomeScreen));
    expect(home.width, CenteredColumn.maxWidth);
    expect(CenteredColumn.maxWidth, 480);
    // The aurora still covers the whole window.
    expect(tester.getSize(find.byType(AuroraBackground)).width, 1280);
  });
}
