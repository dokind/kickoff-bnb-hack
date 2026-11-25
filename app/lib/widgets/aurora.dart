import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// The mood of the background. Most screens are [ink]; the second onboarding
/// step and the sheets are [steel]; a finished step and the result are
/// [volt]; a failed round is [danger].
enum AuroraPalette { ink, steel, volt, danger }

/// The palette of the app-wide background. A screen that wants another mood
/// sets it when it opens and puts [AuroraPalette.ink] back when it closes.
final ValueNotifier<AuroraPalette> auroraTone = ValueNotifier(
  AuroraPalette.ink,
);

/// Sets [auroraTone]. Safe to call from `initState` and `dispose`: while a
/// frame is being built the change waits until the frame is done.
void setAuroraTone(AuroraPalette palette) {
  final scheduler = SchedulerBinding.instance;
  if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    scheduler.addPostFrameCallback((_) => auroraTone.value = palette);
  } else {
    auroraTone.value = palette;
  }
}

/// Nine colours on a 3 by 3 grid, row by row, like a mesh gradient.
List<Color> _mesh(AuroraPalette p, AppColors c) => switch (p) {
  AuroraPalette.ink => [
    c.inkDeep, c.slate, c.ink, //
    c.ink, c.steel.withValues(alpha: 0.85), c.slate,
    c.inkDeep, c.ink, const Color(0xFF10202A),
  ],
  AuroraPalette.steel => [
    c.slate, c.fog, c.slate, //
    c.steel, const Color(0xFF4D6B78), c.ink,
    c.ink, c.inkDeep, c.slate,
  ],
  AuroraPalette.volt => [
    c.ink, c.slate, c.voltDim, //
    c.slate, const Color(0xFF2A3A16), c.steel,
    c.inkDeep, c.ink, c.slate,
  ],
  AuroraPalette.danger => [
    c.ink, const Color(0xFF3A1517), c.slate, //
    c.slate, const Color(0xFF4A1E22), c.ink,
    c.inkDeep, c.ink, c.slate,
  ],
};

/// The atmosphere behind every screen: deep ink with soft lights on a 3 by 3
/// grid whose middle points drift slowly, under a faint film grain. With
/// "reduce motion" on (the system setting, or `prefers-reduced-motion` in a
/// browser) it stands still.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.palette, this.speed = 1, this.child});

  /// A fixed palette. Null follows [auroraTone] (the app-wide background).
  final AuroraPalette? palette;

  /// 1 is the calm default; cards that want more life use about 1.4.
  final double speed;
  final Widget? child;

  /// One full cycle of the drift at speed 1.
  static const period = Duration(seconds: 120);

  @override
  State<AuroraBackground> createState() => AuroraBackgroundState();
}

class AuroraBackgroundState extends State<AuroraBackground>
    with TickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: AuroraBackground.period * (1 / widget.speed),
    value: 0.2,
  );
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );
  late AuroraPalette _from = _wanted;
  late AuroraPalette _to = _wanted;

  AuroraPalette get _wanted => widget.palette ?? auroraTone.value;

  /// Whether the lights are moving. False with reduced motion.
  bool get drifting => _drift.isAnimating;

  /// The palette being shown (or faded to).
  AuroraPalette get palette => _to;

  @override
  void initState() {
    super.initState();
    auroraTone.addListener(_onTone);
  }

  void _onTone() => _retone();

  void _retone({bool rebuild = true}) {
    if (!mounted || _wanted == _to) return;
    _from = _to;
    _to = _wanted;
    if (rebuild) setState(() {});
    if (context.motion) {
      _fade.forward(from: 0);
    } else {
      _fade.value = 1;
    }
  }

  @override
  void didUpdateWidget(AuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _retone(rebuild: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!context.motion) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    auroraTone.removeListener(_onTone);
    _drift.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.inkDeep,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _AuroraPainter(
                drift: _drift,
                fade: _fade,
                from: _mesh(_from, c),
                to: _mesh(_to, c),
              ),
            ),
          ),
          const RepaintBoundary(
            child: IgnorePointer(child: CustomPaint(painter: _GrainPainter())),
          ),
          ?widget.child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.drift,
    required this.fade,
    required this.from,
    required this.to,
  }) : super(repaint: Listenable.merge([drift, fade]));

  final Animation<double> drift;
  final Animation<double> fade;
  final List<Color> from;
  final List<Color> to;

  @override
  void paint(Canvas canvas, Size size) {
    // Three slow waves with whole-number cycles per period, so the loop has
    // no seam: 30, 40 and 60 seconds at speed 1.
    final v = drift.value * 2 * math.pi;
    final a = math.sin(v * 4) * 0.14;
    final b = math.cos(v * 3) * 0.12;
    final w = math.sin(v * 2 + 1.3) * 0.10;
    final points = <Offset>[
      const Offset(0, 0), Offset(0.5 + w, 0), const Offset(1, 0), //
      Offset(0, 0.45 + a), Offset(0.55 + b, 0.5 - a), Offset(1, 0.4 + b),
      const Offset(0, 1), Offset(0.5 - w, 1), const Offset(1, 1),
    ];
    final radius = size.longestSide * 0.62;
    final f = fade.value;
    // Corners and edges first, the middle light last so it reads on top.
    for (final i in const [0, 2, 6, 8, 1, 3, 5, 7, 4]) {
      final colour = Color.lerp(from[i], to[i], f)!;
      final centre = Offset(
        points[i].dx * size.width,
        points[i].dy * size.height,
      );
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colour,
              colour.withValues(alpha: colour.a * 0.55),
              colour.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.from != from || old.to != to;
}

/// Very faint film grain, so the gradients do not band and the surface
/// feels physical. Painted once.
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final count = math.min((size.width * size.height / 90).round(), 24000);
    if (count <= 0) return;
    final random = math.Random(42);
    // Three brightness steps, one draw call each.
    final buckets = List.generate(3, (_) => <double>[]);
    for (var i = 0; i < count; i++) {
      buckets[i % 3]
        ..add(random.nextDouble() * size.width)
        ..add(random.nextDouble() * size.height);
    }
    const alphas = [0.010, 0.017, 0.025];
    for (var i = 0; i < 3; i++) {
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.fromList(buckets[i]),
        Paint()
          ..color = Colors.white.withValues(alpha: alphas[i])
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}

/// A track seen in perspective with a streak of light going round its outer
/// lane: the picture behind the first screen.
class TrackHero extends StatefulWidget {
  const TrackHero({super.key});

  @override
  State<TrackHero> createState() => _TrackHeroState();
}

class _TrackHeroState extends State<TrackHero>
    with SingleTickerProviderStateMixin {
  late final _lap = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
    value: 0.12,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!context.motion) {
      _lap.stop();
    } else if (!_lap.isAnimating) {
      _lap.repeat();
    }
  }

  @override
  void dispose() {
    _lap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0016)
        ..rotateX(-62 * math.pi / 180),
      child: SizedBox(
        width: 290,
        height: 560,
        child: CustomPaint(
          painter: _TrackPainter(_lap, volt: context.colors.volt),
        ),
      ),
    ),
  );
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.lap, {required this.volt}) : super(repaint: lap);

  final Animation<double> lap;
  final Color volt;

  @override
  void paint(Canvas canvas, Size size) {
    Path lane(double inset) {
      final rect = (Offset.zero & size).deflate(inset);
      return Path()..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width / 2)),
      );
    }

    for (var i = 0; i < 7; i++) {
      canvas.drawPath(
        lane(i * 16.0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.05 + i * 0.018),
      );
    }
    final metric = lane(0).computeMetrics().first;
    final start = lap.value * metric.length;
    final length = metric.length * 0.07;
    final streak = metric.extractPath(start, start + length);
    // The streak wraps past the end of the path.
    if (start + length > metric.length) {
      streak.addPath(
        metric.extractPath(0, start + length - metric.length),
        Offset.zero,
      );
    }
    canvas
      ..drawPath(
        streak,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..color = volt.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      )
      ..drawPath(
        streak,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = volt,
      );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.volt != volt;
}

/// The mark: two forward-leaning bars. A stand-in until there is a logo.
class Logomark extends StatelessWidget {
  const Logomark({super.key, this.size = 22, this.color = Colors.white});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 1.2, size), painter: _LogoPainter(color));
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final paint = Paint()..color = color;
    canvas
      ..drawPath(
        Path()
          ..moveTo(w * 0.30, 0)
          ..lineTo(w, 0)
          ..lineTo(w * 0.88, h * 0.40)
          ..lineTo(w * 0.18, h * 0.40)
          ..close(),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w * 0.12, h * 0.58)
          ..lineTo(w * 0.70, h * 0.58)
          ..lineTo(w * 0.58, h)
          ..lineTo(0, h)
          ..close(),
        paint,
      );
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.color != color;
}

/// The mark and the product name in wide heavy capitals.
class Wordmark extends StatelessWidget {
  const Wordmark(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) => Semantics(
    label: name,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Logomark(),
          const SizedBox(width: 10),
          Text(
            name.toUpperCase(),
            style: context.type
                .body(17, FontWeight.w800)
                .copyWith(letterSpacing: 3, height: 1),
          ),
        ],
      ),
    ),
  );
}
