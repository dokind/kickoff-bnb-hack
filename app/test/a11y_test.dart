// Accessibility on the screens and sheets of the join, check-in, wallet,
// new-round and onboarding flows, and on the round cards: no text under 12
// logical pixels, and every chip that can be pressed is a full touch target
// (at least 44 high).
//
// Two exceptions are left, both in shared widgets these screens use and do
// not size: the tracked overline style ("THE DEAL", "ROUND"), which
// lib/theme/theme.dart sets at 11, and the "On" / "Off" inside the
// CapsuleToggle switch (lib/widgets/controls.dart), also 11.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/screens/account_screen.dart';
import 'package:pacepact/screens/checkin_sheet.dart';
import 'package:pacepact/screens/join_sheet.dart';
import 'package:pacepact/screens/new_round_screen.dart';
import 'package:pacepact/screens/onboarding_screen.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/theme/tokens.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/round_slider.dart';

import 'support.dart';

/// Every run of text on the screen drawn under 12 logical pixels, outside
/// the shared overline and switch and outside icons (an icon is a glyph,
/// not text).
List<String> smallText(WidgetTester tester) {
  final hits = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<Overline>() != null) continue;
    if (e.findAncestorWidgetOfExactType<CapsuleToggle>() != null) continue;
    if (e.findAncestorWidgetOfExactType<Icon>() != null) continue;
    final paragraph = e.renderObject! as RenderParagraph;
    void visit(InlineSpan span, double? inherited) {
      final size = span.style?.fontSize ?? inherited;
      if (span is! TextSpan) return;
      final text = span.text ?? '';
      if (text.trim().isNotEmpty && size != null && size < 12) {
        hits.add('"$text" at $size');
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, size);
      }
    }

    visit(paragraph.text, null);
  }
  return hits;
}

/// Scrolls every list on the screen to its end and back, checking the text
/// on the way, so lazily built rows are checked too.
Future<List<String>> smallTextAnywhere(WidgetTester tester) async {
  final hits = <String>{...smallText(tester)};
  final lists = find.byType(Scrollable);
  for (var i = 0; i < lists.evaluate().length; i++) {
    final state = tester.state<ScrollableState>(lists.at(i));
    final position = state.position;
    if (position.axis != Axis.vertical || position.maxScrollExtent <= 0) {
      continue;
    }
    for (var at = 0.0; at <= position.maxScrollExtent; at += 200) {
      position.jumpTo(at);
      await tester.pump();
      hits.addAll(smallText(tester));
    }
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    hits.addAll(smallText(tester));
    position.jumpTo(0);
    await tester.pump();
  }
  return hits.toList();
}

Future<void> pumpBody(WidgetTester tester, Widget body) async {
  usePhone(tester);
  await tester.pumpWidget(inApp(body));
  await settle(tester);
}

void main() {
  tearDown(() => bannerNote.value = null);

  group('no text under 12', () {
    testWidgets('the join sheet, with its warning and its three lines', (
      tester,
    ) async {
      final state = await makeState(
        server: FakeServer()..round = roundJson(totalCheckIns: 5),
        chain: FakeChain(dollars: 2500),
      );
      await pumpBody(tester, JoinSheet(state: state, round: state.round!));
      expect(find.byKey(const Key('join-late')), findsOneWidget);
      expect(find.byKey(const Key('join-outcomes')), findsOneWidget);
      expect(await smallTextAnywhere(tester), isEmpty);
    });

    testWidgets('the check-in sheet, in a browser and on a phone', (
      tester,
    ) async {
      final web = await makeState(chain: FakeChain(isMember: true));
      await pumpBody(tester, CheckInSheet(state: web, round: web.round!));
      expect(find.byKey(const Key('checkin-attested')), findsOneWidget);
      expect(await smallTextAnywhere(tester), isEmpty);

      final phone = await makeState(
        chain: FakeChain(isMember: true),
        health: FakeHealth(available: true, steps: 300),
      );
      await tester.pumpWidget(const SizedBox());
      await pumpBody(tester, CheckInSheet(state: phone, round: phone.round!));
      // The scale under the steps: "0" and "1,000 steps to check in".
      expect(find.text('1,000 steps to check in'), findsOneWidget);
      expect(await smallTextAnywhere(tester), isEmpty);
    });

    testWidgets('Wallet, with money in a round', (tester) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, dollars: 250),
      );
      await pumpBody(tester, AccountScreen(state: state, showBar: false));
      expect(find.byKey(const Key('wallet-in-rounds')), findsOneWidget);
      expect(await smallTextAnywhere(tester), isEmpty);
    });

    testWidgets('New round, "More options" open', (tester) async {
      final state = await makeState();
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));
      final more = find.text('More options');
      await tester.ensureVisible(more);
      await tester.pump();
      await tester.tap(more);
      await settle(tester);
      expect(find.byKey(const Key('round-goal-hint')), findsOneWidget);
      expect(await smallTextAnywhere(tester), isEmpty);
    });

    testWidgets('onboarding: the welcome, and the phone\'s health step', (
      tester,
    ) async {
      final state = await makeState(
        wallet: false,
        store: MemoryStore(),
        health: FakeHealth(available: true),
      );
      await pumpBody(tester, OnboardingScreen(state: state));
      expect(await smallTextAnywhere(tester), isEmpty);
      final start = find.byWidgetPredicate(
        (w) => w is PillButton && w.label == 'Get started',
      );
      await tester.ensureVisible(start);
      await tester.pump();
      await tester.tap(start);
      await settle(tester, 12);
      expect(find.text('CONNECT\nHEALTH CONNECT'), findsOneWidget);
      expect(await smallTextAnywhere(tester), isEmpty);
    });

    testWidgets('a round card', (tester) async {
      await pumpBody(
        tester,
        RoundCard(
          info: RoundCardInfo(
            round: Round.fromJson(roundJson()),
            totalCheckIns: 2,
            launched: false,
            joined: true,
          ),
          now: fixedNow,
          onInvite: () {},
        ),
      );
      expect(smallText(tester), isEmpty);
    });
  });

  group('chips you can press are 44 high', () {
    testWidgets('"Invite" on a round card', (tester) async {
      usePhone(tester);
      var invited = 0;
      final rounds = [
        for (final j in [roundJson(), roundJson(at: launcherB, name: 'B')])
          Round.fromJson(j),
      ];
      await tester.pumpWidget(
        inApp(
          ListView(
            children: [
              RoundSlider(
                cards: [
                  for (final r in rounds)
                    RoundCardInfo(
                      round: r,
                      totalCheckIns: r.totalCheckIns,
                      launched: false,
                      joined: true,
                    ),
                ],
                index: 0,
                now: fixedNow,
                onSelect: (_, {required byPerson}) {},
                onInvite: (_) => invited++,
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      final target = find.byKey(const Key('round-invite')).first;
      expect(tester.getSize(target).height, greaterThanOrEqualTo(Sizes.touch));
      expect(tester.getSize(target).width, greaterThanOrEqualTo(Sizes.touch));
      // The chip it draws is still the small one.
      expect(
        tester
            .getSize(
              find.descendant(of: target, matching: find.byType(AppChip)),
            )
            .height,
        32,
      );
      // A press at the very top of the target, above the chip, counts.
      final box = tester.getRect(target);
      await tester.tapAt(Offset(box.center.dx, box.top + 2));
      await tester.pump();
      expect(invited, 1);
      // The card still holds everything at its height: nothing is pushed
      // out at the bottom.
      final inner = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(RoundCard).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(inner.position.maxScrollExtent, 0);
    });

    testWidgets('every choice on New round', (tester) async {
      final state = await makeState();
      await pumpBody(tester, NewRoundScreen(state: state, missing: const []));
      final more = find.text('More options');
      await tester.ensureVisible(more);
      await tester.pump();
      await tester.tap(more);
      await settle(tester);
      final chips = find.byType(AppChip);
      expect(chips, findsWidgets);
      for (final chip in chips.evaluate()) {
        expect(chip.size!.height, greaterThanOrEqualTo(Sizes.touch));
        expect(chip.size!.width, greaterThanOrEqualTo(Sizes.touch));
      }
    });
  });
}
