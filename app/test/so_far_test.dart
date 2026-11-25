// SO FAR: the two rows of plain counts at the bottom of Home, where they
// come from, and what is left out when it is not known.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/widgets/so_far_card.dart';

import 'support.dart';

Future<void> pumpCard(
  WidgetTester tester,
  Map<String, dynamic> json, {
  Size size = const Size(390, 844),
  bool inARound = false,
}) async {
  usePhone(tester, size: size);
  await tester.pumpWidget(
    inApp(
      ListView(
        padding: const EdgeInsets.all(20),
        children: [SoFarCard(stats: Stats.fromJson(json), inARound: inARound)],
      ),
    ),
  );
  await settle(tester);
}

/// A figure: its number and its words, written together.
Finder figure(String text) => find.text(text, findRichText: true);

void main() {
  group('the card', () {
    testWidgets('two rows: you, and everyone across every round', (
      tester,
    ) async {
      await pumpCard(tester, statsJson());

      expect(find.text('SO FAR'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(figure('4 days shown up'), findsOneWidget);
      expect(figure('2 rounds'), findsOneWidget);
      expect(figure('300 test USD claimed'), findsOneWidget);
      expect(find.text('Everyone'), findsOneWidget);
      expect(figure('7 people'), findsOneWidget);
      expect(figure('12 check-ins'), findsOneWidget);
      expect(figure('5,500 test USD deposited'), findsOneWidget);
      expect(figure('1 token launched'), findsOneWidget);
    });

    testWidgets('small numbers are shown as they are: no plus, no rounding '
        'up, no arrows', (tester) async {
      await pumpCard(
        tester,
        statsJson(
          people: 1,
          checkIns: 1,
          deposited: '999.999',
          launched: 0,
          you: {'rounds': 1, 'days': 1, 'claimed': '0.019'},
        ),
      );

      expect(figure('1 day shown up'), findsOneWidget);
      expect(figure('1 round'), findsOneWidget);
      // Rounded down to the cent.
      expect(figure('0.01 test USD claimed'), findsOneWidget);
      expect(figure('1 person'), findsOneWidget);
      expect(figure('1 check-in'), findsOneWidget);
      expect(figure('999.99 test USD deposited'), findsOneWidget);
      expect(figure('0 tokens launched'), findsOneWidget);
      expect(find.textContaining('+', findRichText: true), findsNothing);
      expect(find.textContaining('1,000', findRichText: true), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('nothing claimed: the figure is left out, not shown as zero', (
      tester,
    ) async {
      await pumpCard(
        tester,
        statsJson(you: {'rounds': 1, 'days': 3, 'claimed': '0'}),
      );
      expect(figure('3 days shown up'), findsOneWidget);
      expect(find.textContaining('claimed', findRichText: true), findsNothing);
    });

    testWidgets('a wallet that has joined nothing', (tester) async {
      await pumpCard(
        tester,
        statsJson(you: {'rounds': 0, 'days': 0, 'claimed': '0'}),
      );
      expect(find.text('No rounds joined yet.'), findsOneWidget);
      expect(find.textContaining('shown up', findRichText: true), findsNothing);
      expect(figure('7 people'), findsOneWidget);
    });

    testWidgets('the server has not caught up with a join yet: the row is '
        'left out, never "No rounds joined yet."', (tester) async {
      await pumpCard(
        tester,
        statsJson(you: {'rounds': 0, 'days': 0, 'claimed': '0'}),
        inARound: true,
      );
      expect(find.text('No rounds joined yet.'), findsNothing);
      expect(find.text('You'), findsNothing);
      expect(find.text('Everyone'), findsOneWidget);

      // Once the server counts the round, the row is back.
      await pumpCard(
        tester,
        statsJson(you: {'rounds': 1, 'days': 0, 'claimed': '0'}),
        inARound: true,
      );
      expect(find.text('You'), findsOneWidget);
      expect(figure('1 round'), findsOneWidget);
    });

    testWidgets('the wallet\'s own numbers could not be read: the row is '
        'left out', (tester) async {
      await pumpCard(tester, statsJson(you: null));
      expect(find.text('You'), findsNothing);
      expect(find.text('Everyone'), findsOneWidget);
      expect(figure('12 check-ins'), findsOneWidget);
    });

    testWidgets('320 by 568 with large text and long numbers: every figure '
        'wraps inside the card', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCard(
        tester,
        statsJson(
          people: 1234567,
          checkIns: 98765432,
          deposited: '987654321.98',
          launched: 4321,
          you: {'rounds': 123, 'days': 4567, 'claimed': '123456789.12'},
        ),
        size: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);
      for (final text in [
        '123,456,789.12 test USD claimed',
        '987,654,321.98 test USD deposited',
        '4,321 tokens launched',
      ]) {
        await tester.ensureVisible(figure(text));
        await settle(tester);
        final rect = tester.getRect(figure(text));
        expect(rect.left, greaterThanOrEqualTo(20));
        expect(rect.right, lessThanOrEqualTo(300));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a screen reader hears each row as one sentence', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester, statsJson());
      expect(
        find.bySemanticsLabel(
          'You: 4 days shown up, 2 rounds, 300 test USD claimed',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Everyone: 7 people, 12 check-ins, 5,500 test USD deposited, '
          '1 token launched',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('where the numbers come from', () {
    test('one call per read, for this wallet, in lower case', () async {
      final server = FakeServer()..stats = statsJson();
      final state = await makeState(server: server);

      expect(server.count('GET /stats/$testAddress'), 1);
      expect(state.stats!.people, 7);
      expect(state.stats!.checkIns, 12);
      expect(state.stats!.deposited, usd(5500));
      expect(state.stats!.launched, 1);
      expect(state.stats!.you!.days, 4);
      expect(state.stats!.you!.rounds, 2);
      expect(state.stats!.you!.claimed, usd(300));

      server.stats = statsJson(checkIns: 13);
      await state.refresh();
      expect(server.count('GET /stats/$testAddress'), 2);
      expect(state.stats!.checkIns, 13);
    });

    test(
      'a server that keeps no totals (404): nothing to show, no error',
      () async {
        final server = FakeServer();
        final state = await makeState(server: server);
        expect(server.count('GET /stats/$testAddress'), 1);
        expect(state.stats, isNull);
        expect(state.roundError, isNull);
        expect(await server.api.stats(testAddress), isNull);
      },
    );

    test('the server from before /rounds is not asked at all', () async {
      final server = FakeServer()
        ..legacy = true
        ..stats = statsJson();
      final state = await makeState(server: server);
      expect(state.legacyServer, isTrue);
      expect(server.requests.where((r) => r.contains('/stats')), isEmpty);
      expect(state.stats, isNull);
    });

    test('totals the server could only read in part do not replace whole '
        'ones', () async {
      final server = FakeServer()..stats = statsJson();
      final state = await makeState(server: server);
      expect(state.stats!.checkIns, 12);

      server.stats = statsJson(checkIns: 3, complete: false);
      await state.refresh();
      expect(state.stats!.checkIns, 12);

      // Nor does a failed read.
      server.offline = true;
      await state.refresh();
      expect(state.stats!.checkIns, 12);
    });

    test(
      'totals read in part are not shown when there is nothing whole',
      () async {
        final server = FakeServer()..stats = statsJson(complete: false);
        final state = await makeState(server: server);
        expect(state.stats, isNull);
      },
    );

    test('the totals are read after the round, so a join is already '
        'seen', () async {
      final server = FakeServer()..stats = statsJson();
      final state = await makeState(server: server);
      await state.getTestDollars(state.deposit);
      server.requests.clear();
      await state.payDeposit();
      final asked = server.requests;
      final stats = asked.lastIndexOf('GET /stats/$testAddress');
      final me = asked.lastIndexOf('GET /rounds/$launcher/me/$testAddress');
      expect(me, greaterThan(-1));
      expect(stats, greaterThan(me));

      // While the round's own read is still waiting, the totals are not
      // asked for at all.
      final gate = Completer<void>();
      server.membersGate = gate.future;
      final before = server.count('GET /stats/$testAddress');
      final run = state.refresh();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(server.count('GET /rounds/$launcher/members'), greaterThan(0));
      expect(server.count('GET /stats/$testAddress'), before);
      gate.complete();
      await run;
      expect(server.count('GET /stats/$testAddress'), before + 1);
    });

    test('another wallet starts with no numbers of the one before', () async {
      final server = FakeServer()..stats = statsJson();
      final state = await makeState(server: server);
      expect(state.stats!.you!.days, 4);

      server.stats = null;
      await state.importKey('${'11' * 31}22');
      expect(state.stats, isNull);
    });
  });

  group('on Home', () {
    Future<void> pumpHome(WidgetTester tester, FakeServer server) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 3),
        server: server,
      );
      usePhone(tester);
      await tester.pumpWidget(inApp(HomeScreen(state: state, showBar: false)));
      await settle(tester);
    }

    testWidgets('SO FAR is the last thing on Home, below THE PRIZE and the '
        'rules', (tester) async {
      await pumpHome(tester, FakeServer()..stats = statsJson());
      final list = find.byType(Scrollable).first;

      await tester.scrollUntilVisible(
        find.text('THE PRIZE'),
        200,
        scrollable: list,
      );
      expect(find.byKey(const Key('so-far')), findsNothing);
      final pot = tester.getRect(find.text('THE PRIZE'));
      final rules = find.byKey(const Key('how-it-works'));
      if (rules.evaluate().isNotEmpty) {
        expect(tester.getRect(rules).top, greaterThan(pot.bottom));
      }

      await tester.scrollUntilVisible(
        find.byKey(const Key('so-far')),
        300,
        scrollable: list,
      );
      // To the very end of the list.
      await tester.drag(list, const Offset(0, -3000));
      await settle(tester);
      final card = tester.getRect(find.byKey(const Key('so-far')));
      expect(card.top, greaterThan(tester.getRect(rules).bottom));
      expect(find.text('THE PRIZE'), findsNothing);
      // Nothing of it is under the floating action.
      final action = tester.getRect(find.byKey(const Key('home-action')));
      expect(card.bottom, lessThanOrEqualTo(action.top + 48));
      expect(figure('12 check-ins'), findsOneWidget);
    });

    testWidgets('a member whose round the totals do not count yet: no "No '
        'rounds joined yet." on Home', (tester) async {
      await pumpHome(
        tester,
        FakeServer()
          ..stats = statsJson(you: {'rounds': 0, 'days': 0, 'claimed': '0'}),
      );
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('so-far')),
        300,
        scrollable: list,
      );
      final card = find.byKey(const Key('so-far'));
      expect(
        find.descendant(of: card, matching: find.text('No rounds joined yet.')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('You')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Everyone')),
        findsOneWidget,
      );
    });

    testWidgets('with no totals from the server there is no card', (
      tester,
    ) async {
      await pumpHome(tester, FakeServer());
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -5000));
      await settle(tester);
      expect(find.byKey(const Key('how-it-works')), findsOneWidget);
      expect(find.byKey(const Key('so-far')), findsNothing);
      expect(find.text('SO FAR'), findsNothing);
    });

    testWidgets('small phone, large text: Home with THE PRIZE and SO FAR '
        'lays out to its end', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 3),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 3, prizeNow: '1234567.89')
          ..stats = statsJson(deposited: '987654321.98'),
      );
      usePhone(tester, size: const Size(320, 568));
      await tester.pumpWidget(inApp(HomeScreen(state: state, showBar: false)));
      await settle(tester);
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, -400));
        await settle(tester, 2);
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('so-far')), findsOneWidget);
    });
  });
}
