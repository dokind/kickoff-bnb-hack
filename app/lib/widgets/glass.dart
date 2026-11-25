import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// Frosted glass: what is behind is blurred, then covered with a faint white
/// fill (and an optional colour tint) and a 1px rim that is brightest at the
/// top left.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = Radii.lg,
    this.tint,
    this.blur = true,
  });

  /// A capsule or a circle: the radius is half the height.
  const GlassSurface.pill({
    super.key,
    required this.child,
    this.tint,
    this.blur = true,
  }) : radius = 999;

  final Widget child;
  final double radius;

  /// A colour washed over the glass at a quarter strength.
  final Color? tint;

  /// False for rows in a long list: the fill and rim stay, the blur (the
  /// costly part) goes.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = tint == null
        ? c.glassFill
        : Color.alphaBlend(
            tint!.withValues(alpha: tint!.a * 0.25),
            c.glassFill,
          );
    final surface = CustomPaint(
      foregroundPainter: _RimPainter(radius: radius, color: c.text),
      child: ColoredBox(color: fill, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: surface,
            )
          : surface,
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final r = radius.clamp(0.0, size.shortestSide / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.04),
          color.withValues(alpha: 0.10),
        ],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.color != color;
}

/// A full-width glass card.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = Radii.lg,
    this.tint,
    this.blur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final bool blur;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: radius,
    tint: tint,
    blur: blur,
    child: Container(width: double.infinity, padding: padding, child: child),
  );
}
