import 'package:flutter/material.dart';

/// LED dot-matrix numerals, seven dots tall. Used for money: the prize, a
/// share, a balance. Lit dots are [color]; the unlit ones stay faintly
/// visible, like a display that is switched on.
class DotMatrixText extends StatelessWidget {
  const DotMatrixText(
    this.text, {
    super.key,
    this.dot = 6,
    this.gap = 2.2,
    this.color = Colors.white,
  });

  final String text;

  /// Diameter of one dot and the space between two dots.
  final double dot;
  final double gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final glyphs = [for (final ch in text.characters) DotFont.glyph(ch)];
    final pitch = dot + gap;
    var columns = glyphs.isEmpty ? 0 : glyphs.length - 1;
    for (final g in glyphs) {
      columns += g.width;
    }
    final width = columns * pitch - gap;
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size(width < 1 ? 1 : width, DotFont.rows * pitch - gap),
          painter: _DotPainter(glyphs, dot, pitch, color),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.glyphs, this.dot, this.pitch, this.color);

  final List<DotGlyph> glyphs;
  final double dot;
  final double pitch;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lit = Paint()..color = color;
    final dim = Paint()..color = Colors.white.withValues(alpha: 0.07);
    final r = dot / 2;
    var x = 0.0;
    for (final glyph in glyphs) {
      for (var row = 0; row < DotFont.rows; row++) {
        for (var col = 0; col < glyph.width; col++) {
          canvas.drawCircle(
            Offset(x + col * pitch + r, row * pitch + r),
            r,
            glyph.lit(row, col) ? lit : dim,
          );
        }
      }
      x += (glyph.width + 1) * pitch;
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.glyphs != glyphs ||
      old.dot != dot ||
      old.pitch != pitch ||
      old.color != color;
}

/// One character: [width] columns by [DotFont.rows] rows. Each row is a
/// number whose bits are the dots, the leftmost dot being the highest bit.
class DotGlyph {
  const DotGlyph(this.width, this.bits);
  final int width;
  final List<int> bits;

  bool lit(int row, int col) => (bits[row] >> (width - 1 - col)) & 1 == 1;
}

/// The dot font: digits and the few marks a figure needs.
class DotFont {
  static const int rows = 7;

  static DotGlyph glyph(String ch) => _glyphs[ch] ?? _glyphs[' ']!;

  static const _glyphs = <String, DotGlyph>{
    '0': DotGlyph(5, [14, 17, 19, 21, 25, 17, 14]),
    '1': DotGlyph(5, [4, 12, 4, 4, 4, 4, 14]),
    '2': DotGlyph(5, [14, 17, 1, 2, 4, 8, 31]),
    '3': DotGlyph(5, [31, 2, 4, 2, 1, 17, 14]),
    '4': DotGlyph(5, [2, 6, 10, 18, 31, 2, 2]),
    '5': DotGlyph(5, [31, 16, 30, 1, 1, 17, 14]),
    '6': DotGlyph(5, [6, 8, 16, 30, 17, 17, 14]),
    '7': DotGlyph(5, [31, 1, 2, 4, 8, 8, 8]),
    '8': DotGlyph(5, [14, 17, 17, 14, 17, 17, 14]),
    '9': DotGlyph(5, [14, 17, 17, 15, 1, 2, 12]),
    '.': DotGlyph(1, [0, 0, 0, 0, 0, 0, 1]),
    ',': DotGlyph(1, [0, 0, 0, 0, 0, 1, 1]),
    ':': DotGlyph(1, [0, 0, 1, 0, 1, 0, 0]),
    '-': DotGlyph(3, [0, 0, 0, 7, 0, 0, 0]),
    '+': DotGlyph(5, [0, 4, 4, 31, 4, 4, 0]),
    '/': DotGlyph(5, [1, 1, 2, 4, 8, 16, 16]),
    '%': DotGlyph(5, [24, 25, 2, 4, 8, 19, 3]),
    ' ': DotGlyph(2, [0, 0, 0, 0, 0, 0, 0]),
  };
}
