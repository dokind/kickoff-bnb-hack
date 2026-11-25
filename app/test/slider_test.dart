// Home's round cards: one card per round, the dots, moving on by itself
// and when it does not, the invite sheet, and the scrim behind the floating
// action. The rules that keep the action on the round the person meant are
// in safe_action_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/config.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/screens/invite_sheet.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/round_slider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support.dart';

/// The featured round and two more.
FakeServer threeRounds() => FakeServer()
  ..more.addAll([
    roundJson(
      at: launcherB,
      name: 'Lumpini Striders',
      totalCheckIns: 5,
      memberCount: 4,
      prizeNow: '2800',
    ),
    roundJson(at: launcherC, name: 'Night Owls', deadline: 1796860800),
  ]);

/// Home with motion on (the cards move by themselves) or reduced.
Future<void> pumpHome(
  WidgetTester tester,
  AppState state, {
  bool motion = true,
}) async {
  usePhone(tester);
  final home = HomeScreen(state: state, showBar: false);
  await tester.pumpWidget(motion ? inMotion(home) : inApp(home));
  await settle(tester);
}

/// Lets [time] pass, then the frames of a card sliding in.
Future<void> wait(WidgetTester tester, Duration time) async {
  await tester.pump(time);
  await settle(tester, 14);
}

/// Scrolls Home's content as far up as it goes. The list is laid out as it
/// scrolls, so one long drag is not enough.
Future<void> toTheEnd(WidgetTester tester) async {
  final list = find.byKey(const Key('home-list'));
  for (var i = 0; i < 14; i++) {
    await tester.drag(list, const Offset(0, -500), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settle(tester, 14);
}

RoundSliderState slider(WidgetTester tester) =>
    tester.state<RoundSliderState>(find.byType(RoundSlider));

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is PillButton && w.label == label);

void main() {
  tearDown(() => bannerNote.value = null);

  group('the cards', () {
    testWidgets('one round is a plain card: nothing to swipe, no dots', (
      tester,
    ) async {
      final state = await makeState();
      await pumpHome(tester, state);

      expect(find.byType(RoundCard), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
      expect(find.byKey(const Key('round-dots')), findsNothing);
      expect(slider(tester).waiting, isFalse);
      expect(find.text('1 round'), findsOneWidget);
      // The card: name, where it stands, the bar, prize, members, deadline.
      expect(find.text('FEATURED ROUND'), findsOneWidget);
      expect(find.text('Morning Movers'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('2 / 6 check-ins'), findsOneWidget);
      expect(find.text('Prize so far 2,100 USD'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RoundCard),
          matching: find.text('3 members'),
        ),
        findsOneWidget,
      );
      expect(find.text('Closes 2 Dec 2026'), findsOneWidget);
      expect(find.text('You\'re in'), findsNothing);
      // Still nothing after a long while.
      await wait(tester, const Duration(seconds: 30));
      expect(state.selected, launcher);
    });

    testWidgets('several rounds: a card each, dots, the first selected', (
      tester,
    ) async {
      final chain = FakeChain()..others[launcherB] = FakeChain(isMember: true);
      final state = await makeState(server: threeRounds(), chain: chain);
      await pumpHome(tester, state, motion: false);

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byKey(const Key('round-dots')), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('round-dot-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('round-dot-3')), findsNothing);
      expect(find.text('3 rounds'), findsOneWidget);
      // Featured first, then the round this wallet joined.
      expect(state.rounds.map((r) => r.id), [launcher, launcherB, launcherC]);
      expect(find.text('Morning Movers'), findsOneWidget);
      expect(action('Join Morning Movers · 1,000 USD'), findsOneWidget);
      // The selected dot is the wide one.
      expect(tester.getSize(find.byKey(const Key('round-dot-0'))).width, 20);
      expect(tester.getSize(find.byKey(const Key('round-dot-1'))).width, 7);
    });

    testWidgets('a swipe selects the next round and everything under it', (
      tester,
    ) async {
      final chain = FakeChain()
        ..others[launcherB] = FakeChain(isMember: true, daysOf: 2);
      final server = threeRounds()
        ..meAt[launcherB] = meJson(daysOf: 2, streak: 2);
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(server: server, chain: chain, store: store);
      await pumpHome(tester, state, motion: false);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester, 14);

      expect(state.selected, launcherB);
      expect(find.text('Lumpini Striders'), findsOneWidget);
      expect(find.text('You\'re in'), findsOneWidget);
      expect(find.text('5 / 6 check-ins'), findsOneWidget);
      expect(find.text('Prize so far 2,800 USD'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RoundCard),
          matching: find.text('4 members'),
        ),
        findsOneWidget,
      );
      // The streak, the days and the one action are that round's. The days
      // are further down Home, under the prize.
      await tester.scrollUntilVisible(
        find.text('2 days in this round'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('home-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('2 days in this round'), findsOneWidget);
      expect(action('Check in · Lumpini Striders'), findsOneWidget);
      expect(action('Join Morning Movers · 1,000 USD'), findsNothing);
      expect(tester.getSize(find.byKey(const Key('round-dot-1'))).width, 20);
      // A round the person chose is remembered.
      expect(store.rounds!['selected'], launcherB);
    });

    testWidgets('a tap on a dot goes to that round', (tester) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state, motion: false);
      await tester.tap(find.byKey(const Key('round-dot-2')));
      await settle(tester, 14);
      expect(state.selected, state.rounds[2].id);
      expect(find.text(state.rounds[2].name), findsOneWidget);
    });

    testWidgets('the slider opens on the remembered round', (tester) async {
      final store = MemoryStore(
        key: testKey,
        onboarded: true,
        rounds: {'selected': launcherC, 'known': <dynamic>[]},
      );
      final state = await makeState(server: threeRounds(), store: store);
      await pumpHome(tester, state, motion: false);
      expect(state.selected, launcherC);
      expect(find.text('Night Owls'), findsOneWidget);
      expect(find.text('Morning Movers'), findsNothing);
    });
  });

  group('moving on by itself', () {
    testWidgets('every 5 seconds, round after round, then from the start', (
      tester,
    ) async {
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(server: threeRounds(), store: store);
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];
      expect(state.selected, order[0]);
      expect(slider(tester).waiting, isTrue);
      expect(AppConfig.sliderInterval, const Duration(seconds: 5));

      await tester.pump(const Duration(milliseconds: 4000));
      expect(state.selected, order[0], reason: 'not before 5 seconds');
      await wait(tester, const Duration(milliseconds: 600));
      expect(state.selected, order[1]);
      expect(find.text(state.rounds[1].name), findsOneWidget);

      await wait(tester, const Duration(seconds: 5));
      expect(state.selected, order[2]);
      await wait(tester, const Duration(seconds: 5));
      expect(state.selected, order[0], reason: 'after the last, the first');

      // A card that came by itself is not "the round the person chose".
      expect(store.rounds?['selected'], isNull);
    });

    testWidgets('it stays while touched, and after the finger lifts', (
      tester,
    ) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      final finger = await tester.startGesture(
        tester.getCenter(find.byType(RoundSlider)),
      );
      await tester.pump(const Duration(seconds: 30));
      await settle(tester);
      expect(state.selected, order[0], reason: 'held');
      expect(slider(tester).waiting, isFalse);

      // Before, the cards started again 10 seconds after the finger lifted.
      await finger.up();
      await wait(tester, const Duration(seconds: 60));
      expect(state.selected, order[0]);
      expect(slider(tester).waiting, isFalse);
    });

    testWidgets('after a swipe by hand the chosen card stays', (tester) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      // Three seconds in, the person swipes to the second card.
      await tester.pump(const Duration(seconds: 3));
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester, 14);
      expect(state.selected, order[1]);

      // The timer that was two seconds from firing does not fire, and no
      // other one does.
      await wait(tester, const Duration(seconds: 60));
      expect(state.selected, order[1]);
    });

    testWidgets('a touch anywhere on Home holds it too', (tester) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];
      await tester.pump(const Duration(seconds: 4));
      // About to press the action: the round under it must not change.
      final finger = await tester.startGesture(
        tester.getCenter(action('Join Morning Movers · 1,000 USD')) +
            const Offset(0, -60),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(state.selected, order[0]);
      await finger.up();
      await wait(tester, const Duration(seconds: 60));
      expect(state.selected, order[0]);
    });

    testWidgets('not while a sheet is open over Home', (tester) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state);
      final order = [for (final r in state.rounds) r.id];

      await tester.tap(action('Join Morning Movers · 1,000 USD'));
      await settle(tester, 14);
      expect(find.text('Pay the deposit'), findsOneWidget);
      await wait(tester, const Duration(seconds: 40));
      expect(state.selected, order[0], reason: 'the sheet is about round 1');

      // The sheet closes: the card the person pressed the action on stays.
      await tester.tapAt(const Offset(195, 20));
      await settle(tester, 14);
      expect(find.text('Pay the deposit'), findsNothing);
      await wait(tester, const Duration(seconds: 60));
      expect(state.selected, order[0]);
    });

    testWidgets('reduced motion: the cards never move by themselves', (
      tester,
    ) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state, motion: false);
      final order = [for (final r in state.rounds) r.id];

      expect(slider(tester).waiting, isFalse);
      await wait(tester, const Duration(seconds: 60));
      expect(state.selected, order[0]);
      // By hand they still move.
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester, 14);
      expect(state.selected, order[1]);
      await wait(tester, const Duration(seconds: 60));
      expect(state.selected, order[1]);
    });

    testWidgets('the slider alone: its own interval and hold', (tester) async {
      usePhone(tester);
      final rounds = [
        for (final j in [roundJson(), roundJson(at: launcherB, name: 'B')])
          Round.fromJson(j),
      ];
      var index = 0;
      final moves = <(int, bool)>[];
      var allowed = true;
      await tester.pumpWidget(
        inMotion(
          StatefulBuilder(
            builder: (context, setState) => RoundSlider(
              cards: [
                for (final r in rounds)
                  RoundCardInfo(
                    round: r,
                    totalCheckIns: r.totalCheckIns,
                    launched: false,
                    joined: false,
                  ),
              ],
              index: index,
              now: fixedNow,
              interval: const Duration(seconds: 2),
              hold: const Duration(seconds: 7),
              canAdvance: () => allowed,
              onInvite: (_) {},
              onSelect: (i, {required byPerson}) {
                moves.add((i, byPerson));
                setState(() => index = i);
              },
            ),
          ),
        ),
      );
      await wait(tester, const Duration(seconds: 2));
      expect(moves, [(1, false)]);
      // Told not to (a sheet is open, the page is scrolled away): it waits.
      allowed = false;
      await wait(tester, const Duration(seconds: 10));
      expect(moves, hasLength(1));
      // Allowed again: the card stays for the hold, then the cards move on.
      allowed = true;
      await wait(tester, const Duration(seconds: 6));
      expect(moves, hasLength(1));
      await wait(tester, const Duration(seconds: 3));
      expect(moves, [(1, false), (0, false)]);
      // A swipe is the person's, and after it the cards stay for good.
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester, 14);
      expect(moves.last, (1, true));
      await wait(tester, const Duration(seconds: 60));
      expect(moves, hasLength(3));
    });
  });

  group('stopping for good', () {
    /// The slider alone, on a page that scrolls, with motion on.
    Future<(List<(int, bool)>, List<int>)> pumpAlone(
      WidgetTester tester,
    ) async {
      usePhone(tester);
      final rounds = [
        for (final j in [roundJson(), roundJson(at: launcherB, name: 'B')])
          Round.fromJson(j),
      ];
      var index = 0;
      final moves = <(int, bool)>[];
      final stopped = <int>[];
      await tester.pumpWidget(
        inMotion(
          ListView(
            key: const Key('page'),
            children: [
              StatefulBuilder(
                builder: (context, setState) => RoundSlider(
                  cards: [
                    for (final r in rounds)
                      RoundCardInfo(
                        round: r,
                        totalCheckIns: r.totalCheckIns,
                        launched: false,
                        joined: false,
                      ),
                  ],
                  index: index,
                  now: fixedNow,
                  interval: const Duration(seconds: 2),
                  hold: const Duration(seconds: 7),
                  onInvite: (_) {},
                  onStopped: () => stopped.add(index),
                  onSelect: (i, {required byPerson}) {
                    moves.add((i, byPerson));
                    setState(() => index = i);
                  },
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      return (moves, stopped);
    }

    testWidgets('anything opened over the page, however it was opened', (
      tester,
    ) async {
      final (moves, stopped) = await pumpAlone(tester);
      await wait(tester, const Duration(seconds: 2));
      expect(moves, [(1, false)]);

      // A sheet opened by the app, with no touch anywhere.
      final context = tester.element(find.byType(RoundSlider));
      showAppSheet<void>(
        context,
        builder: (_) => const SheetFrame(tall: false, child: Text('A sheet')),
      );
      await settle(tester, 14);
      expect(find.text('A sheet'), findsOneWidget);
      expect(slider(tester).waiting, isFalse);
      expect(stopped, [1], reason: 'told once');
      Navigator.of(context).pop();
      await settle(tester, 14);

      // Closed again: the cards stay on the card that was in view.
      await wait(tester, const Duration(seconds: 60));
      expect(moves, [(1, false)]);
      expect(slider(tester).waiting, isFalse);
      expect(stopped, [1]);
    });

    testWidgets('a scroll of the page that is no touch (keys, a scroll bar)', (
      tester,
    ) async {
      final (moves, stopped) = await pumpAlone(tester);
      expect(slider(tester).waiting, isTrue);
      final page = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('page')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // What the keyboard's Page Down does: an animated scroll.
      page.position.animateTo(
        120,
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
      expect(stopped, [0]);
      expect(slider(tester).waiting, isFalse);
      await wait(tester, const Duration(seconds: 60));
      expect(moves, isEmpty);
    });

    testWidgets('a touch tells it once too', (tester) async {
      final (moves, stopped) = await pumpAlone(tester);
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester, 14);
      expect(moves, [(1, true)]);
      expect(stopped, hasLength(1));
      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await settle(tester, 14);
      await wait(tester, const Duration(seconds: 60));
      expect(stopped, hasLength(1));
      expect(moves, [(1, true), (0, true)]);
    });
  });

  group('invite', () {
    testWidgets('"Invite" on the card opens the sheet for that round', (
      tester,
    ) async {
      final state = await makeState(server: threeRounds());
      await pumpHome(tester, state, motion: false);
      await tester.tap(find.text('Invite'));
      await settle(tester, 14);
      final sheet = tester.widget<InviteSheet>(find.byType(InviteSheet));
      expect(sheet.round.id, launcher);
      expect(find.text('INVITE'), findsOneWidget);
    });

    testWidgets('the link, a copy button and a QR of the same link', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final state = await makeState(server: threeRounds());
      final round = state.rounds.firstWhere((r) => r.id == launcherB);
      final link = AppConfig.inviteLinkFor('https://run.example', launcherB);
      expect(link, 'https://run.example/#/r/$launcherB');
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: InviteSheet(state: state, round: round, link: link),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Lumpini Striders'), findsOneWidget);
      expect(find.text(link), findsOneWidget);
      expect(tester.widget<QrImageView>(find.byType(QrImageView)).size, 196);
      expect(
        find.text('Anyone with this link can open the round and join.'),
        findsOneWidget,
      );
      // Not this wallet's round: no switch to change its listing.
      expect(find.byKey(const Key('invite-unlisted')), findsNothing);

      await tester.tap(action('Copy link'));
      await settle(tester);
      expect(copied, [link]);
      expect(bannerNote.value!.text, 'Invite link copied.');
    });

    testWidgets('an unlisted round says what unlisted means, no more', (
      tester,
    ) async {
      final server = threeRounds()..unlisted.add(launcherC);
      final state = await makeState(server: server);
      await state.openLink(launcherC);
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: InviteSheet(
              state: state,
              round: state.round!,
              link: 'https://run.example/#/r/$launcherC',
            ),
          ),
        ),
      );
      await settle(tester);
      expect(
        find.text(
          'Not shown in the public list. Anyone with the link can still '
          'join, and the chain is public.',
        ),
        findsOneWidget,
      );
      for (final word in ['secret', 'private', 'hidden', 'Secret', 'Private']) {
        expect(find.textContaining(word), findsNothing);
      }
    });

    testWidgets('a build with no web address hands out the round address', (
      tester,
    ) async {
      final state = await makeState();
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: InviteSheet(state: state, round: state.round!, link: ''),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text(launcher), findsOneWidget);
      expect(action('Copy round address'), findsOneWidget);
    });

    testWidgets('the creator changes the listing from the sheet', (
      tester,
    ) async {
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Lumpini Striders'));
      server.unlisted.add(createdLauncher);
      final state = await makeState(server: server);
      await state.createRound(
        name: 'Lumpini Striders',
        deposit: usd(1000),
        liquidityBps: 3000,
        checkInGoal: 6,
        deadline: fixedNow.add(const Duration(days: 7)),
      );
      expect(server.unlisted, isEmpty);
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: InviteSheet(state: state, round: state.round!, link: ''),
          ),
        ),
      );
      await settle(tester);
      final toggle = find.byKey(const Key('invite-unlisted'));
      expect(tester.widget<CapsuleToggle>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await settle(tester);
      expect(server.unlisted, {createdLauncher});
      expect(tester.widget<CapsuleToggle>(toggle).value, isTrue);
      expect(
        server.bodies['/rounds']!['signature'],
        VerifierApi.sign(testKey, 'Cypher Run round $createdLauncher unlisted'),
      );
    });
  });

  group('the floating action', () {
    testWidgets('the scrim is opaque behind the hint and the button', (
      tester,
    ) async {
      final state = await makeState();
      await pumpHome(tester, state, motion: false);

      // Clear at its top edge, opaque from 48px down, nothing in between
      // lets text through behind the hint.
      expect(BottomFade.opacityAt(0), 0);
      expect(BottomFade.opacityAt(BottomFade.defaultRise), 1);
      expect(BottomFade.opacityAt(200), 1);
      expect(BottomFade.opacityAt(24), inExclusiveRange(0.5, 1));

      final scrim = tester.getRect(find.byKey(const Key('home-action')));
      final solidFrom = scrim.top + BottomFade.defaultRise;
      final hint = tester.getRect(
        find.text('Pay once. It comes back if the token never launches.'),
      );
      final button = tester.getRect(action('Join Morning Movers · 1,000 USD'));
      expect(hint.top, greaterThanOrEqualTo(solidFrom));
      expect(button.top, greaterThan(hint.bottom));
      expect(scrim.bottom, 844);
      expect(scrim.width, 390);
    });

    testWidgets('the last card scrolls fully above it', (tester) async {
      final state = await makeState();
      await pumpHome(tester, state, motion: false);
      final list = find.byKey(const Key('home-list'));

      await toTheEnd(tester);
      final scrim = tester.getRect(find.byKey(const Key('home-action')));
      final last = tester.getRect(find.byKey(const Key('how-it-works')));
      expect(last.bottom, lessThanOrEqualTo(scrim.top));
      // The room left under the content is the action's own height.
      final padding = tester
          .widget<ListView>(list)
          .padding!
          .resolve(TextDirection.ltr);
      expect(padding.bottom, scrim.height + 16);
    });

    testWidgets('a taller action (launch, pool short) still clears it', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, totalCheckIns: 6, pool: 900),
        server: FakeServer()..round = roundJson(totalCheckIns: 6),
      );
      // With the tab bar under the buttons, as in the app: taller than any
      // fixed padding the list used to have.
      usePhone(tester);
      await tester.pumpWidget(inApp(HomeScreen(state: state)));
      await settle(tester);
      expect(
        tester.getSize(find.byKey(const Key('home-action'))).height,
        greaterThan(260),
      );
      expect(action('Sponsor the token pool'), findsOneWidget);
      await toTheEnd(tester);
      final scrim = tester.getRect(find.byKey(const Key('home-action')));
      final last = tester.getRect(find.byKey(const Key('how-it-works')));
      expect(last.bottom, lessThanOrEqualTo(scrim.top));
    });
  });
}
