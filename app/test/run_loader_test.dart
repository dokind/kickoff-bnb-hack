import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/widgets/common.dart';

import 'support.dart';

void main() {
  group('RunLoader', () {
    testWidgets('runs at both sizes', (tester) async {
      await tester.pumpWidget(
        inMotion(
          const Column(
            children: [
              RunLoader(key: Key('big')),
              RunLoader.small(key: Key('small')),
            ],
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('big'))), const Size(84, 56));
      expect(
        tester.getSize(find.byKey(const Key('small'))),
        const Size(27, 18),
      );
      final big = tester.state<RunLoaderState>(find.byKey(const Key('big')));
      expect(big.running, isTrue);
      // A whole loop and a bit: still running, nothing thrown.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(big.running, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows its label and says it is loading', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        inApp(const Center(child: RunLoader(label: 'Reading the round…'))),
      );
      expect(find.text('Reading the round…'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(RunLoader)),
        matchesSemantics(
          label: 'Loading. Reading the round…',
          isLiveRegion: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('stands still with reduced motion', (tester) async {
      await tester.pumpWidget(inApp(const Center(child: RunLoader())));
      final state = tester.state<RunLoaderState>(find.byType(RunLoader));
      expect(state.running, isFalse);
      expect(tester.hasRunningAnimations, isFalse);
      // Nothing is left to settle.
      await tester.pumpAndSettle();
    });
  });

  group('RunProgress', () {
    testWidgets('shows the step count and the step running now', (
      tester,
    ) async {
      Widget at(int current) => inApp(
        Padding(
          padding: const EdgeInsets.all(20),
          child: RunProgress(
            steps: const ['Get test USD', 'Approve test USD', 'Join the round'],
            current: current,
          ),
        ),
      );
      await tester.pumpWidget(at(1));
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Approve test USD'), findsOneWidget);
      expect(find.text('Join the round'), findsNothing);

      await tester.pumpWidget(at(2));
      await tester.pump();
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Join the round'), findsOneWidget);
      expect(
        tester.state<RunProgressState>(find.byType(RunProgress)).running,
        isFalse,
      );
      expect(RunProgress.countLabel(9, 3), 'Step 3 of 3');
    });

    testWidgets('moves on with motion on', (tester) async {
      Widget at(int current) =>
          inMotion(RunProgress(steps: const ['One', 'Two'], current: current));
      await tester.pumpWidget(at(0));
      expect(
        tester.state<RunProgressState>(find.byType(RunProgress)).running,
        isTrue,
      );
      await tester.pumpWidget(at(1));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('busy states', () {
    testWidgets('a busy pill shows the running mark', (tester) async {
      Widget pill({required bool busy}) => inApp(
        Center(
          child: PillButton(
            label: 'Join',
            busy: busy,
            busyLabel: 'Joining…',
            onPressed: () {},
          ),
        ),
      );
      await tester.pumpWidget(pill(busy: false));
      expect(find.byType(RunLoader), findsNothing);
      await tester.pumpWidget(pill(busy: true));
      expect(find.byType(RunLoader), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Joining…'), findsOneWidget);
    });

    testWidgets('try again runs until the retry is done', (tester) async {
      final retry = Completer<void>();
      var tries = 0;
      await tester.pumpWidget(
        inApp(
          ErrorRetry(
            text: 'The round could not be read.',
            onRetry: () {
              tries++;
              return retry.future;
            },
          ),
        ),
      );
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(tries, 1);
      expect(find.text('Trying again…'), findsOneWidget);
      expect(find.byType(RunLoader), findsOneWidget);
      // It cannot be pressed twice.
      await tester.tap(find.text('Trying again…'));
      expect(tries, 1);

      retry.complete();
      await tester.pump();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(RunLoader), findsNothing);
    });

    testWidgets('loading card and line show the mark and their words', (
      tester,
    ) async {
      await tester.pumpWidget(
        inApp(
          const Column(
            children: [
              LoadingCard(label: 'Reading the round…'),
              LoadingLine('Reading your check-ins…'),
            ],
          ),
        ),
      );
      expect(find.byType(RunLoader), findsNWidgets(2));
      expect(find.text('Reading the round…'), findsOneWidget);
      expect(find.text('Reading your check-ins…'), findsOneWidget);
    });
  });
}
