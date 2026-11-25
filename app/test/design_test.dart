// The look: dot-matrix numerals, tick gauges, the aurora, the pills, and the
// words the copy must not use.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/theme/theme.dart';
import 'package:pacepact/theme/tokens.dart';
import 'package:pacepact/util/format.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/dot_matrix.dart';
import 'package:pacepact/widgets/gauges.dart';
import 'package:pacepact/widgets/identicon.dart';
import 'package:pacepact/widgets/tab_bar.dart';

import 'support.dart';

void main() {
  group('formats', () {
    test('amounts carry separators, two decimals at most, and a unit', () {
      expect(formatAmount(usd(1000)), '1,000');
      expect(formatAmount(usd(1068.5949)), '1,068.59');
      expect(formatAmount(usd(356.2)), '356.2');
      expect(formatAmount(usd(1234567), maxFraction: 0), '1,234,567');
      expect(formatMoney(usd(1000), 'USD'), '1,000 USD');
      expect(formatMoney(usd(0.03), 'tBNB', maxFraction: 4), '0.03 tBNB');
      expect(formatMoney(BigInt.zero, 'USD'), '0 USD');
      expect(formatCount(6214), '6,214');
    });

    test('shares, days and waits read as words', () {
      expect(formatBps(3000), '30%');
      expect(formatBps(10000), '100%');
      expect(formatBps(3333), '33.33%');
      expect(formatBps(250), '2.5%');
      expect(days(1), '1 day');
      expect(days(7), '7 days');
      expect(formatWait(const Duration(hours: 9)), '9 h');
      expect(formatWait(const Duration(hours: 5, minutes: 12)), '5 h 12 min');
      expect(formatWait(const Duration(minutes: 12)), '12 min');
      expect(formatWait(const Duration(seconds: 20)), 'under a minute');
      expect(formatDate(DateTime.utc(2026, 12, 2)), '2 Dec 2026');
    });

    test('days are counted in UTC, like the contract', () {
      expect(dayIndexOf(fixedNow), 20782);
      expect(utcDayKey(fixedNow), '2026-11-25');
      // 06:30 in Bangkok on the 26th is still the 25th in UTC.
      final bangkokMorning = DateTime.utc(2026, 11, 25, 23, 30);
      expect(utcDayKey(bangkokMorning), '2026-11-25');
      expect(dayIndexOf(bangkokMorning), 20782);
      expect(nextUtcDay(fixedNow), DateTime.utc(2026, 11, 26));
    });

    test('parseUnits and wholeUnits agree', () {
      expect(parseUnits('1000'), wholeUnits(1000));
      expect(parseUnits('1,000'), wholeUnits(1000));
      expect(parseUnits('0'), isNull);
      expect(parseUnits('-5'), isNull);
      expect(parseUnits('abc'), isNull);
    });

    test('errors shown to a person never carry a host or a raw exception', () {
      const generic =
          'Something went wrong. Check your connection and try again.';
      expect(
        friendlyError(Exception('Give the round a name first.')),
        'Give the round a name first.',
      );
      expect(friendlyError(StateError('bad state')), generic);
      expect(
        friendlyError(Exception('GET http://localhost:8787/round failed')),
        generic,
      );
      expect(
        friendlyError(Exception('SocketException: connection refused')),
        generic,
      );
      expect(friendlyError(const FormatException('x')), generic);
      expect(
        friendlyError(
          Exception(
            'RPCError: got code -32000 with msg '
            '"insufficient funds for gas * price + value"',
          ),
        ),
        contains('no test BNB for network fees'),
      );
    });
  });

  group('dot-matrix numerals', () {
    test('every character of an amount has a glyph seven dots tall', () {
      for (final ch in '0123456789.,:-+/% '.split('')) {
        final glyph = DotFont.glyph(ch);
        expect(glyph.bits.length, DotFont.rows, reason: ch);
        for (final row in glyph.bits) {
          expect(row < (1 << glyph.width), isTrue, reason: 'row fits: $ch');
        }
      }
      // Digits are five dots wide and all different.
      final digits = {
        for (final d in '0123456789'.split('')) DotFont.glyph(d).bits.join(','),
      };
      expect(digits.length, 10);
      expect(DotFont.glyph('8').width, 5);
      // An unknown character is a blank, not a crash.
      expect(DotFont.glyph('x').bits.every((r) => r == 0), isTrue);
    });

    testWidgets('the widget is as wide as its glyphs and reads as text', (
      tester,
    ) async {
      await tester.pumpWidget(
        inApp(const Center(child: DotMatrixText('2,100', dot: 6, gap: 2))),
      );
      // 4 digits x 5 columns + a 1-column comma + 4 gaps = 25 columns.
      final size = tester.getSize(find.byType(DotMatrixText));
      expect(size.width, 25 * 8 - 2);
      expect(size.height, 7 * 8 - 2);
      expect(find.bySemanticsLabel('2,100'), findsOneWidget);
    });
  });

  group('gauges', () {
    test('ticks fill with progress', () {
      expect(TickGauge.filledFor(0, 34), 0);
      expect(TickGauge.filledFor(0.5, 34), 17);
      expect(TickGauge.filledFor(1, 34), 34);
      expect(TickGauge.filledFor(7, 34), 34);
      expect(TickGauge.filledFor(-1, 34), 0);
      expect(TickGauge.filledFor(double.nan, 34), 0);
    });

    testWidgets('a week is seven pills, each named for screen readers', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          Padding(
            padding: const EdgeInsets.all(20),
            child: DayTrack(
              days: [
                for (var i = 0; i < 7; i++)
                  (
                    DateTime.utc(2026, 11, 19 + i),
                    i == 6
                        ? DayState.today
                        : i.isEven
                        ? DayState.done
                        : DayState.missed,
                  ),
              ],
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Thu 19: checked in'), findsOneWidget);
      expect(find.bySemanticsLabel('Fri 20: missed'), findsOneWidget);
      expect(find.bySemanticsLabel('Wed 25: today'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
    });

    test('an address always draws the same orb', () {
      const a = '0xFCAd0B19bB29D4674531d6f115237E16AfCE377c';
      expect(Identicon.seedOf(a), Identicon.seedOf(a.toLowerCase()));
      expect(
        Identicon.seedOf(a),
        isNot(Identicon.seedOf('0x2000000000000000000000000000000000000002')),
      );
    });
  });

  group('theme', () {
    test('ink, one volt accent, and the type roles', () {
      const c = AppColors.dark;
      expect(c.ink, const Color(0xFF0A0E11));
      expect(c.volt, const Color(0xFFD4FF3A));
      final t = buildTheme(useGoogleFonts: false).extension<AppType>()!;
      // Compressed heavy italic headlines.
      expect(t.display(78).fontStyle, FontStyle.italic);
      expect(t.display(78).fontWeight, FontWeight.w800);
      expect(t.display(78).fontFamily, 'Barlow Condensed');
      // Light tabular numerals.
      expect(t.metric(40).fontFeatures, isNotEmpty);
      expect(t.overline.letterSpacing, 1.4);
      expect(Radii.lg, 28);
      expect(Sizes.button, 58);
    });

    testWidgets('the aurora drifts, and stands still with reduced motion', (
      tester,
    ) async {
      Widget app({required bool reduce}) => MaterialApp(
        theme: inAppTheme,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: const AuroraBackground(child: SizedBox.expand()),
        ),
      );
      await tester.pumpWidget(app(reduce: false));
      final aurora = tester.state<AuroraBackgroundState>(
        find.byType(AuroraBackground),
      );
      expect(aurora.drifting, isTrue);
      await tester.pumpWidget(app(reduce: true));
      expect(aurora.drifting, isFalse);
    });

    testWidgets('a screen can change the aurora\'s mood', (tester) async {
      await tester.pumpWidget(
        inApp(const AuroraBackground(child: SizedBox.expand())),
      );
      final aurora = tester.state<AuroraBackgroundState>(
        find.byType(AuroraBackground).first,
      );
      expect(aurora.palette, AuroraPalette.ink);
      setAuroraTone(AuroraPalette.volt);
      await tester.pump();
      expect(aurora.palette, AuroraPalette.volt);
      setAuroraTone(AuroraPalette.ink);
      await tester.pump();
      expect(aurora.palette, AuroraPalette.ink);
    });

    testWidgets('pills: disabled cannot be pressed, busy shows its label', (
      tester,
    ) async {
      var presses = 0;
      Widget pill({bool busy = false, bool on = true}) => inApp(
        Center(
          child: PillButton(
            kind: PillKind.volt,
            label: 'Launch the token',
            busy: busy,
            busyLabel: 'Launching on Flap…',
            onPressed: on ? () => presses++ : null,
          ),
        ),
      );
      await tester.pumpWidget(pill());
      await tester.tap(find.text('Launch the token'));
      expect(presses, 1);
      expect(tester.getSize(find.byType(PillButton)).height, 58);

      await tester.pumpWidget(pill(on: false));
      await tester.tap(find.text('Launch the token'));
      expect(presses, 1);

      await tester.pumpWidget(pill(busy: true));
      expect(find.text('Launching on Flap…'), findsOneWidget);
      await tester.tap(find.text('Launching on Flap…'));
      expect(presses, 1);
    });

    testWidgets('the floating tab bar marks the place you are on', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        inApp(
          Center(
            child: FloatingTabBar(
              current: 0,
              onSelect: (i) => picked = i,
              items: const [
                TabItem(icon: Icons.grid_view_rounded, label: 'Home'),
                TabItem(icon: Icons.add_rounded, label: 'Add', action: true),
                TabItem(icon: Icons.person, label: 'Wallet'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Home'));
      expect(picked, isNull, reason: 'already there');
      await tester.tap(find.byTooltip('Wallet'));
      expect(picked, 2);
    });

    testWidgets('an action in the tab bar is never the selected one', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      Color? disc(String label) =>
          (tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: find.byTooltip(label),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      // Even when the bar is told the action is where you are.
      for (final current in [0, 1]) {
        final picked = <int>[];
        await tester.pumpWidget(
          inApp(
            Center(
              child: FloatingTabBar(
                current: current,
                onSelect: picked.add,
                items: const [
                  TabItem(icon: Icons.grid_view_rounded, label: 'Home'),
                  TabItem(icon: Icons.add_rounded, label: 'Add', action: true),
                  TabItem(icon: Icons.person, label: 'Wallet'),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        // Volt marks where you are; the action is never volt.
        expect(disc('Add'), isNot(AppColors.dark.volt));
        expect(
          disc('Home'),
          current == 0 ? AppColors.dark.volt : isNot(AppColors.dark.volt),
        );
        // A place says whether it is selected; the action has no such state.
        expect(
          tester.getSemantics(find.bySemanticsLabel('Add')),
          isSemantics(
            isButton: true,
            hasTapAction: true,
            hasSelectedState: false,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Home')),
          isSemantics(
            isButton: true,
            hasTapAction: true,
            hasSelectedState: true,
            isSelected: current == 0,
          ),
        );
        // Every press of the action is passed on, as often as it is pressed.
        await tester.tap(find.byTooltip('Add'));
        await tester.tap(find.byTooltip('Add'));
        expect(picked, [1, 1]);
        // The same 56 disc as the places.
        expect(
          tester.getSize(
            find.descendant(
              of: find.byTooltip('Add'),
              matching: find.byType(AnimatedContainer),
            ),
          ),
          const Size(56, 56),
        );
      }
      semantics.dispose();
    });

    testWidgets('a message shows in the banner and leaves by itself', (
      tester,
    ) async {
      await tester.pumpWidget(
        inApp(
          const Stack(
            children: [
              Positioned(top: 0, left: 0, right: 0, child: BannerHost()),
            ],
          ),
        ),
      );
      bannerNote.value = BannerNote(BannerKind.success, 'Launched.');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Launched.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('Launched.'), findsNothing);
      expect(bannerNote.value, isNull);
    });
  });

  group('copy', () {
    // Words the product must not use, in any text or comment of the app.
    final banned = RegExp(
      r'\btrustless|\bbets?\b|\bbetting\b|gambl|jackpot|\bstak(e|es|ed|ing)\b',
      caseSensitive: false,
    );

    // The hero line as it is written in the source of config.dart.
    const heroSource = r"'RUN THE\nSTAKES.'";

    test('no banned word anywhere in lib/', () {
      final hits = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          // The one exception: the first screen's line, which the owner
          // chose with the name. It is spelled once, in config.dart.
          final line = lines[i].replaceAll(heroSource, '');
          if (banned.hasMatch(line)) hits.add('${file.path}:${i + 1}');
        }
      }
      expect(hits, isEmpty);
    });

    test('the first screen\'s line is spelled once, in config.dart', () {
      final hits = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains(heroSource)) hits.add(file.path);
        }
      }
      expect(hits, hasLength(1));
      expect(hits.single, endsWith('config.dart'));
    });

    test('the product name is spelled in config.dart only', () {
      final hits = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('config.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Comments and the app's class names may say it; strings may not.
          final code = line.split('//').first;
          if (RegExp("['\"][^'\"]*(Showup|Cypher Run)").hasMatch(code)) {
            hits.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(hits, isEmpty);
    });
  });
}
