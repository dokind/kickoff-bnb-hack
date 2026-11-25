// The join sheet's two steps, the check-in on the web and on a phone,
// onboarding and routing, the result and Account.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/router.dart';
import 'package:pacepact/screens/account_screen.dart';
import 'package:pacepact/screens/checkin_sheet.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/screens/invite_sheet.dart';
import 'package:pacepact/screens/join_sheet.dart';
import 'package:pacepact/screens/onboarding_screen.dart';
import 'package:pacepact/screens/result_screen.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/util/format.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/dot_matrix.dart';

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
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

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
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));
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
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

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
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));

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
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));

      expect(find.text('Self-reported, testnet only'), findsOneWidget);
      expect(find.byKey(const Key('steps')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('steps')), '6214');
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
      await tester.tap(button('Retry'));
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

      // No wallet yet: the first-run steps come first.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(state.selected, isNull);
      await press(tester, 'Get started');
      await settle(tester, 12);
      await press(tester, 'Continue');
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

    testWidgets('"Start a new round": the form, then the invite sheet', (
      tester,
    ) async {
      final chain = FakeChain();
      // The server finds the new round on chain when it is asked about it.
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Lumpini Striders'));
      server.unlisted.add(createdLauncher); // not shown until registered
      final state = await makeState(chain: chain, server: server);
      expect(state.rounds, hasLength(1));
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
      await settle(tester, 12);
      expect(chain.calls, ['createRound Lumpini Striders LS 1000 3000 6']);

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

      // The invite sheet opens over the form. This build has no web
      // address, so it hands out the round's address.
      expect(find.byType(InviteSheet), findsOneWidget);
      expect(find.text('INVITE'), findsOneWidget);
      expect(find.text('Lumpini Striders'), findsOneWidget);
      expect(find.byKey(const Key('invite-link')), findsOneWidget);
      // The creator can change the listing from the sheet.
      expect(find.byKey(const Key('invite-unlisted')), findsOneWidget);

      await tester.tapAt(const Offset(195, 20)); // the barrier closes it
      await settle(tester, 12);
      expect(find.byType(InviteSheet), findsNothing);
      expect(find.text(createdLauncher), findsOneWidget);
      expect(find.text('It is on your Home now, selected.'), findsOneWidget);
      expect(
        find.text('Listed: everyone sees it in the list on Home.'),
        findsOneWidget,
      );
      expect(button('Invite'), findsOneWidget);
      expect(button('Copy round address'), findsOneWidget);
    });

    testWidgets('the "Unlisted" switch says exactly what it means', (
      tester,
    ) async {
      final chain = FakeChain();
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Night Owls'));
      server.unlisted.add(createdLauncher);
      final state = await makeState(chain: chain, server: server);
      await pumpBody(
        tester,
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: StartRoundForm(state: state, missing: const []),
        ),
      );

      const note =
          'Not shown in the public list. Anyone with the link can still '
          'join, and the chain is public.';
      expect(unlistedNote, note);
      final toggle = find.byKey(const Key('round-unlisted'));
      expect(
        find.descendant(of: toggle, matching: find.text('Unlisted')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: toggle, matching: find.text(note)),
        findsOneWidget,
      );
      expect(tester.widget<CapsuleToggle>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await settle(tester);
      expect(tester.widget<CapsuleToggle>(toggle).value, isTrue);

      await tester.enterText(find.byKey(const Key('round-name')), 'Night Owls');
      await settle(tester);
      await press(tester, 'Start the round');
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
      expect(find.text('Unlisted. $note'), findsOneWidget);
    });

    testWidgets('a listing the server did not save says so, with a way on', (
      tester,
    ) async {
      // The server has not found the new round on chain yet.
      final server = FakeServer();
      final state = await makeState(server: server);
      await pumpBody(
        tester,
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: StartRoundForm(state: state, missing: const []),
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('round-unlisted')));
      await tester.tap(find.byKey(const Key('round-unlisted')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('round-name')), 'Night Owls');
      await settle(tester);
      await press(tester, 'Start the round');
      await settle(tester, 12);
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 12);

      // Still on this device's slider, from what was sent to the chain.
      expect(state.selected, createdLauncher);
      expect(state.round!.name, 'Night Owls');
      expect(state.knownRound(createdLauncher)!.registered, isFalse);
      expect(
        find.textContaining('has not found this round on chain yet'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Until it is saved as unlisted, the round can show in the public '
          'list.',
        ),
        findsOneWidget,
      );

      // The server finds it; "Save again" goes through.
      server.more.add(roundJson(at: createdLauncher, name: 'Night Owls'));
      await press(tester, 'Save again');
      await settle(tester, 12);
      expect(state.knownRound(createdLauncher)!.registered, isTrue);
      expect(server.unlisted, contains(createdLauncher));
      expect(find.textContaining('Unlisted. Not shown'), findsOneWidget);
    });

    testWidgets('"Open a round" takes a pasted link or address', (
      tester,
    ) async {
      final server = FakeServer()
        ..more.add(roundJson(at: launcherB, name: 'Night Owls'));
      server.unlisted.add(launcherB);
      final state = await makeState(server: server);
      await pumpBody(
        tester,
        Padding(
          padding: const EdgeInsets.all(20),
          child: OpenRoundForm(state: state),
        ),
      );
      expect(enabled(tester, 'Open round'), isFalse);

      await tester.enterText(find.byKey(const Key('open-round')), 'hello');
      await settle(tester);
      await tester.tap(button('Open round'));
      await settle(tester);
      expect(
        find.text('That is not a round link or a round address.'),
        findsOneWidget,
      );

      // An address our factory never made.
      await tester.enterText(find.byKey(const Key('open-round')), launcherD);
      await settle(tester);
      await tester.tap(button('Open round'));
      await settle(tester, 12);
      expect(find.text('That link does not lead to a round.'), findsOneWidget);
      expect(state.selected, launcher);

      // A link to an unlisted round opens it.
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
