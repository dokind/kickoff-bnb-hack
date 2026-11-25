import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'glass.dart';

/// Barcode-style progress: a row of ticks. The filled ones are white, the
/// last filled one is the accent and stands taller, the rest are faint.
class TickGauge extends StatelessWidget {
  const TickGauge({
    super.key,
    required this.progress,
    this.ticks = 34,
    this.height = 26,
    this.label,
  });

  /// 0 to 1.
  final double progress;
  final int ticks;
  final double height;

  /// What the gauge says, for screen readers ("42 of 60 check-ins").
  final String? label;

  /// How many ticks are filled for [progress].
  static int filledFor(double progress, int ticks) {
    final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    return (p * ticks).floor();
  }

  @override
  Widget build(BuildContext context) {
    final filled = filledFor(progress, ticks);
    return Semantics(
      label: label,
      value: label == null ? '${(progress.clamp(0, 1) * 100).round()}%' : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: filled.toDouble()),
        duration: context.motion
            ? const Duration(milliseconds: 600)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, shown, _) => CustomPaint(
          size: Size(double.infinity, height),
          painter: _TickPainter(
            filled: shown.round(),
            ticks: ticks,
            accent: context.colors.volt,
          ),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter({
    required this.filled,
    required this.ticks,
    required this.accent,
  });

  final int filled;
  final int ticks;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 2.5;
    final step = ticks > 1 ? (size.width - width) / (ticks - 1) : 0.0;
    for (var i = 0; i < ticks; i++) {
      final last = i == filled - 1;
      final h = last ? size.height : size.height * 0.66;
      final colour = last
          ? accent
          : Colors.white.withValues(alpha: i < filled ? 0.9 : 0.16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * step, (size.height - h) / 2, width, h),
          const Radius.circular(width / 2),
        ),
        Paint()..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.filled != filled || old.ticks != ticks || old.accent != accent;
}

/// A line that brightens to the right with a triangle marking the value.
/// The marker turns volt once the value reaches the end.
class MarkerScale extends StatelessWidget {
  const MarkerScale({super.key, required this.value});

  /// 0 to 1 (clamped).
  final double value;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: v),
        duration: context.motion
            ? const Duration(milliseconds: 600)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, shown, _) => CustomPaint(
          size: const Size(double.infinity, 24),
          painter: _MarkerPainter(shown, context.colors.volt),
        ),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.value, this.accent);
  final double value;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2 + 4;
    final line = Rect.fromLTWH(0, y - 1.5, size.width, 3);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(line, const Radius.circular(1.5)),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.85),
            ],
          ).createShader(line),
      )
      ..drawRect(
        Rect.fromLTWH(size.width - 1, y - 6, 1, 12),
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
    final x = value * size.width;
    canvas.drawPath(
      Path()
        ..moveTo(x - 5.5, y - 15)
        ..lineTo(x + 5.5, y - 15)
        ..lineTo(x, y - 6)
        ..close(),
      Paint()..color = value >= 1 ? accent : Colors.white,
    );
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.value != value || old.accent != accent;
}

/// What a day in the [DayTrack] looks like.
enum DayState { done, missed, today, upcoming }

/// One pill per day, like a training week: the weekday above a circle. A
/// checked-in day is a white pill with a tick, today has a volt ring, a
/// missed day is a quiet red cross.
class DayTrack extends StatelessWidget {
  const DayTrack({super.key, required this.days});

  /// The days to show, oldest first, with their state.
  final List<(DateTime, DayState)> days;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, (date, state)) in days.indexed) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 48),
              child: _DayPill(date: date, state: state),
            ),
          ),
        ),
      ],
    ],
  );
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _DayPill extends StatelessWidget {
  const _DayPill({required this.date, required this.state});
  final DateTime date;
  final DayState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final weekday = _weekdays[date.weekday - 1];
    final circle = switch (state) {
      DayState.done => Colors.black.withValues(alpha: 0.06),
      DayState.today => c.volt,
      DayState.missed => c.danger.withValues(alpha: 0.15),
      DayState.upcoming => Colors.white.withValues(alpha: 0.06),
    };
    final inside = switch (state) {
      DayState.done => Icon(Icons.check_rounded, size: 16, color: c.onVolt),
      DayState.missed => Icon(Icons.close_rounded, size: 15, color: c.danger),
      _ => Text(
        '${date.day}',
        style: t
            .body(14, FontWeight.w600)
            .copyWith(
              height: 1,
              color: state == DayState.today ? c.onVolt : c.text2,
            ),
      ),
    };
    final content = SizedBox(
      width: double.infinity,
      height: 78,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekday,
            style: t
                .body(12, FontWeight.w500)
                .copyWith(
                  height: 1,
                  color: state == DayState.done
                      ? Colors.black.withValues(alpha: 0.6)
                      : c.text2,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
            child: inside,
          ),
        ],
      ),
    );
    final Widget pill = switch (state) {
      DayState.done => DecoratedBox(
        decoration: ShapeDecoration(
          color: c.text,
          shape: const StadiumBorder(),
        ),
        child: content,
      ),
      DayState.today => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: StadiumBorder(side: BorderSide(color: c.volt, width: 1.5)),
        ),
        child: GlassSurface.pill(blur: false, child: content),
      ),
      DayState.missed => DecoratedBox(
        decoration: ShapeDecoration(
          color: c.danger.withValues(alpha: 0.10),
          shape: StadiumBorder(
            side: BorderSide(color: c.danger.withValues(alpha: 0.35)),
          ),
        ),
        child: content,
      ),
      DayState.upcoming => GlassSurface.pill(blur: false, child: content),
    };
    return Semantics(
      label:
          '$weekday ${date.day}: ${switch (state) {
            DayState.done => 'checked in',
            DayState.missed => 'missed',
            DayState.today => 'today',
            DayState.upcoming => 'not yet',
          }}',
      child: ExcludeSemantics(child: pill),
    );
  }
}

/// A small tile: an icon and a label above a big figure and its unit.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 14, color: c.text),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body(13, FontWeight.w500).copyWith(color: c.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: t.metric(30)),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit!,
                    style: t.body(13, FontWeight.w500).copyWith(color: c.text2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
