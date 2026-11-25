import 'package:flutter/material.dart';

/// Colour tokens. Dark only: deep ink, frosted glass and one electric accent.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ink,
    required this.inkDeep,
    required this.slate,
    required this.steel,
    required this.fog,
    required this.volt,
    required this.voltDim,
    required this.onVolt,
    required this.success,
    required this.danger,
    required this.text,
    required this.text2,
    required this.text3,
    required this.hairline,
    required this.glassFill,
  });

  /// Background, top and bottom.
  final Color ink;
  final Color inkDeep;

  /// Aurora tones, and the opaque surface of dialogs.
  final Color slate;
  final Color steel;
  final Color fog;

  /// The one accent: money actions, progress, "you".
  final Color volt;
  final Color voltDim;
  final Color onVolt;

  /// States. Always paired with an icon or a word.
  final Color success;
  final Color danger;

  /// White at 100%, 64% and 38%. Sentences use the first two, a field's
  /// placeholder included; the third is for units, fine print and a
  /// placeholder in the large title type.
  final Color text;
  final Color text2;
  final Color text3;

  final Color hairline;

  /// The faint white fill of frosted glass.
  final Color glassFill;

  static const dark = AppColors(
    ink: Color(0xFF0A0E11),
    inkDeep: Color(0xFF05080A),
    slate: Color(0xFF17222A),
    steel: Color(0xFF24414A),
    fog: Color(0xFF3A5563),
    volt: Color(0xFFD4FF3A),
    voltDim: Color(0xFF3B4A10),
    onVolt: Color(0xFF05080A),
    success: Color(0xFF6CF2B0),
    danger: Color(0xFFFF5D5D),
    text: Color(0xFFFFFFFF),
    text2: Color(0xA3FFFFFF),
    text3: Color(0x61FFFFFF),
    hairline: Color(0x1FFFFFFF),
    glassFill: Color(0x0DFFFFFF),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      other is AppColors && t >= 0.5 ? other : this;
}

/// Spacing scale.
class Space {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s12 = 48;

  /// Side margin of every screen.
  static const double gutter = 20;
}

/// Corner radii. Cards use [lg]; fields use [md]; small rows use [row].
class Radii {
  static const double sm = 14;
  static const double md = 18;
  static const double row = 22;
  static const double lg = 28;
  static const double sheet = 40;
}

/// Sizes that are not spacing.
class Sizes {
  /// Smallest touch target.
  static const double touch = 44;

  /// Height of a pill button.
  static const double button = 58;

  /// Height of a compact pill button.
  static const double buttonSmall = 50;

  /// The app's column on wide screens.
  static const double column = 480;
}
