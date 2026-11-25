import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'glass.dart';

/// A gradient orb drawn from a wallet address, always the same for the same
/// address. Stands in for a profile picture.
class Identicon extends StatelessWidget {
  const Identicon({super.key, required this.address, this.size = 36});
  final String address;
  final double size;

  /// The three numbers the orb is drawn from: two hues (0 to 1) and the
  /// angle the sweep starts at, in degrees.
  static (double, double, double) seedOf(String address) {
    var h = 5381;
    for (final unit in address.toLowerCase().codeUnits) {
      h = (h * 33 + unit) & 0x7fffffff;
    }
    return ((h % 360) / 360, ((h ~/ 360) % 360) / 360, (h ~/ 7 % 360) * 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final (hue1, hue2, angle) = seedOf(address);
    Color hsv(double hue, double s, double v) =>
        HSVColor.fromAHSV(1, hue * 360, s, v).toColor();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          gradient: SweepGradient(
            transform: GradientRotation(angle * math.pi / 180),
            colors: [
              hsv(hue1, 0.55, 0.95),
              hsv(hue2, 0.65, 0.55),
              hsv(hue1, 0.35, 0.25),
              hsv(hue1, 0.55, 0.95),
            ],
          ),
        ),
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 0.8,
            colors: [
              Colors.white.withValues(alpha: 0.35),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dot and a few words in a glass capsule: where the round is. With
/// [live] the dot pulses (unless motion is reduced).
class StatusBadge extends StatefulWidget {
  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    this.live = false,
  });

  final String text;
  final Color color;
  final bool live;

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  void _sync() {
    if (widget.live && context.motion) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassSurface.pill(
    blur: false,
    child: SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _DotPulse(
                    widget.color,
                    _pulse.isAnimating ? _pulse.value : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type
                    .body(12, FontWeight.w600)
                    .copyWith(height: 1),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DotPulse extends CustomPainter {
  _DotPulse(this.color, this.pulse);
  final Color color;
  final double? pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final p = pulse;
    if (p != null) {
      canvas.drawCircle(
        centre,
        3.5 + p * 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.6 * (1 - p)),
      );
    }
    canvas.drawCircle(centre, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DotPulse old) => old.color != color || old.pulse != pulse;
}
