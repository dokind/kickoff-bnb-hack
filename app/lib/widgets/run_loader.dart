import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The app's one loading mark: the two slanted volt bars of the [Logomark]
/// running on a treadmill. The bars surge forward in a staggered stride with
/// a short motion trail while a thin track under them streams backwards.
///
/// Where to use which:
/// - [RunLoader] (56) for a whole section or screen that is waiting for
///   something it cannot show yet ("Reading the round…"). Give it a
///   [label] of one short line.
/// - [RunLoader.small] (18) inside a button, a row or a line of text. A
///   [PillButton] with `busy: true` already shows it.
/// - [RunProgress] instead of either when the wait has named steps the person
///   can follow (joining: get test USD, approve, join).
///
/// With reduced motion (MediaQuery.disableAnimations) it is a still mark and
/// no ticker runs. A screen reader hears "Loading" and the label, as a live
/// region.
class RunLoader extends StatefulWidget {
  const RunLoader({super.key, this.size = 56, this.label, this.color});

  /// The small one for buttons and rows.
  const RunLoader.small({super.key, this.label, this.color}) : size = 18;

  /// The height of the mark and its track. The mark is 1.5 times as wide.
  final double size;

  /// One short line under the mark: "Reading the round…".
  final String? label;

  /// The bars' colour; volt when not given. A busy button passes its ink.
  final Color? color;

  /// One stride: the bars surge and settle once, the track moves on.
  static const Duration loop = Duration(milliseconds: 1100);

  @override
  State<RunLoader> createState() => RunLoaderState();
}

/// Public so tests can see whether the loop is running.
class RunLoaderState extends State<RunLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: RunLoader.loop,
  );

  /// Whether the bars are moving (false with reduced motion).
  bool get running => _run.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.motion) {
      if (!_run.isAnimating) _run.repeat();
    } else {
      _run
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colour = widget.color ?? c.volt;
    final still = !context.motion;
    final size = widget.size;
    final mark = RepaintBoundary(
      child: CustomPaint(
        size: Size(size * 1.5, size),
        painter: _RunPainter(progress: _run, color: colour, still: still),
      ),
    );
    final label = widget.label;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label == null ? 'Loading' : 'Loading. $label',
      child: ExcludeSemantics(
        child: label == null
            ? mark
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  mark,
                  SizedBox(height: size >= 40 ? 14 : 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.type
                        .body(size >= 40 ? 15 : 13, FontWeight.w500)
                        .copyWith(color: c.text2),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 0 to 1 and back to 0 over one loop: the stride of one bar. Eased in and
/// out at both ends, so it never jumps.
double _stride(double p) {
  final q = p - p.floorToDouble();
  const ease = Curves.easeInOutCubic;
  return q < 0.5 ? ease.transform(q * 2) : 1 - ease.transform((q - 0.5) * 2);
}

class _RunPainter extends CustomPainter {
  _RunPainter({
    required this.progress,
    required this.color,
    required this.still,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final bool still;

  /// The bottom bar runs this far behind the top one.
  static const double _stagger = 0.16;

  @override
  void paint(Canvas canvas, Size s) {
    final t = still ? 0.0 : progress.value;
    final w = s.width, h = s.height;
    // The mark is as tall as 80% of the box, in the middle of its width; the
    // track runs along the bottom.
    final markH = h * 0.78;
    final markW = markH * 1.2;
    final left = (w - markW) / 2;
    final reach = w * 0.12;

    for (final (i, top) in [(0, true), (1, false)]) {
      final p = t - i * _stagger;
      // Still: both bars at rest in the middle of their stride.
      final at = still ? 0.5 : _stride(p);
      final dx = (at - 0.5) * 2 * reach;
      // Forward speed now, from the stride a moment ago: the trail grows
      // while the bar surges and is gone before it settles back.
      final speed = still
          ? 0.0
          : math.max(0.0, (at - _stride(p - 0.03)) / 0.03);
      final trail = (speed / 3).clamp(0.0, 1.0);
      final bar = _bar(left, markW, markH, top);
      for (final (k, alpha) in [(3, 0.12), (2, 0.22), (1, 0.36)]) {
        if (trail <= 0.01) break;
        canvas.drawPath(
          bar.shift(Offset(dx - k * trail * reach * 0.45, 0)),
          Paint()..color = color.withValues(alpha: alpha * trail),
        );
      }
      canvas.drawPath(bar.shift(Offset(dx, 0)), Paint()..color = color);
    }

    // The treadmill: a faint line with dashes streaming backwards, fading at
    // both ends.
    final stroke = math.max(1.0, h * 0.045);
    final y = h - stroke / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(w, y),
      Paint()
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.16),
    );
    final dash = w * 0.16;
    final period = w * 0.30;
    // Two dash periods per loop, so the end of the loop meets its start.
    final shift = (t * 2 * period) % period;
    for (var x = -period - shift; x < w + period; x += period) {
      final from = math.max(0.0, x);
      final to = math.min(w, x + dash);
      if (to <= from) continue;
      final mid = (from + to) / 2;
      final fade = math.sin(math.pi * (mid / w).clamp(0.0, 1.0));
      canvas.drawLine(
        Offset(from, y),
        Offset(to, y),
        Paint()
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = color.withValues(alpha: 0.75 * fade),
      );
    }
  }

  /// One bar of the [Logomark] in a [w] by [h] box at [left], top or bottom.
  Path _bar(double left, double w, double h, bool top) => top
      ? (Path()
          ..moveTo(left + w * 0.30, 0)
          ..lineTo(left + w, 0)
          ..lineTo(left + w * 0.88, h * 0.40)
          ..lineTo(left + w * 0.18, h * 0.40)
          ..close())
      : (Path()
          ..moveTo(left + w * 0.12, h * 0.58)
          ..lineTo(left + w * 0.70, h * 0.58)
          ..lineTo(left + w * 0.58, h)
          ..lineTo(left, h)
          ..close());

  @override
  bool shouldRepaint(_RunPainter old) =>
      old.color != color || old.still != still || old.progress != progress;
}

/// A wait with named steps: a track with one dot per step and a runner
/// that moves from step to step, the current step's words under it and
/// "Step 2 of 3" beside them.
///
/// Use it, not [RunLoader], when a wait is a sequence the person can follow:
/// joining a round (get test USD, approve test USD, join), starting a round
/// (find the address, send the transaction). [current] is the index in
/// [steps] of the step running now, from 0; it is kept inside the list.
///
/// With reduced motion the runner jumps to its step and does not glow. A
/// screen reader hears the step count and the step, as a live region.
class RunProgress extends StatefulWidget {
  const RunProgress({super.key, required this.steps, required this.current})
    : assert(steps.length > 0);

  /// What each step does, in a few words: "Approve test USD".
  final List<String> steps;

  /// The step running now, from 0.
  final int current;

  /// "Step 2 of 3" for [current] 1 of three [steps].
  static String countLabel(int current, int total) =>
      'Step ${current.clamp(0, total - 1) + 1} of $total';

  @override
  State<RunProgress> createState() => RunProgressState();
}

/// Public so tests can see whether the glow is running.
class RunProgressState extends State<RunProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: RunLoader.loop,
  );

  /// Whether the runner's glow is moving (false with reduced motion).
  bool get running => _glow.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.motion) {
      if (!_glow.isAnimating) _glow.repeat();
    } else {
      _glow
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final total = widget.steps.length;
    final at = widget.current.clamp(0, total - 1);
    final motion = context.motion;
    final words = widget.steps[at];
    final count = RunProgress.countLabel(at, total);
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$count: $words',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 28,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: at.toDouble()),
                duration: motion
                    ? const Duration(milliseconds: 650)
                    : Duration.zero,
                curve: Curves.easeInOutCubic,
                builder: (context, runner, _) => RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _StepsPainter(
                      steps: total,
                      runner: runner,
                      glow: _glow,
                      still: !motion,
                      volt: c.volt,
                      rest: c.text3,
                      line: c.hairline,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: motion
                        ? const Duration(milliseconds: 260)
                        : Duration.zero,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      words,
                      key: ValueKey(at),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.body(15, FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(count, style: t.body(13).copyWith(color: c.text2)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepsPainter extends CustomPainter {
  _StepsPainter({
    required this.steps,
    required this.runner,
    required this.glow,
    required this.still,
    required this.volt,
    required this.rest,
    required this.line,
  }) : super(repaint: glow);

  final int steps;

  /// Where the runner is, in steps from the first (0.0 to steps - 1).
  final double runner;
  final Animation<double> glow;
  final bool still;
  final Color volt;
  final Color rest;
  final Color line;

  @override
  void paint(Canvas canvas, Size s) {
    const pad = 8.0;
    final y = s.height / 2;
    double xOf(double i) =>
        steps == 1 ? s.width / 2 : pad + (s.width - 2 * pad) * i / (steps - 1);
    final runX = xOf(runner);

    // The whole track, then the part already run.
    canvas
      ..drawLine(
        Offset(pad, y),
        Offset(s.width - pad, y),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = line,
      )
      ..drawLine(
        Offset(xOf(0), y),
        Offset(runX, y),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = volt.withValues(alpha: 0.7),
      );

    // A short trail behind the runner, brightest at the runner.
    final tail = math.min(36.0, runX - xOf(0));
    if (tail > 1) {
      canvas.drawLine(
        Offset(runX - tail, y),
        Offset(runX, y),
        Paint()
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [volt.withValues(alpha: 0), volt],
          ).createShader(Rect.fromLTRB(runX - tail, y - 2, runX, y + 2)),
      );
    }

    // One dot per step: filled once passed, a ring while ahead.
    for (var i = 0; i < steps; i++) {
      final x = xOf(i.toDouble());
      final passed = i <= runner + 0.001;
      canvas.drawCircle(
        Offset(x, y),
        4,
        passed
            ? (Paint()..color = volt)
            : (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = rest),
      );
    }

    // The runner, with a glow that breathes once a loop.
    final breath = still ? 0.5 : 0.5 - 0.5 * math.cos(2 * math.pi * glow.value);
    canvas
      ..drawCircle(
        Offset(runX, y),
        9 + 4 * breath,
        Paint()
          ..color = volt.withValues(alpha: 0.10 + 0.14 * breath)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawCircle(Offset(runX, y), 7, Paint()..color = volt);
  }

  @override
  bool shouldRepaint(_StepsPainter old) =>
      old.steps != steps ||
      old.runner != runner ||
      old.still != still ||
      old.volt != volt ||
      old.rest != rest ||
      old.line != line ||
      old.glow != glow;
}
