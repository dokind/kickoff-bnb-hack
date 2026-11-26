// Draws the Cypher Run app icon from the same mark the app shows next to its
// wordmark (Logomark in lib/widgets/aurora.dart) and writes every PNG the
// iOS, Android and web builds need. Run from the app folder:
//
//   flutter test tool/icon/generate_icon_test.dart
//
// It lives outside test/ so the normal suite does not rewrite the icons.
// Each size is painted from the vector, not scaled down from the master, so
// small icons stay sharp.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/theme/tokens.dart';
import 'package:pacepact/widgets/aurora.dart';

import 'png.dart';

const _colors = AppColors.dark;

/// The Logomark box is 1.2 wide for every 1 high.
const _markAspect = 1.2;

/// How a single PNG is drawn.
class _Spec {
  const _Spec({
    required this.path,
    required this.px,
    required this.markWidth,
    this.alpha = false,
    this.background = true,
    this.glow = true,
    this.shape = _Shape.square,
    this.markColor,
  });

  final String path;
  final int px;

  /// Width of the mark as a share of the canvas.
  final double markWidth;
  final bool alpha;
  final bool background;
  final bool glow;
  final _Shape shape;
  final Color? markColor;
}

enum _Shape { square, rounded, circle }

/// Paints one icon at [s] by [s] logical pixels.
void _paintIcon(ui.Canvas canvas, double s, _Spec spec, CustomPainter mark) {
  final rect = Rect.fromLTWH(0, 0, s, s);
  switch (spec.shape) {
    case _Shape.square:
      break;
    case _Shape.rounded:
      canvas.clipRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(s * 0.22)),
      );
    case _Shape.circle:
      canvas.clipPath(Path()..addOval(rect));
  }
  if (spec.background) {
    canvas.drawRect(rect, Paint()..color = _colors.inkDeep);
  }

  final mw = s * spec.markWidth;
  final mh = mw / _markAspect;
  final centre = Offset(s / 2, s / 2);

  if (spec.glow) {
    // Sized from the mark, so every variant has the same light around it.
    final glow = mw * 1.07;
    // The aurora, very faint: a steel light behind the mark, and a breath of
    // volt right at its heart so the mark seems lit from within.
    canvas
      ..drawCircle(
        centre,
        glow,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _colors.steel.withValues(alpha: 0.55),
              _colors.slate.withValues(alpha: 0.30),
              _colors.slate.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromCircle(center: centre, radius: glow)),
      )
      ..drawCircle(
        centre,
        mw * 0.75,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _colors.volt.withValues(alpha: 0.10),
              _colors.volt.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: mw * 0.75)),
      );
  }

  canvas
    ..save()
    ..translate(centre.dx - mw / 2, centre.dy - mh / 2);
  mark.paint(canvas, Size(mw, mh));
  canvas.restore();
}

Future<void> _render(_Spec spec, CustomPainter Function(Color) markFor) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  _paintIcon(
    canvas,
    spec.px.toDouble(),
    spec,
    markFor(spec.markColor ?? _colors.volt),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(spec.px, spec.px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  final png = encodePng(
    bytes!.buffer.asUint8List(),
    spec.px,
    spec.px,
    alpha: spec.alpha,
  );
  File(spec.path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png);
}

List<_Spec> _specs() {
  final specs = <_Spec>[];

  // iOS: every file the asset catalog lists. Opaque, square, no alpha: the
  // system applies the mask.
  const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final contents =
      jsonDecode(File('$iosDir/Contents.json').readAsStringSync())
          as Map<String, dynamic>;
  final seen = <String>{};
  for (final image in contents['images'] as List) {
    final m = image as Map<String, dynamic>;
    final name = m['filename'] as String?;
    if (name == null || !seen.add(name)) continue;
    final points = double.parse((m['size'] as String).split('x').first);
    final scale = int.parse((m['scale'] as String).replaceAll('x', ''));
    specs.add(
      _Spec(
        path: '$iosDir/$name',
        px: (points * scale).round(),
        markWidth: 0.58,
      ),
    );
  }

  // Android. minSdk is 26, so launchers use the adaptive icon; the legacy
  // PNGs are a fallback for tools that read mipmaps directly.
  const densities = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
  };
  const res = 'android/app/src/main/res';
  densities.forEach((name, d) {
    final legacy = (48 * d).round();
    final layer = (108 * d).round();
    specs
      ..add(
        _Spec(
          path: '$res/mipmap-$name/ic_launcher.png',
          px: legacy,
          markWidth: 0.56,
          alpha: true,
          shape: _Shape.rounded,
        ),
      )
      ..add(
        _Spec(
          path: '$res/mipmap-$name/ic_launcher_round.png',
          px: legacy,
          markWidth: 0.54,
          alpha: true,
          shape: _Shape.circle,
        ),
      )
      // Adaptive foreground: 108dp, transparent. The 66dp safe circle is
      // 61% of the layer; the mark's corners sit inside it at 44% wide.
      ..add(
        _Spec(
          path: '$res/mipmap-$name/ic_launcher_foreground.png',
          px: layer,
          markWidth: 0.44,
          alpha: true,
          background: false,
        ),
      )
      // Themed icon (Android 13+): only the alpha counts, so no glow.
      ..add(
        _Spec(
          path: '$res/mipmap-$name/ic_launcher_monochrome.png',
          px: layer,
          markWidth: 0.44,
          alpha: true,
          background: false,
          glow: false,
          markColor: Colors.white,
        ),
      );
  });

  // Web. The plain icons double as the apple-touch-icon, so they are opaque
  // and square like the iOS icon; maskable ones keep the mark inside the
  // 80% safe circle; the favicon is a small rounded tile for browser tabs.
  specs
    ..add(
      const _Spec(
        path: 'web/favicon.png',
        px: 64,
        markWidth: 0.64,
        alpha: true,
        glow: false,
        shape: _Shape.rounded,
      ),
    )
    ..add(const _Spec(path: 'web/icons/Icon-192.png', px: 192, markWidth: 0.58))
    ..add(const _Spec(path: 'web/icons/Icon-512.png', px: 512, markWidth: 0.58))
    ..add(
      const _Spec(
        path: 'web/icons/Icon-maskable-192.png',
        px: 192,
        markWidth: 0.48,
      ),
    )
    ..add(
      const _Spec(
        path: 'web/icons/Icon-maskable-512.png',
        px: 512,
        markWidth: 0.48,
      ),
    );
  return specs;
}

void main() {
  testWidgets('generate the app icon', (tester) async {
    // Take the painter from the app's own Logomark, so the icon is the mark
    // the user sees on the welcome screen, whatever it becomes.
    CustomPainter markFor(Color colour) {
      final finder = find.descendant(
        of: find.byType(Logomark),
        matching: find.byType(CustomPaint),
      );
      return tester.widget<CustomPaint>(finder).painter!;
    }

    final painters = <Color, CustomPainter>{};
    for (final colour in [_colors.volt, Colors.white]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Logomark(size: 100, color: colour)),
        ),
      );
      painters[colour] = markFor(colour);
    }

    final specs = _specs();
    await tester.runAsync(() async {
      for (final spec in specs) {
        await _render(spec, (c) => painters[c]!);
      }
    });
    // ignore: avoid_print
    print('Wrote ${specs.length} icons.');
  });
}
