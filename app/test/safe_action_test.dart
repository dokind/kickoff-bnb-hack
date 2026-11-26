// Nobody pays into a round they did not mean. Three rules, each held here
// with fake timers:
//   1. Home's cards move on by themselves only until the person first
//      touches Home in this session, scrolls it, or anything is opened over
//      it (a sheet, a dialog, by touch or not); never when the app was
//      opened from a round's link, never when the platform asks for reduced
//      motion. A sheet's pay button names its round for as long as it is
//      open.
//   2. The primary action names the round it acts on, and the join sheet,
//      the check-in sheet and the result name it in their title.
//   3. The action is for the round it named when it was pressed: a sheet
//      keeps acting on that round when the selection changes behind it.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/router.dart';
import 'package:pacepact/screens/checkin_sheet.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/screens/join_sheet.dart';
import 'package:pacepact/screens/result_screen.dart';
import 'package:pacepact/screens/sponsor_sheet.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/round_slider.dart';

import 'support.dart';

/// "Demo Day" (featured, a 500 test USD deposit) and two more rounds.
FakeServer threeRounds() => FakeServer()
  ..round = (roundJson(name: 'Demo Day')..['deposit'] = '500')
  ..more.addAll([
    roundJson(at: launcherB, name: 'Lumpini Striders'),
    roundJson(at: launcherC, name: 'Night Owls', deadline: 1796860800),
  ]);

/// The first round's contract takes 500, the others 1,000.
FakeChain threeChains({num dollars = 0}) =>
    FakeChain(deposit: 500, dollars: dollars)
      ..others[launcherB] = FakeChain()
      ..others[launcherC] = FakeChain();

/// Home with motion on, so the cards move by themselves.
Future<void> pumpHome(WidgetTester tester, AppState state) async {
  usePhone(tester);
  await tester.pumpWidget(inMotion(HomeScreen(state: state, showBar: false)));
  await settle(tester);
}

/// Lets [time] pass, then the frames of a card sliding in.
Future<void> wait(WidgetTester tester, Duration time) async {
  await tester.pump(time);
  await settle(tester, 14);
}

RoundSliderState slider(WidgetTester tester) =>
    tester.state<RoundSliderState>(find.byType(RoundSlider));

/// The pill whose whole label is [label], however much of it is drawn.
Finder action(String label) =>
    find.byWidgetPredicate((w) => w is PillButton && w.label == label);

/// The one primary action's whole label.
String primaryLabel(WidgetTester tester) => tester
    .widget<PillButton>(
      find.descendant(
        of: find.byKey(const Key('home-action')),
        matching: find.byType(PillButton),
      ),
    )
    .label;

/// The text a pill draws for its label.
String drawn(WidgetTester tester, Finder pill) => tester
    .widget<Text>(find.descendant(of: pill, matching: find.byType(Text)))
    .data!;

/// The round named in the title area of [within].
String namedIn(WidgetTester tester, Type within) => tester
    .widget<RoundLabel>(
      find.descendant(
        of: find.byType(within),
        matching: find.byType(RoundLabel),
      ),
    )
    .name;

const long = Duration(seconds: 60);

void main() {
  tearDown(() {
    bannerNote.value = null;
    auroraTone.value = AuroraPalette.ink;
  });

  group('1. moving on by itself ends at the first touch', () {
    testWidgets('untouched, the cards move on every 5 seconds', (tester) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];
      expect(state.autoAdvance, isTrue);
      expect(slider(tester).waiting, isTrue);
      await wait(tester, const Duration(milliseconds: 5100));
      expect(state.selected, order[1]);
      await wait(tester, const Duration(seconds: 5));
      expect(state.selected, order[2]);
    });

    testWidgets('a tap anywhere on Home stops them for the session', (
      tester,
    ) async {
      final state = await makeState(
        server: threeRounds(),
        chain: threeChains(),
      );
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      // The greeting: nothing happens there, but it is a touch on Home.
      await tester.tap(find.text('3 rounds'));
      await settle(tester);
      expect(state.autoAdvance, isFalse);
      expect(slider(tester).waiting, isFalse);
      await wait(tester, long);
      expect(state.selected, order[0]);
      expect(primaryLabel(tester), 'Join Demo Day · 500 USD');

      // Leaving Home and coming back in the same session does not start
      // them again: a new Home, the same app.
      await tester.pumpWidget(inMotion(const SizedBox()));
      await tester.pumpWidget(
        inMotion(HomeScreen(state: state, showBar: false)),
      );
      await settle(tester);
      expect(slider(tester).waiting, isFalse);
      await wait(tester, long);
      expect(state.selected, order[0]);
    });

    testWidgets('a scroll of the page stops them', (tester) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      await tester.drag(
        find.byKey(const Key('home-list')),
        const Offset(0, -80),
        warnIfMissed: false,
      );
      await settle(tester);
      // Back at the top, where the cards would otherwise move.
      await tester.drag(
        find.byKey(const Key('home-list')),
        const Offset(0, 200),
        warnIfMissed: false,
      );
      await settle(tester, 20);
      expect(state.autoAdvance, isFalse);
      await wait(tester, long);
      expect(state.selected, order[0]);
    });

    testWidgets('a mouse wheel stops them', (tester) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      // The wheel turns over the lower part of Home, off the cards.
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final at = tester.getCenter(find.byKey(const Key('home-action')));
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 1)));
      await settle(tester);
      expect(state.autoAdvance, isFalse);
      expect(slider(tester).waiting, isFalse);
      await wait(tester, long);
      expect(state.selected, order[0]);
    });

    testWidgets('a trackpad scroll stops them', (tester) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = tester.getCenter(find.byKey(const Key('home-action')));
      await tester.sendEventToBinding(pad.panZoomStart(at));
      await tester.sendEventToBinding(pad.panZoomEnd());
      await settle(tester);
      expect(state.autoAdvance, isFalse);
      expect(slider(tester).waiting, isFalse);
      await wait(tester, long);
      expect(state.selected, order[0]);
    });

    testWidgets('a swipe of the cards stops them on the card chosen', (
      tester,
    ) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester, 14);
      expect(state.selected, order[1]);
      expect(state.autoAdvance, isFalse);
      await wait(tester, long);
      expect(state.selected, order[1]);
    });

    testWidgets('a touch while a card is sliding in takes the move back', (
      tester,
    ) async {
      final state = await makeState(
        server: threeRounds(),
        chain: threeChains(),
      );
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      // Five seconds: the next card starts to slide in. A tenth of a second
      // later it is on its way, and the action still says "Demo Day".
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 100));
      final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
      expect(pages.page, inExclusiveRange(0.0, 0.5));
      expect(primaryLabel(tester), 'Join Demo Day · 500 USD');

      // The finger comes down on the action at that moment.
      final finger = await tester.startGesture(
        tester.getCenter(action('Join Demo Day · 500 USD')),
      );
      await settle(tester, 14);
      expect(pages.page, 0, reason: 'the card went back');
      expect(state.selected, order[0]);
      expect(primaryLabel(tester), 'Join Demo Day · 500 USD');

      // It lifts: the sheet is for the round the button named.
      await finger.up();
      await settle(tester, 14);
      expect(namedIn(tester, JoinSheet), 'Demo Day');
      expect(
        tester.widget<JoinSheet>(find.byType(JoinSheet)).round.id,
        order[0],
      );
      await wait(tester, long);
      expect(state.selected, order[0]);
    });

    testWidgets('a sheet opened without a touch stops them for good', (
      tester,
    ) async {
      final state = await makeState(
        server: threeRounds(),
        chain: threeChains(),
      );
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];
      final home = tester.element(find.byType(HomeScreen));
      expect(slider(tester).waiting, isTrue);

      // A sheet that opened without a touch on Home (the keyboard, a link).
      showJoinSheet(home, state, state.round!);
      await settle(tester, 14);
      expect(find.byType(JoinSheet), findsOneWidget);
      expect(slider(tester).waiting, isFalse);
      await wait(tester, long);
      expect(state.selected, order[0]);
      Navigator.of(home).pop();
      await settle(tester, 14);
      expect(find.byType(JoinSheet), findsNothing);

      // Closed: nobody touched Home, and still the cards stay. The person
      // was dealing with this round.
      await wait(tester, long);
      expect(state.selected, order[0]);
      expect(slider(tester).waiting, isFalse);
      expect(primaryLabel(tester), 'Join Demo Day · 500 USD');
    });

    testWidgets('a dialog opened without a touch stops them for good', (
      tester,
    ) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];
      final home = tester.element(find.byType(HomeScreen));

      showDialog<void>(
        context: home,
        builder: (_) => const AlertDialog(title: Text('A dialog')),
      );
      await settle(tester, 14);
      expect(find.text('A dialog'), findsOneWidget);
      await wait(tester, long);
      expect(state.selected, order[0]);
      Navigator.of(home).pop();
      await settle(tester, 14);
      await wait(tester, long);
      expect(state.selected, order[0]);
      expect(slider(tester).waiting, isFalse);
    });

    testWidgets('a scroll of Home that is no touch stops them for good', (
      tester,
    ) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];
      final page = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('home-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // The keyboard's Page Down, or a scroll bar: no finger on Home.
      page.position.animateTo(
        60,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      await settle(tester, 8);
      page.position.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      await settle(tester, 8);
      expect(slider(tester).waiting, isFalse);
      await wait(tester, long);
      expect(state.selected, order[0]);
    });

    testWidgets('the join sheet\'s pay button keeps naming its round', (
      tester,
    ) async {
      final state = await makeState(
        server: threeRounds(),
        chain: threeChains(dollars: 2000),
      );
      await pumpHome(tester, state);
      final home = tester.element(find.byType(HomeScreen));
      // Opened without a touch, while the cards could still move.
      showJoinSheet(home, state, state.round!);
      await settle(tester, 14);
      expect(namedIn(tester, JoinSheet), 'Demo Day');
      expect(action('Pay deposit · 500 test USD'), findsOneWidget);

      // A minute of looking at it: the round and the amount on the button
      // do not change, and neither does the card behind it.
      for (var i = 0; i < 12; i++) {
        await wait(tester, const Duration(seconds: 5));
        expect(namedIn(tester, JoinSheet), 'Demo Day');
        expect(action('Pay deposit · 500 test USD'), findsOneWidget);
        expect(state.selected, launcher);
      }
    });

    testWidgets('never when the app was opened from a round link', (
      tester,
    ) async {
      Future<AppState> open(String location) async {
        final state = await makeState(server: threeRounds());
        usePhone(tester);
        await tester.pumpWidget(
          MaterialApp.router(
            key: UniqueKey(),
            theme: inAppTheme,
            routerConfig: buildRouter(state, initialLocation: location),
            builder: (context, child) => AppBackdrop(child: child!),
          ),
        );
        await settle(tester, 12);
        return state;
      }

      // Opened plainly, this same app moves on.
      final plain = await open('/');
      expect(plain.autoAdvance, isTrue);
      await wait(tester, const Duration(milliseconds: 5100));
      expect(plain.selected, launcherB);

      // Opened from the link to "Night Owls", it stays there.
      final linked = await open('/r/$launcherC');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(linked.selected, launcherC);
      expect(linked.autoAdvance, isFalse);
      expect(slider(tester).waiting, isFalse);
      expect(primaryLabel(tester), 'Join Night Owls · 1,000 USD');
      await wait(tester, long);
      expect(linked.selected, launcherC);
      expect(primaryLabel(tester), 'Join Night Owls · 1,000 USD');
    });

    testWidgets('never when the platform asks for reduced motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      expect(slider(tester).waiting, isFalse);
      await wait(tester, long);
      expect(state.selected, order[0]);
    });

    test('it starts again when the app is opened again', () async {
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(server: threeRounds(), store: store);
      state.stopAutoAdvance();
      expect(state.autoAdvance, isFalse);
      // The same device, the app opened again: nothing was kept.
      final again = await makeState(server: threeRounds(), store: store);
      expect(again.autoAdvance, isTrue);
    });
  });

  group('2. the action names its round', () {
    testWidgets('join: the name and the deposit', (tester) async {
      final state = await makeState(
        server: threeRounds(),
        chain: threeChains(),
      );
      await pumpHome(tester, state);
      expect(primaryLabel(tester), 'Join Demo Day · 500 USD');
      // It follows the card in view.
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester, 14);
      expect(primaryLabel(tester), 'Join Lumpini Striders · 1,000 USD');
    });

    testWidgets('check in, launch and claim name it too', (tester) async {
      Future<String> labelFor(FakeChain chain, FakeServer server) async {
        final state = await makeState(chain: chain, server: server);
        await tester.pumpWidget(const SizedBox());
        await pumpHome(tester, state);
        return primaryLabel(tester);
      }

      expect(
        await labelFor(
          FakeChain(isMember: true),
          FakeServer()..round = roundJson(name: 'Demo Day'),
        ),
        'Check in · Demo Day',
      );
      expect(
        await labelFor(
          FakeChain(isMember: true, totalCheckIns: 6, pool: 1500),
          FakeServer()..round = roundJson(name: 'Demo Day', totalCheckIns: 6),
        ),
        'Launch Demo Day',
      );
      expect(
        await labelFor(
          FakeChain(launched: true, isMember: true, daysOf: 3),
          FakeServer()..round = roundJson(name: 'Demo Day', launched: true),
        ),
        'Claim · Demo Day',
      );
      expect(
        await labelFor(
          FakeChain(launched: true),
          FakeServer()..round = roundJson(name: 'Demo Day', launched: true),
        ),
        'See the result · Demo Day',
      );
      expect(
        await labelFor(
          FakeChain(isMember: true, refundable: 1000),
          FakeServer()
            ..round = roundJson(name: 'Demo Day', deadline: 1795000000),
        ),
        'Deposit back · Demo Day',
      );
    });

    testWidgets('a long name is cut short at 390pt; the amount stays', (
      tester,
    ) async {
      const name = 'The Saturday Morning Riverside Running And Coffee Society';
      const label = 'Join $name · 500 USD';
      final state = await makeState(
        chain: FakeChain(deposit: 500),
        server: FakeServer()..round = roundJson(name: name),
      );
      // The test font is about twice as wide as the app's; at this scale a
      // line holds about what it holds on a phone.
      usePhone(tester);
      await tester.pumpWidget(
        inMotion(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(0.55),
            ),
            child: HomeScreen(state: state, showBar: false),
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(HomeScreen)).width, 390);

      final pill = action(label);
      expect(pill, findsOneWidget, reason: 'the whole label is still known');
      final text = drawn(tester, pill);
      expect(text, startsWith('Join The Saturday'));
      expect(text, endsWith('… · 500 USD'));
      expect(text.length, lessThan(label.length));
      // Drawn inside the pill, on one line.
      final box = tester.getRect(pill);
      final line = tester.getRect(
        find.descendant(of: pill, matching: find.byType(Text)),
      );
      expect(line.left, greaterThan(box.left));
      expect(line.right, lessThan(box.right));
      expect(line.height, lessThan(20));

      // At the test font's full width almost nothing of the name fits, and
      // it still does not overflow.
      await tester.pumpWidget(
        inMotion(HomeScreen(state: state, showBar: false)),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(drawn(tester, action(label)), 'Join T… · 500 USD');
    });

    test('fitting a label: only the name gives way', () {
      // Ten units a letter.
      double widthOf(String text) => text.length * 10;
      String fit(String label, String? name, double width) =>
          PillButton.fitLabel(label, name, width, widthOf);

      expect(
        fit('Join Demo Day · 500 USD', 'Demo Day', 230),
        'Join Demo Day · 500 USD',
      );
      expect(
        fit('Join Demo Day · 500 USD', 'Demo Day', 220),
        'Join Demo D… · 500 USD',
      );
      expect(
        fit('Join Demo Day · 500 USD', 'Demo Day', 200),
        'Join Demo… · 500 USD',
      );
      expect(fit('Check in · Demo Day', 'Demo Day', 150), 'Check in · Dem…');
      expect(fit('Launch Demo Day', 'Demo Day', 100), 'Launch De…');
      // At least one letter of the name is kept, however narrow.
      expect(fit('Claim · Demo Day', 'Demo Day', 10), 'Claim · D…');
      // Nothing to cut: the label is left alone.
      expect(fit('Checked in', null, 10), 'Checked in');
      expect(fit('Launch X', 'X', 10), 'Launch X');
    });

    testWidgets('the join sheet names the round in its title', (tester) async {
      final state = await makeState(
        server: threeRounds(),
        chain: threeChains(),
      );
      await pumpHome(tester, state);
      await tester.tap(action('Join Demo Day · 500 USD'));
      await settle(tester, 14);
      expect(namedIn(tester, JoinSheet), 'Demo Day');
      // Right over the title.
      final name = tester.getRect(
        find.descendant(
          of: find.byType(JoinSheet),
          matching: find.byType(RoundLabel),
        ),
      );
      final title = tester.getRect(find.text('Pay the deposit'));
      expect(name.bottom, lessThanOrEqualTo(title.top));
      expect(title.top - name.bottom, lessThan(12));
    });

    testWidgets('the check-in sheet names the round in its title', (
      tester,
    ) async {
      final state = await makeState(
        server: threeRounds(),
        chain: FakeChain(isMember: true, dollars: 0),
      );
      await pumpHome(tester, state);
      await tester.tap(action('Check in · Demo Day'));
      await settle(tester, 14);
      expect(namedIn(tester, CheckInSheet), 'Demo Day');
      final name = tester.getRect(
        find.descendant(
          of: find.byType(CheckInSheet),
          matching: find.byType(RoundLabel),
        ),
      );
      final title = tester.getRect(find.text('Check in today'));
      expect(name.bottom, lessThanOrEqualTo(title.top));
      expect(title.top - name.bottom, lessThan(12));
    });

    testWidgets('the result names the round over its title', (tester) async {
      final state = await makeState(
        chain: FakeChain(
          launched: true,
          isMember: true,
          daysOf: 3,
          totalCheckIns: 6,
          claimableQuote: 1050,
        ),
        server: FakeServer()
          ..round = roundJson(
            name: 'Demo Day',
            launched: true,
            totalCheckIns: 6,
          ),
      );
      usePhone(tester);
      await tester.pumpWidget(inApp(ResultScreen(state: state)));
      await settle(tester);
      expect(namedIn(tester, ResultScreen), 'Demo Day');
      final name = tester.getRect(find.byType(RoundLabel));
      final title = tester.getRect(find.text('THE COIN\nIS LIVE.'));
      expect(name.bottom, lessThanOrEqualTo(title.top));
    });
  });

  group('3. the action keeps the round it was pressed for', () {
    testWidgets('the join sheet pays into its round, not the selected one', (
      tester,
    ) async {
      final chain = threeChains();
      final state = await makeState(server: threeRounds(), chain: chain);
      await pumpHome(tester, state);

      await tester.tap(action('Join Demo Day · 500 USD'));
      await settle(tester, 14);
      expect(namedIn(tester, JoinSheet), 'Demo Day');

      // Behind the sheet another card becomes the selected one.
      state.select(launcherB);
      await settle(tester, 14);
      expect(state.selected, launcherB);
      expect(state.round!.name, 'Lumpini Striders');
      expect(state.deposit, usd(1000));

      // The sheet is still about "Demo Day" and its 500.
      expect(namedIn(tester, JoinSheet), 'Demo Day');
      expect(find.text('Pay deposit · 500 test USD'), findsNothing);
      await tester.tap(action('Join with test dollars · 500 test USD'));
      await settle(tester, 14);

      expect(chain.asked, [launcher], reason: 'the deposit went to Demo Day');
      expect(chain.calls, ['mint 500', 'join 500']);
      expect(chain.others[launcherB]!.calls, isEmpty);
      expect(find.text('YOU\'RE IN.'), findsOneWidget);
      expect(namedIn(tester, JoinSheet), 'Demo Day');
      // The selection behind it was left alone, and the app knows which
      // round was joined.
      expect(state.selected, launcherB);
      expect(state.isMemberOf(launcher), isTrue);
      expect(state.isMemberOf(launcherB), isFalse);
    });

    testWidgets('the check-in sheet checks in to its round', (tester) async {
      final chain = FakeChain(isMember: true)
        ..others[launcherB] = FakeChain(isMember: true)
        ..others[launcherC] = FakeChain();
      final server = threeRounds();
      final state = await makeState(server: server, chain: chain);
      await pumpHome(tester, state);

      await tester.tap(action('Check in · Demo Day'));
      await settle(tester, 14);
      state.select(launcherB);
      await settle(tester, 14);
      expect(state.selected, launcherB);
      expect(namedIn(tester, CheckInSheet), 'Demo Day');

      await tester.enterText(find.byKey(const Key('steps')), '6214');
      await tester.tap(action('Check in'));
      await settle(tester, 14);

      expect(chain.asked, [launcher]);
      expect(chain.calls, ['checkIn 20782']);
      expect(chain.others[launcherB]!.calls, isEmpty);
      expect(server.count('POST /rounds/$launcher/checkin'), 1);
      expect(server.count('POST /rounds/$launcherB/checkin'), 0);
      expect(find.text('CHECKED IN.'), findsOneWidget);
      expect(namedIn(tester, CheckInSheet), 'Demo Day');
      expect(state.selected, launcherB);
    });

    testWidgets('the sponsor sheet adds to its round', (tester) async {
      final chain = FakeChain(isMember: true, totalCheckIns: 6, pool: 900)
        ..others[launcherB] = FakeChain()
        ..others[launcherC] = FakeChain();
      final server = threeRounds();
      server.round!['totalCheckIns'] = 6;
      final state = await makeState(server: server, chain: chain);
      await pumpHome(tester, state);

      await tester.tap(action('Sponsor the shop'));
      await settle(tester, 14);
      expect(namedIn(tester, SponsorSheet), 'Demo Day');
      state.select(launcherB);
      await settle(tester, 14);
      await tester.tap(action('Add to the shop'));
      await settle(tester, 14);
      expect(chain.asked, [launcher]);
      expect(chain.calls, ['mint 600', 'sponsor 600']);
      // The sheet's own words for it, as on its title and its button.
      expect(bannerNote.value!.text, '600 test USD added to the shop money.');
    });

    testWidgets('a press that began on one round never lands on another', (
      tester,
    ) async {
      final state = await makeState(
        server: threeRounds(),
        chain: threeChains(),
      );
      await pumpHome(tester, state);
      // The finger is down on "Join Demo Day" when the selection changes
      // under it (not the cards moving, which a touch stops: a link, a
      // round that left the list).
      final finger = await tester.startGesture(
        tester.getCenter(action('Join Demo Day · 500 USD')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      state.select(launcherB);
      await settle(tester);
      expect(primaryLabel(tester), 'Join Lumpini Striders · 1,000 USD');

      // It lifts over a button that now names another round: nothing opens.
      await finger.up();
      await settle(tester, 14);
      expect(find.byType(JoinSheet), findsNothing);

      // A press on the button as it reads now is for the round it names.
      await tester.tap(action('Join Lumpini Striders · 1,000 USD'));
      await settle(tester, 14);
      expect(
        tester.widget<JoinSheet>(find.byType(JoinSheet)).round.id,
        launcherB,
      );
      expect(namedIn(tester, JoinSheet), 'Lumpini Striders');
    });

    test('every action goes to the round it is given', () async {
      final chain = FakeChain(isMember: true, dollars: 500, deposit: 500)
        ..others[launcherB] = FakeChain(isMember: true);
      final server = threeRounds();
      final state = await makeState(server: server, chain: chain);
      state.select(launcherB);
      await state.refresh();
      expect(state.selected, launcherB);

      // Readers for a round that is not the selected one.
      expect(state.roundOf(launcher)!.name, 'Demo Day');
      expect(state.depositOf(launcher), usd(500));
      expect(state.depositOf(launcherB), usd(1000));
      expect(state.deposit, usd(1000));

      await state.payDeposit(launcher: launcher);
      expect(chain.asked, [launcher]);
      expect(chain.calls, ['join 500']);
      await state.checkIn(selfReported: 5000, launcher: launcher);
      await state.launch(launcher: launcher);
      await state.refund(launcher: launcher);
      await state.sponsor(usd(100), launcher: launcher);
      expect(chain.asked, List.filled(5, launcher));
      expect(chain.others[launcherB]!.calls, isEmpty);
      expect(state.selected, launcherB, reason: 'the selection is not moved');

      // With no round given an action is for the selected one, as before.
      await state.checkIn(selfReported: 5000);
      expect(chain.asked.last, launcherB);

      // A round that is not on the slider any more: one sentence, nothing
      // sent.
      await expectLater(
        state.payDeposit(launcher: launcherD),
        throwsA(
          predicate(
            (e) => '$e'.contains('That round is not on Home any more.'),
          ),
        ),
      );
      expect(chain.asked, hasLength(6));
    });
  });
}
