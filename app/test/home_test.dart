// Home: one widget test per state of its primary action, plus the bar, the
// prize, the order of the sections, what a launch still needs and the
// states with no round to show.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/dot_matrix.dart';
import 'package:pacepact/widgets/gauges.dart';
import 'package:pacepact/widgets/launch_floor_line.dart';
import 'package:pacepact/widgets/streak_block.dart';

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

/// Scrolls Home down to the streak, under THE PRIZE.
Future<void> showStreak(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('YOUR STREAK'),
    200,
    scrollable: homeList,
  );
  await settle(tester);
}

/// Where [finder] sits in Home's list, from the top of its content: the
/// same however far the list is scrolled.
double contentTop(WidgetTester tester, Finder finder) =>
    tester.getRect(finder).top +
    tester.state<ScrollableState>(homeList).position.pixels;

/// Home's own list (not the cards' sideways one inside it).
final homeList = find
    .descendant(
      of: find.byKey(const Key('home-list')),
      matching: find.byType(Scrollable),
    )
    .first;

String? floorLine(AppState state) =>
    LaunchFloorLine.textFor(state, state.round!);

void main() {
  testWidgets(
    'not joined: "Join Morning Movers · 1,000 USD" opens the join sheet',
    (tester) async {
      final state = await makeState();
      await pumpHome(tester, state);

      expect(action('Join Morning Movers · 1,000 USD'), findsOneWidget);
      expect(find.byType(PillButton), findsOneWidget, reason: 'one action');
      // The streak, under THE PRIZE.
      await showStreak(tester);
      expect(find.text('Round open · not joined yet'), findsOneWidget);
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
      await showStreak(tester);
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
    await showStreak(tester);
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
      find.text('The bar is full. Anyone can launch the coin now.'),
      findsOneWidget,
    );

    await tester.tap(action('Launch Morning Movers'));
    await settle(tester);
    expect(chain.calls, ['launch']);
    // The same screen moves on to the result.
    expect(action('See the result · Morning Movers'), findsOneWidget);
    expect(bannerNote.value!.text, 'Launched. The coin is live.');
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
        'The bar is full, but the shop money is 600 test USD short of what '
        'Flap needs.',
      ),
      findsOneWidget,
    );
    await tester.tap(action('Sponsor the shop'));
    await settle(tester, 10);
    expect(find.text('Sponsor the shop'), findsNWidgets(2));
    // The sheet starts with what is missing.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sponsor-amount')))
          .controller!
          .text,
      '600',
    );
    await tester.tap(action('Add to the shop'));
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
    await showStreak(tester);
    expect(find.text('Coin launched'), findsOneWidget);
    expect(
      find.text('The coin launched. Your share is in the piggy bank.'),
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

    await showStreak(tester);
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
    // The header says this is testnet money, beside the balance.
    expect(find.byKey(const Key('testnet-pill')), findsOneWidget);
    expect(find.text('TESTNET'), findsOneWidget);
    // A chip as wide as its word, not a bar across the header.
    expect(
      tester.getSize(find.byKey(const Key('testnet-pill'))).width,
      lessThan(120),
    );
    expect(find.text('Morning Movers'), findsOneWidget);
    expect(find.text('THE BAR'), findsOneWidget);
    expect(find.text('3 / 6 check-ins'), findsOneWidget);
    expect(find.text('Closes 2 Dec 2026'), findsOneWidget);
    expect(find.text('Prize 2,100 test USD'), findsOneWidget);
    // On the card only: THE PRIZE right under it does not say it again.
    expect(find.text('3 members'), findsOneWidget);
    expect(find.text('You\'re in'), findsOneWidget);
    expect(find.byType(TickGauge), findsOneWidget);
    expect(tester.widget<TickGauge>(find.byType(TickGauge)).progress, 0.5);

    // THE PRIZE: each member's days and what they are worth if it
    // launched now (the prize of 2,100 over 3 check-ins). The person's own
    // row says "You"; the others have a friendly name and their address.
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('You'), 200, scrollable: list);
    expect(find.text('THE PRIZE'), findsOneWidget);
    expect(find.text('0x2000…0002'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('1,400 test USD'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('700 test USD'), findsOneWidget);

    // The prize so far, in dot-matrix numerals.
    await tester.scrollUntilVisible(
      find.text('SHOP MONEY'),
      200,
      scrollable: list,
    );
    expect(find.text('PRIZE SO FAR'), findsOneWidget);
    expect(
      tester.widget<DotMatrixText>(find.byType(DotMatrixText)).text,
      '2,100',
    );
    expect(find.text('SHOP MONEY'), findsOneWidget);
    expect(find.text('900'), findsOneWidget);
    expect(find.text('of 1,500 test USD Flap needs'), findsOneWidget);

    // What the server can and cannot do is said plainly.
    await tester.scrollUntilVisible(
      find.textContaining('signed by Cypher Run\'s server, not proven'),
      200,
      scrollable: list,
    );
    expect(
      find.textContaining('cannot move money, launch early or block a launch'),
      findsOneWidget,
    );
    // A full bar alone does not launch: Flap's floor for the shop money is
    // said too.
    expect(
      find.text(
        'Bar full (6 check-ins) and 1,500 test USD of shop money (Flap\'s '
        'floor)? Then anyone can press Launch.',
      ),
      findsOneWidget,
    );
    // What a launch makes, where the coins go, the tax, the split and the
    // refund, in plain words.
    for (final line in [
      'Launch makes 1,000,000 new coins on Flap: half go into the shop with '
          'the shop money, half into the group\'s piggy bank. The shop is '
          'locked forever (LP burned).',
      'For 30 days each trade pays a tax: 3% on buys, 5% on sells. 80% goes '
          'to the piggy bank, 20% is burned.',
      'The prize and the piggy bank are split by days: your days ÷ all '
          'days, frozen at launch. 0 days = nothing.',
    ]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(
      find.textContaining(
        'Each member presses Refund and gets back exactly '
        'what they paid. Sponsors too.',
      ),
      findsOneWidget,
    );
  });

  group('the order on a 390 by 844 phone', () {
    Future<double> actionTop(WidgetTester tester) async =>
        tester.getRect(find.byKey(const Key('home-action'))).top;

    testWidgets('a member: the cards, then what they would get, then the '
        'streak', (tester) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 3),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 3)
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
          ],
      );
      await pumpHome(tester, state);
      final top = await actionTop(tester);

      // Without scrolling: the round's card and the start of THE PRIZE.
      expect(tester.getRect(find.text('THE BAR')).bottom, lessThan(top));
      expect(tester.getRect(find.text('THE PRIZE')).bottom, lessThan(top));
      expect(
        tester.getRect(find.text('If it launched now, you\'d get')).bottom,
        lessThan(top),
      );
      // The amount itself within one short scroll (under 200 px).
      final amount = tester.getRect(find.byKey(const Key('pot-amount')));
      expect(amount.bottom - top, lessThan(200));
      final amountAt = contentTop(tester, find.byKey(const Key('pot-amount')));

      // THE PRIZE comes before the streak, and the streak is compact.
      await showStreak(tester);
      expect(amountAt, lessThan(contentTop(tester, find.text('YOUR STREAK'))));
      expect(
        tester.getSize(find.byKey(const Key('streak-number'))).height,
        lessThan(80),
      );
      // Its information is all still there.
      expect(find.text('Not checked in today'), findsOneWidget);
      expect(find.text('1 day in this round'), findsOneWidget);
      expect(find.byType(DayTrack), findsOneWidget);
    });

    testWidgets('a visitor: what a day is worth before the streak, without '
        'scrolling', (tester) async {
      final state = await makeState(
        server: FakeServer()..round = roundJson(totalCheckIns: 4),
      );
      await pumpHome(tester, state);
      final top = await actionTop(tester);
      final worth = find.text(
        'If it launched now, each day shown up would be worth about 525 '
        'test USD.',
        findRichText: true,
      );
      expect(worth, findsOneWidget);
      expect(tester.getRect(worth).bottom, lessThan(top));
    });
  });

  group('launch also needs the shop money', () {
    const fiveMore =
        'Launch also needs 1,500 test USD of shop money (Flap\'s floor): about '
        '5 more members at this deposit, or a sponsor.';

    testWidgets('under THE PRIZE, above the streak, while the pool is short', (
      tester,
    ) async {
      // Nothing in the pool yet: 1,500 short, 300 a member.
      final state = await makeState(chain: FakeChain(pool: 0));
      await pumpHome(tester, state);
      final line = find.byKey(const Key('launch-floor'));
      // Under THE PRIZE, its list and its invite.
      final invite = contentTop(tester, find.text('Invite someone'));
      expect(invite, greaterThan(contentTop(tester, find.text('THE PRIZE'))));
      await tester.scrollUntilVisible(line, 200, scrollable: homeList);
      await settle(tester);
      expect(tester.widget<Text>(line).data, fiveMore);
      final at = contentTop(tester, line);
      expect(at, greaterThan(invite));
      await showStreak(tester);
      expect(at, lessThan(contentTop(tester, find.text('YOUR STREAK'))));
    });

    test(
      'how many members, from the deposit and its part for the pool',
      () async {
        expect(floorLine(await makeState(chain: FakeChain(pool: 0))), fiveMore);
        // 600 short: two more members at 300 each.
        expect(
          floorLine(await makeState(chain: FakeChain(pool: 900))),
          'Launch also needs 1,500 test USD of shop money (Flap\'s floor): '
          'about 2 more members at this deposit, or a sponsor.',
        );
        // 1 short: one more member.
        expect(
          floorLine(await makeState(chain: FakeChain(pool: 1499))),
          'Launch also needs 1,500 test USD of shop money (Flap\'s floor): '
          'about 1 more member at this deposit, or a sponsor.',
        );
        // A round whose deposit adds nothing to the pool.
        expect(
          floorLine(
            await makeState(
              chain: FakeChain(pool: 0),
              server: FakeServer()..round = {...roundJson(), 'liquidityBps': 0},
            ),
          ),
          'Launch also needs 1,500 test USD of shop money (Flap\'s floor). In '
          'this round a deposit adds nothing to it, so it takes a sponsor.',
        );
      },
    );

    test('nothing when the pool has enough, after the launch, or after the '
        'deadline', () async {
      expect(floorLine(await makeState(chain: FakeChain(pool: 1500))), isNull);
      expect(floorLine(await makeState(chain: FakeChain(pool: 4000))), isNull);
      expect(
        floorLine(
          await makeState(
            chain: FakeChain(launched: true, pool: 0, totalCheckIns: 6),
            server: FakeServer()
              ..round = roundJson(launched: true, totalCheckIns: 6),
          ),
        ),
        isNull,
      );
      expect(
        floorLine(
          await makeState(
            now: DateTime.utc(2026, 12, 3),
            chain: FakeChain(pool: 0),
          ),
        ),
        isNull,
      );
    });

    testWidgets('not on Home when the pool has enough', (tester) async {
      final state = await makeState(chain: FakeChain(pool: 1500));
      await pumpHome(tester, state);
      await showStreak(tester);
      expect(find.byKey(const Key('launch-floor')), findsNothing);
      expect(find.textContaining('Launch also needs'), findsNothing);
    });
  });

  testWidgets('reads again every 20 s, but not while a sheet covers Home', (
    tester,
  ) async {
    final server = FakeServer();
    final state = await makeState(server: server);
    await pumpHome(tester, state);
    int reads() => server.count('GET /rounds');

    var before = reads();
    await tester.pump(const Duration(seconds: 20));
    await settle(tester);
    expect(reads(), before + 1);

    // Under the join sheet Home waits: the sheet reads after its own step.
    await tester.tap(action('Join Morning Movers · 1,000 USD'));
    await settle(tester, 10);
    expect(find.text('Pay the deposit'), findsOneWidget);
    before = reads();
    await tester.pump(const Duration(seconds: 41));
    await settle(tester);
    expect(reads(), before);

    // Uncovered again, it goes on.
    Navigator.of(tester.element(find.text('Pay the deposit'))).pop();
    await settle(tester, 12);
    expect(find.text('Pay the deposit'), findsNothing);
    before = reads();
    await tester.pump(const Duration(seconds: 20));
    await settle(tester);
    expect(reads(), before + 1);
  });

  testWidgets('no round open: a card and "Look again"', (tester) async {
    final server = FakeServer()..round = null;
    final state = await makeState(server: server);
    await pumpHome(tester, state);

    expect(find.text('NO ROUND\nRIGHT NOW.'), findsOneWidget);
    // It says what to do next, not to wait.
    expect(
      find.text(
        'Press + to start one, or to open an invite link someone sent you.',
      ),
      findsOneWidget,
    );
    expect(find.text('YOUR STREAK'), findsNothing);
    server.round = roundJson();
    await tester.tap(action('Look again'));
    await settle(tester);
    expect(action('Join Morning Movers · 1,000 USD'), findsOneWidget);
  });

  testWidgets('server unreachable: one sentence and Try again, no host name', (
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
    await tester.tap(action('Try again'));
    await settle(tester);
    expect(find.text(VerifierApi.unreachable), findsNothing);
    expect(action('Join Morning Movers · 1,000 USD'), findsOneWidget);
  });

  testWidgets('320 by 568 with text at 1.5: Home lays out to its end', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = await makeState(
      chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 3),
    );
    usePhone(tester, size: const Size(320, 568));
    await tester.pumpWidget(inApp(HomeScreen(state: state, showBar: false)));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('testnet-pill')), findsOneWidget);
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -300));
      await settle(tester, 2);
      expect(tester.takeException(), isNull);
    }
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

  group('a Season squad', () {
    testWidgets('before the start: the hint says when check-ins open', (
      tester,
    ) async {
      final server = FakeServer()
        ..round = seasonRoundJson()
        ..members = const [];
      final chain = FakeChain(isMember: true, deposit: 100, pool: 1500);
      final state = await makeState(server: server, chain: chain);
      await pumpHome(tester, state);

      // The hint over the action, and the streak's state, say when.
      expect(find.text('Check-ins open 1 Dec · in 6 days'), findsWidgets);
      expect(action('Check in · Season 1 Squad A'), findsOneWidget);
      // THE PRIZE has no "check in today" before the start.
      expect(find.textContaining('Check in today'), findsNothing);
      await showStreak(tester);
      expect(find.text('Not checked in today'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StreakBlock),
          matching: find.text('Check-ins open 1 Dec · in 6 days'),
        ),
        findsOneWidget,
      );
      // Pressed anyway: the reason, no sheet, nothing sent.
      server.requests.clear();
      await tester.tap(action('Check in · Season 1 Squad A'));
      await settle(tester, 10);
      expect(
        bannerNote.value!.text,
        'Season 1 check-ins open Tue 1 Dec (07:00 in Bangkok). Everyone '
        'starts at 0.',
      );
      expect(find.text('Check in today'), findsNothing);
      expect(server.requests.where((r) => r.startsWith('POST')), isEmpty);
      expect(chain.calls, isEmpty);
      bannerNote.value = null;
    });

    testWidgets('open to join: the usual Join, with its deposit', (
      tester,
    ) async {
      final state = await makeState(
        server: FakeServer()..round = seasonRoundJson(memberCount: 9),
        chain: FakeChain(deposit: 100, pool: 1500),
      );
      await pumpHome(tester, state);
      expect(action('Join Season 1 Squad A · 100 USD'), findsOneWidget);
      expect(enabled(tester, 'Join Season 1 Squad A · 100 USD'), isTrue);
    });

    testWidgets('full: Home offers no Join, and says why', (tester) async {
      final state = await makeState(
        server: FakeServer()..round = seasonRoundJson(memberCount: 10),
        chain: FakeChain(deposit: 100, pool: 1500),
      );
      await pumpHome(tester, state);
      expect(action('Squad full'), findsOneWidget);
      expect(enabled(tester, 'Squad full'), isFalse);
      expect(
        find.text(
          'The contract still takes joins; the app stops here so everyone '
          'starts fair.',
        ),
        findsOneWidget,
      );
      expect(action('Join Season 1 Squad A · 100 USD'), findsNothing);
    });

    testWidgets(
      'after 30 Dec: one short line, the server\'s words on a press',
      (tester) async {
        final server = FakeServer()
          ..round = seasonRoundJson(totalCheckIns: 230, memberCount: 10);
        final chain = FakeChain(
          isMember: true,
          deposit: 100,
          pool: 1500,
          daysOf: 25,
          totalCheckIns: 230,
        );
        final state = await makeState(
          server: server,
          chain: chain,
          now: DateTime.utc(2026, 12, 31, 3),
        );
        await pumpHome(tester, state);

        // The hint over the action and the streak's badge (one line, cut with
        // an ellipsis when too long) say it in a few words.
        expect(find.text('Check-ins ended 30 Dec'), findsWidgets);
        expect(action('Check in · Season 1 Squad A'), findsOneWidget);
        await showStreak(tester);
        final badge = find.descendant(
          of: find.byType(StreakBlock),
          matching: find.text('Check-ins ended 30 Dec'),
        );
        expect(badge, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(badge).didExceedMaxLines,
          isFalse,
        );

        // Pressed anyway: the server's own sentence, no sheet, nothing sent.
        server.requests.clear();
        await tester.tap(action('Check in · Season 1 Squad A'));
        await settle(tester, 10);
        expect(
          bannerNote.value!.text,
          'Season 1 check-ins have ended. The last day was Wed 30 Dec.',
        );
        expect(server.requests.where((r) => r.startsWith('POST')), isEmpty);
        expect(chain.calls, isEmpty);
        bannerNote.value = null;
      },
    );

    testWidgets('after 7 Dec: "Joining closed 7 Dec"', (tester) async {
      final state = await makeState(
        server: FakeServer()
          ..round = seasonRoundJson(totalCheckIns: 70, memberCount: 10),
        chain: FakeChain(deposit: 100, pool: 1500, totalCheckIns: 70),
        now: DateTime.utc(2026, 12, 8, 9),
      );
      await pumpHome(tester, state);
      expect(action('Joining closed 7 Dec'), findsOneWidget);
      expect(enabled(tester, 'Joining closed 7 Dec'), isFalse);
    });
  });
}
