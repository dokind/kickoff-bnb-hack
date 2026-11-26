// The Health sheet, the check-in sheet over each result of a read of the
// health store, the Wallet's health row, and the typed fallback.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/screens/account_screen.dart';
import 'package:pacepact/screens/checkin_sheet.dart';
import 'package:pacepact/screens/health_sheet.dart';
import 'package:pacepact/services/health_service.dart';
import 'package:pacepact/widgets/common.dart';

import 'support.dart';

/// A health store that answers [next] to every read, and counts what was
/// asked of it.
class StatusHealth extends FakeHealth implements HealthAccess {
  StatusHealth(this.next, {super.available = true, this.askedFlag = true})
    : super(steps: next.steps);

  StepsRead next;
  bool askedFlag;
  bool opensFine = true;
  int reads = 0;
  int connects = 0;
  int opens = 0;
  int installs = 0;

  /// The `ask` of every read, in order.
  final List<bool> asks = [];

  @override
  Future<bool> askedBefore() async => askedFlag;

  @override
  Future<StepsRead> readSteps({bool ask = true}) async {
    reads++;
    asks.add(ask);
    return next;
  }

  @override
  Future<int> stepsToday() async => next.isOk ? next.steps : 0;

  @override
  Future<bool> connect() async {
    connects++;
    askedFlag = true;
    return true;
  }

  @override
  Future<bool> openSettings() async {
    opens++;
    return opensFine;
  }

  @override
  Future<void> installHealthConnect() async => installs++;
}

Finder button(String label) =>
    find.byWidgetPredicate((w) => w is PillButton && w.label == label);

bool enabled(WidgetTester tester, String label) =>
    tester.widget<PillButton>(button(label)).onPressed != null;

Future<void> pumpBody(WidgetTester tester, Widget body) async {
  usePhone(tester);
  await tester.pumpWidget(inApp(body));
  await settle(tester);
}

Future<void> press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settle(tester);
}

final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

/// Nothing on screen claims that access was refused.
void expectNoBlame() {
  for (final word in ['denied', 'Denied', 'refused', 'blocked']) {
    expect(find.textContaining(word), findsNothing);
  }
}

void main() {
  group('health service', () {
    test('a service with only the old API still has the status API', () async {
      final none = FakeHealth();
      expect(await none.readSteps(), StepsRead.unavailable);
      expect(none.store, HealthStore.none);

      final some = FakeHealth(available: true, steps: 5000);
      expect(await some.readSteps(), const StepsRead.ok(5000));
      some.steps = 0;
      expect(await some.readSteps(), StepsRead.noData);
      expect(await some.askedBefore(), isFalse);
      expect(await some.connect(), isTrue);
      expect(some.asked, 1);
    });

    test('a service with the status API is asked through it', () async {
      final h = StatusHealth(StepsRead.notInstalled);
      final HealthService asService = h;
      expect(await asService.readSteps(), StepsRead.notInstalled);
      expect(h.reads, 1);
      await asService.installHealthConnect();
      expect(h.installs, 1);
    });

    testWidgets('named for the platform', (tester) async {
      expect(FakeHealth(available: true).storeName, 'Health Connect');
    });

    testWidgets('named Apple Health on an iPhone', (tester) async {
      expect(FakeHealth(available: true).storeName, 'Apple Health');
    }, variant: iOS);
  });

  group('Health sheet', () {
    testWidgets('says what is read and what is not', (tester) async {
      await pumpBody(
        tester,
        HealthSheet(health: StatusHealth(const StepsRead.ok(6214))),
      );
      expect(find.text('Health Connect'), findsOneWidget);
      expect(find.text('Today\'s step count'), findsOneWidget);
      expect(find.text('Nothing else'), findsOneWidget);
      expect(find.text('Nothing written'), findsOneWidget);
    });

    testWidgets('ok: connected, today\'s steps, "Sync again" reads again', (
      tester,
    ) async {
      final h = StatusHealth(const StepsRead.ok(6214));
      await pumpBody(tester, HealthSheet(health: h));
      expect(h.reads, 1, reason: 'asked before: read on open');
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('6,214 steps today.'), findsOneWidget);
      h.next = const StepsRead.ok(7000);
      await press(tester, button('Sync again'));
      expect(h.reads, 2);
      expect(find.text('7,000 steps today.'), findsOneWidget);
    });

    testWidgets('first time: "Connect" asks, then reads', (tester) async {
      final h = StatusHealth(const StepsRead.ok(3000), askedFlag: false);
      await pumpBody(tester, HealthSheet(health: h));
      expect(h.reads, 0, reason: 'nothing is asked before the press');
      expect(find.text('Not connected yet'), findsOneWidget);
      expect(button('Open Health Connect'), findsNothing);
      await press(tester, button('Connect Health Connect'));
      expect(h.connects, 1);
      expect(h.reads, 1);
      expect(find.text('3,000 steps today.'), findsOneWidget);
      expect(button('Sync again'), findsOneWidget);
    });

    testWidgets(
      'noData on an iPhone: never "denied", and the way to the switch',
      (tester) async {
        final h = StatusHealth(StepsRead.noData);
        await pumpBody(tester, HealthSheet(health: h));
        expect(find.text('Apple Health'), findsOneWidget);
        expect(
          find.text(
            'No steps came from Apple Health. If you turned access off, '
            'turn it on in the Health app.',
          ),
          findsOneWidget,
        );
        expectNoBlame();
        expect(find.text('Tap your profile, top right.'), findsOneWidget);
        expect(find.text('Apps, then Cypher Run.'), findsOneWidget);
        expect(find.text('Turn on Steps.'), findsOneWidget);
        await press(tester, button('Open the Health app'));
        expect(h.opens, 1);
      },
      variant: iOS,
    );

    testWidgets('the Health app does not open: one sentence, the steps stay', (
      tester,
    ) async {
      final h = StatusHealth(StepsRead.noData)..opensFine = false;
      await pumpBody(tester, HealthSheet(health: h));
      await press(tester, button('Open the Health app'));
      expect(find.textContaining('did not open'), findsOneWidget);
      expect(find.byKey(const Key('health-path')), findsOneWidget);
    }, variant: iOS);

    testWidgets('noData on Android: "Open Health Connect" asks again', (
      tester,
    ) async {
      final h = StatusHealth(StepsRead.noData);
      await pumpBody(tester, HealthSheet(health: h));
      expect(find.textContaining('allow Steps in Health Connect'), findsOne);
      await press(tester, button('Open Health Connect'));
      expect(h.opens, 1);
      expect(h.reads, 2, reason: 'read again once Health Connect answers');
    });

    testWidgets('notInstalled: "Install Health Connect"', (tester) async {
      final h = StatusHealth(StepsRead.notInstalled);
      await pumpBody(tester, HealthSheet(health: h));
      expect(find.text('Health Connect is not on this phone'), findsOneWidget);
      expect(button('Open Health Connect'), findsNothing);
      await press(tester, button('Install Health Connect'));
      expect(h.installs, 1);
      expect(button('Sync again'), findsOneWidget);
    });

    testWidgets('error: one plain sentence and "Sync again"', (tester) async {
      final h = StatusHealth(const StepsRead.error('boom'));
      await pumpBody(tester, HealthSheet(health: h));
      expect(find.text('Health Connect did not answer'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      await press(tester, button('Sync again'));
      expect(h.reads, 2);
    });

    testWidgets('not available: says so, and offers nothing to press', (
      tester,
    ) async {
      final h = StatusHealth(StepsRead.unavailable, available: false);
      await pumpBody(
        tester,
        HealthSheet(health: h, initial: StepsRead.unavailable),
      );
      expect(find.text('No health data here'), findsOneWidget);
      expect(find.byType(PillButton), findsNothing);
    });

    testWidgets('every action is at least 44 high and has a label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = StatusHealth(StepsRead.noData);
      await pumpBody(tester, HealthSheet(health: h));
      for (final label in ['Sync again', 'Open Health Connect']) {
        expect(tester.getSize(button(label)).height, greaterThanOrEqualTo(44));
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      semantics.dispose();
    });

    testWidgets('opening it never asks; only a press does', (tester) async {
      final h = StatusHealth(StepsRead.noData);
      await pumpBody(tester, HealthSheet(health: h));
      expect(h.asks, [false], reason: 'the read on open does not ask');
      await press(tester, button('Sync again'));
      expect(h.asks, [false, true]);
    });

    testWidgets('"Connect" asks once, then reads without asking again', (
      tester,
    ) async {
      final h = StatusHealth(StepsRead.noData, askedFlag: false);
      await pumpBody(tester, HealthSheet(health: h));
      await press(tester, button('Connect Health Connect'));
      expect(h.connects, 1);
      expect(h.asks, [false]);
    });

    testWidgets('"Open Health Connect" does not ask a second time', (
      tester,
    ) async {
      final h = StatusHealth(StepsRead.noData);
      await pumpBody(tester, HealthSheet(health: h));
      await press(tester, button('Open Health Connect'));
      expect(h.opens, 1);
      expect(h.asks, [false, false]);
    });
  });

  group('check-in sheet over each read', () {
    Future<StatusHealth> open(WidgetTester tester, StepsRead read) async {
      final h = StatusHealth(read);
      final state = await makeState(
        chain: FakeChain(isMember: true),
        health: h,
      );
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));
      return h;
    }

    testWidgets('ok: the number and the check-in button', (tester) async {
      await open(tester, const StepsRead.ok(6214));
      expect(find.text('6,214'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(enabled(tester, 'Check in'), isTrue);
      expect(find.byKey(const Key('checkin-no-steps')), findsNothing);
    });

    testWidgets('noData on an iPhone: no blame, "Sync again" reads again', (
      tester,
    ) async {
      final h = await open(tester, StepsRead.noData);
      expect(find.text('No steps from Apple Health today.'), findsOneWidget);
      expect(
        find.text(
          'No steps came from Apple Health. If you turned access off, '
          'turn it on in the Health app.',
        ),
        findsOneWidget,
      );
      expectNoBlame();
      expect(enabled(tester, 'Check in'), isFalse);
      expect(h.reads, 1);
      h.next = const StepsRead.ok(2500);
      await press(tester, button('Sync again'));
      expect(h.reads, 2);
      expect(find.text('2,500'), findsOneWidget);
      expect(enabled(tester, 'Check in'), isTrue);
    }, variant: iOS);

    testWidgets('"Fix in Health" opens the Health sheet; its read comes back', (
      tester,
    ) async {
      final h = await open(tester, StepsRead.noData);
      await press(tester, button('Fix in Health'));
      expect(find.byType(HealthSheet), findsOneWidget);
      h.next = const StepsRead.ok(4000);
      await press(tester, button('Sync again').last);
      Navigator.of(tester.element(find.byType(HealthSheet))).pop();
      await settle(tester);
      expect(find.byType(HealthSheet), findsNothing);
      expect(find.text('4,000'), findsOneWidget);
      expect(enabled(tester, 'Check in'), isTrue);
    }, variant: iOS);

    testWidgets('notInstalled: says so, and the way on', (tester) async {
      await open(tester, StepsRead.notInstalled);
      expect(find.text('Health Connect is not on this phone.'), findsOneWidget);
      expect(button('Fix in Health Connect'), findsOneWidget);
      expect(find.text('Type today\'s steps instead'), findsOneWidget);
    });

    testWidgets('error: no dead end either', (tester) async {
      await open(tester, const StepsRead.error('timeout'));
      expect(find.text('No steps from Health Connect today.'), findsOneWidget);
      expect(find.textContaining('did not answer'), findsOneWidget);
      expect(find.textContaining('timeout'), findsNothing);
      expect(button('Sync again'), findsOneWidget);
    });

    testWidgets('not available: the typed field, as in a browser', (
      tester,
    ) async {
      final h = StatusHealth(StepsRead.unavailable, available: false);
      final state = await makeState(
        chain: FakeChain(isMember: true),
        health: h,
      );
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));
      expect(find.byKey(const Key('steps')), findsOneWidget);
      expect(h.reads, 0);
    });

    testWidgets('typed instead: sent as "self", and back to Health', (
      tester,
    ) async {
      final server = FakeServer();
      final h = StatusHealth(StepsRead.noData);
      final state = await makeState(
        chain: FakeChain(isMember: true),
        server: server,
        health: h,
      );
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));
      await press(tester, find.text('Type today\'s steps instead'));
      expect(find.text('Self-reported, testnet only'), findsOneWidget);
      expect(find.text('Read Health Connect instead'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('steps')), '5100');
      await press(tester, button('Check in'));
      final body = server.bodies['/rounds/$launcher/checkin']!;
      expect(body['steps'], 5100);
      expect(body['source'], 'self');
      expect(find.text('CHECKED IN.'), findsOneWidget);
    });

    testWidgets('"Read Health Connect instead" leaves the typed field', (
      tester,
    ) async {
      final h = await open(tester, StepsRead.noData);
      await press(tester, find.text('Type today\'s steps instead'));
      h.next = const StepsRead.ok(1800);
      await press(tester, find.text('Read Health Connect instead'));
      expect(find.byKey(const Key('steps')), findsNothing);
      expect(find.text('1,800'), findsOneWidget);
    });

    testWidgets('the actions are at least 44 high, with labels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(tester, StepsRead.noData);
      for (final label in ['Sync again', 'Fix in Health Connect']) {
        expect(tester.getSize(button(label)).height, greaterThanOrEqualTo(44));
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      final typed = find.widgetWithText(
        TextButton,
        'Type today\'s steps instead',
      );
      expect(tester.getSize(typed).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Type today\'s steps instead'), findsOne);
      semantics.dispose();
    });

    Future<void> comeBack(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
    }

    testWidgets('opening asks only if the app never asked before', (
      tester,
    ) async {
      final h = StatusHealth(StepsRead.noData, askedFlag: false);
      final state = await makeState(
        chain: FakeChain(isMember: true),
        health: h,
      );
      await pumpBody(tester, CheckInSheet(state: state, round: state.round!));
      expect(h.asks, [true], reason: 'first time: the system sheet');
    });

    testWidgets('asked before: opening reads without asking', (tester) async {
      final h = await open(tester, StepsRead.noData);
      expect(h.asks, [false]);
      await press(tester, button('Sync again'));
      expect(h.asks, [false, true], reason: 'a press may ask');
    });

    testWidgets('coming back to the app reads again without asking', (
      tester,
    ) async {
      final h = await open(tester, StepsRead.noData);
      await comeBack(tester);
      expect(h.asks, [false, false]);
    });

    testWidgets('while the Health sheet is open, only it reads on return', (
      tester,
    ) async {
      final h = await open(tester, StepsRead.noData);
      await press(tester, button('Fix in Health Connect'));
      expect(find.byType(HealthSheet), findsOneWidget);
      final before = h.reads;
      await comeBack(tester);
      expect(h.reads, before, reason: 'nothing was opened from the sheet');
      Navigator.of(tester.element(find.byType(HealthSheet))).pop();
      await settle(tester);
      await comeBack(tester);
      expect(h.reads, before + 1);
      expect(h.asks.last, isFalse);
    });
  });

  group('Wallet health row', () {
    testWidgets('on a phone: a row that opens the Health sheet', (
      tester,
    ) async {
      final h = StatusHealth(const StepsRead.ok(6214));
      final state = await makeState(health: h);
      await pumpBody(tester, AccountScreen(state: state, showBar: false));
      final row = find.byKey(const Key('wallet-health'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Health Connect')),
        findsOneWidget,
      );
      await press(tester, row);
      expect(find.byType(HealthSheet), findsOneWidget);
      expect(find.text('6,214 steps today.'), findsOneWidget);
    });

    testWidgets('named Apple Health on an iPhone', (tester) async {
      final state = await makeState(
        health: StatusHealth(const StepsRead.ok(1)),
      );
      await pumpBody(tester, AccountScreen(state: state, showBar: false));
      expect(
        find.descendant(
          of: find.byKey(const Key('wallet-health')),
          matching: find.text('Apple Health'),
        ),
        findsOneWidget,
      );
    }, variant: iOS);

    testWidgets('in a browser: no row', (tester) async {
      final state = await makeState(health: FakeHealth());
      await pumpBody(tester, AccountScreen(state: state, showBar: false));
      expect(find.byKey(const Key('wallet-health')), findsNothing);
      expect(find.byKey(const Key('wallet-about')), findsOneWidget);
    });
  });
}
