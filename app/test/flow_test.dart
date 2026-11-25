// The join sheet's two steps, the check-in on the web and on a phone,
// onboarding and routing, the result and Account.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/router.dart';
import 'package:pacepact/screens/account_screen.dart';
import 'package:pacepact/screens/checkin_sheet.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/screens/join_sheet.dart';
import 'package:pacepact/screens/onboarding_screen.dart';
import 'package:pacepact/screens/result_screen.dart';
import 'package:pacepact/util/format.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/dot_matrix.dart';

import 'support.dart';

Finder button(String label) => find.widgetWithText(PillButton, label);

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

void main() {
  tearDown(() {
    bannerNote.value = null;
    auroraTone.value = AuroraPalette.ink;
  });

  group('join sheet', () {
    testWidgets('shows the deposit and where it goes', (tester) async {
      final state = await makeState();
      await pumpBody(tester, JoinSheet(state: state));

      expect(find.text('Pay the deposit'), findsOneWidget);
      expect(find.text('Deposit'), findsOneWidget);
      expect(find.text('1,000 USD'), findsOneWidget);
      expect(find.text('To the prize'), findsOneWidget);
      expect(find.text('700 USD · 70%'), findsOneWidget);
      expect(find.text('To the launch pool'), findsOneWidget);
      expect(find.text('300 USD · 30%'), findsOneWidget);
      expect(find.text('If it has not by 2 Dec 2026'), findsOneWidget);
      expect(find.text('Full deposit back'), findsOneWidget);
      // The two steps. The first says plainly what it stands in for.
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
        find.textContaining('Approves, then pays 1,000 USD'),
        findsOneWidget,
      );
    });

    testWidgets('step 1 mints the deposit, step 2 approves and joins', (
      tester,
    ) async {
      final chain = FakeChain();
      final state = await makeState(chain: chain);
      await pumpBody(tester, JoinSheet(state: state));

      // Step 1: the wallet mints the deposit amount to itself.
      expect(button('Get test dollars'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.tap(button('Get test dollars'));
      await settle(tester);
      expect(chain.calls, ['mint 1000']);
      expect(
        find.byIcon(Icons.check_rounded),
        findsOneWidget,
        reason: 'step 1',
      );
      expect(find.text('1,000 USD'), findsNWidgets(2), reason: 'the balance');

      // Step 2: pay it into the round.
      expect(button('Get test dollars'), findsNothing);
      await tester.tap(button('Pay deposit · 1,000 USD'));
      await settle(tester);
      expect(chain.calls, ['mint 1000', 'join 1000']);
      expect(state.isMember, isTrue);
      expect(find.text('YOU\'RE IN.'), findsOneWidget);
      expect(button('Let\'s go'), findsOneWidget);
    });

    testWidgets('a wallet that already holds the deposit starts at step 2', (
      tester,
    ) async {
      final state = await makeState(chain: FakeChain(dollars: 2500));
      await pumpBody(tester, JoinSheet(state: state));
      expect(button('Get test dollars'), findsNothing);
      expect(button('Pay deposit · 1,000 USD'), findsOneWidget);
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
      await pumpBody(tester, JoinSheet(state: state));

      await tester.tap(button('Get test dollars'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Preparing your wallet:'), findsOneWidget);
      expect(find.text('Preparing your wallet…'), findsOneWidget);
      expect(chain.calls, isEmpty, reason: 'nothing is sent without gas');

      // The faucet's transfer arrives.
      chain.bnb = usd(0.03);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.textContaining('Preparing your wallet'), findsNothing);
      expect(chain.calls, ['mint 1000']);
      expect(button('Pay deposit · 1,000 USD'), findsOneWidget);
    });

    testWidgets('a failed step is one sentence and the button says Retry', (
      tester,
    ) async {
      final chain = FakeChain(fail: 'mint');
      final state = await makeState(chain: chain);
      await pumpBody(tester, JoinSheet(state: state));

      await tester.tap(button('Get test dollars'));
      await settle(tester);
      expect(find.text('The mint was rejected. Try again.'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      await tester.tap(button('Retry'));
      await settle(tester);
      expect(chain.calls, ['mint 1000']);
      expect(button('Pay deposit · 1,000 USD'), findsOneWidget);
    });
  });

  group('check-in', () {
    testWidgets('web: a number field labelled self-reported, then the tx', (
      tester,
    ) async {
      final chain = FakeChain(isMember: true);
      final server = FakeServer();
      final state = await makeState(chain: chain, server: server);
      await pumpBody(tester, CheckInSheet(state: state));

      expect(find.text('Self-reported, testnet only'), findsOneWidget);
      expect(find.byKey(const Key('steps')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('steps')), '6214');
      await tester.tap(button('Check in'));
      await settle(tester);

      expect(server.bodies['/checkin']!['steps'], 6214);
      expect(server.bodies['/checkin']!['source'], 'self');
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
      await pumpBody(tester, CheckInSheet(state: state));

      await tester.enterText(find.byKey(const Key('steps')), '12');
      await tester.tap(button('Check in'));
      await settle(tester);
      expect(
        find.text(
          'A check-in needs at least 1,000 steps today. You have 12 so far.',
        ),
        findsOneWidget,
      );
      expect(server.count('POST /checkin'), 0);
      expect(button('Retry'), findsOneWidget);
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
      await pumpBody(tester, CheckInSheet(state: state));

      expect(find.text('6,214'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.byKey(const Key('steps')), findsNothing);
      expect(find.text('Self-reported, testnet only'), findsNothing);
      await tester.tap(button('Check in'));
      await settle(tester);
      expect(server.bodies['/checkin']!['steps'], 6214);
      expect(server.bodies['/checkin']!['source'], 'healthkit');
      expect(chain.calls, ['checkIn 20782']);
      expect(find.text('CHECKED IN.'), findsOneWidget);
    });

    testWidgets('phone: under the minimum the action waits', (tester) async {
      final health = FakeHealth(available: true, steps: 300);
      final state = await makeState(
        chain: FakeChain(isMember: true),
        health: health,
      );
      await pumpBody(tester, CheckInSheet(state: state));

      expect(find.text('300'), findsOneWidget);
      expect(find.text('Keep going'), findsOneWidget);
      expect(enabled(tester, 'Check in'), isFalse);
      health.steps = 1200;
      await tester.tap(button('Read my steps again'));
      await settle(tester);
      expect(find.text('1,200'), findsOneWidget);
      expect(enabled(tester, 'Check in'), isTrue);
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
      await pumpBody(tester, CheckInSheet(state: state));

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
      await pumpBody(tester, CheckInSheet(state: state));

      await tester.enterText(find.byKey(const Key('steps')), '6214');
      await tester.tap(button('Check in'));
      await settle(tester);
      expect(find.text('The checkIn was rejected. Try again.'), findsOneWidget);
      expect(find.byKey(const Key('steps')), findsNothing);
      await tester.tap(button('Retry'));
      await settle(tester);
      expect(server.count('POST /checkin'), 1, reason: 'asked once');
      expect(chain.calls, ['checkIn 20782']);
      expect(find.text('CHECKED IN.'), findsOneWidget);
    });
  });

  group('onboarding and routing', () {
    testWidgets('a new device: hero, one button, then the browser note', (
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

      await press(tester, 'Get started');
      await settle(tester, 12);
      // The wallet was made silently and the faucet asked in the background.
      expect(store.key, isNotNull);
      expect(server.count('POST /faucet'), 1);
      expect(find.text('CHECK IN\nIN THE BROWSER'), findsOneWidget);
      expect(find.text('Self-reported, testnet only.'), findsOneWidget);
      expect(find.text('Check-ins are attested, not proven.'), findsOneWidget);

      await press(tester, 'Continue');
      await settle(tester, 12);
      expect(store.onboarded, isTrue);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(button('Join for 1,000 USD'), findsOneWidget);
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
      expect(find.text('CONNECT\nHEALTH CONNECT'), findsOneWidget);
      expect(find.text('Steps today'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
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

    testWidgets('the floating bar goes from Home to Account and back', (
      tester,
    ) async {
      final state = await makeState();
      await pumpApp(tester, state);
      await tester.tap(find.byTooltip('Account'));
      await settle(tester, 12);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      await tester.tap(find.byTooltip('Home'));
      await settle(tester, 12);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('addresses of earlier builds lead Home', (tester) async {
      final state = await makeState();
      await pumpApp(tester, state, location: '/clubs');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('the result opens only after the launch', (tester) async {
      final open = await makeState();
      await pumpApp(tester, open, location: '/result');
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('"Claim your share" on Home opens the result', (tester) async {
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
      await tester.tap(button('Claim your share'));
      await settle(tester, 12);
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text('THE TOKEN\nIS LIVE.'), findsOneWidget);
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
      expect(find.text('tokens'), findsOneWidget);

      await tester.tap(button('Claim'));
      await settle(tester);
      expect(chain.calls, ['claim']);
      expect(button('Nothing more to claim yet'), findsOneWidget);
      expect(enabled(tester, 'Nothing more to claim yet'), isFalse);
      await tester.scrollUntilVisible(
        find.textContaining('250,000 tokens · 1,068.59 USD'),
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

  group('account', () {
    testWidgets('address, balances and "Back up key"', (tester) async {
      final state = await makeState(chain: FakeChain(dollars: 1000));
      await pumpBody(tester, AccountScreen(state: state, showBar: false));

      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text(shortAddress(state.address)), findsOneWidget);
      expect(
        tester.widget<DotMatrixText>(find.byType(DotMatrixText)).text,
        '1,000',
      );
      expect(find.text('0.03 tBNB'), findsOneWidget);
      expect(find.text('BSC testnet'), findsOneWidget);

      // The key shows only after the person asks for it.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Show private key'),
        200,
        scrollable: list,
      );
      expect(find.text(testKeyHex), findsNothing);
      await tester.tap(find.text('Show private key'));
      await settle(tester);
      expect(find.text(testKeyHex), findsOneWidget);
      expect(button('Copy key'), findsOneWidget);
    });

    testWidgets('"Import a key" takes a pasted key', (tester) async {
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(store: store);
      await pumpBody(tester, ImportKeySheet(state: state));

      expect(enabled(tester, 'Import'), isFalse);
      await tester.enterText(find.byKey(const Key('import-key')), 'zz' * 32);
      await settle(tester);
      await tester.tap(button('Import'));
      await settle(tester);
      expect(find.textContaining('That is not a private key'), findsOneWidget);
      expect(store.key!.address, testKey.address);
    });

    testWidgets('"Start a new round": the form, then the address to copy', (
      tester,
    ) async {
      final chain = FakeChain();
      final state = await makeState(chain: chain);
      await pumpBody(
        tester,
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: StartRoundForm(state: state, missing: const []),
        ),
      );

      // The defaults: 1,000 USD, 30% to the pool, 6 check-ins, 7 days.
      expect(
        find.textContaining('Flap needs 1,500 USD in the pool: 5 members'),
        findsOneWidget,
      );
      await tester.ensureVisible(button('Start the round'));
      await tester.tap(button('Start the round'));
      await settle(tester);
      expect(find.text('Give the round a name first.'), findsOneWidget);
      expect(chain.calls, isEmpty);

      await tester.enterText(
        find.byKey(const Key('round-name')),
        'Lumpini Striders',
      );
      await tester.ensureVisible(button('Retry'));
      await tester.tap(button('Retry'));
      await settle(tester);
      expect(chain.calls, ['createRound Lumpini Striders LS 1000 3000 6']);
      expect(
        find.text('0x5000000000000000000000000000000000000005'),
        findsOneWidget,
      );
      expect(button('Copy round address'), findsOneWidget);
      expect(find.textContaining('whoever runs the server'), findsOneWidget);
    });

    testWidgets('a build without addresses says which values are missing', (
      tester,
    ) async {
      final state = await makeState();
      await pumpBody(
        tester,
        StartRoundForm(
          state: state,
          missing: const ['CHECKIN_LAUNCHER_FACTORY', 'ATTESTER_ADDRESS'],
        ),
      );
      expect(find.text('This build cannot start a round yet.'), findsOneWidget);
      expect(find.text('CHECKIN_LAUNCHER_FACTORY'), findsOneWidget);
      expect(find.text('ATTESTER_ADDRESS'), findsOneWidget);
      expect(button('Start the round'), findsNothing);
    });
  });
}
