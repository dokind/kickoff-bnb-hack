import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Type: compressed heavy italic headlines, condensed titles, light tabular
/// numerals, small tracked overlines.
@immutable
class AppType extends ThemeExtension<AppType> {
  const AppType({
    required TextStyle display,
    required TextStyle title,
    required TextStyle metric,
    required TextStyle body,
    required this.overline,
    required this.mono,
  }) : _display = display,
       _title = title,
       _metric = metric,
       _body = body;

  final TextStyle _display;
  final TextStyle _title;
  final TextStyle _metric;
  final TextStyle _body;

  /// Small uppercase tracked label: "PRIZE SO FAR", "TODAY".
  final TextStyle overline;

  /// Addresses and keys.
  final TextStyle mono;

  /// Big compressed italic headline, set in capitals by the caller.
  TextStyle display(double size) =>
      _display.copyWith(fontSize: size, height: 0.9);

  /// Section and card titles.
  TextStyle title(double size) => _title.copyWith(fontSize: size, height: 1.15);

  /// Light tabular numerals for figures.
  TextStyle metric(double size, {FontWeight weight = FontWeight.w300}) =>
      _metric.copyWith(fontSize: size, height: 1.05, fontWeight: weight);

  TextStyle body([double size = 15, FontWeight weight = FontWeight.w400]) =>
      _body.copyWith(fontSize: size, fontWeight: weight);

  /// A quiet sentence under something.
  TextStyle get caption => _body.copyWith(fontSize: 13, height: 1.4);

  /// [useGoogleFonts] is false in tests so no font is fetched over the network.
  factory AppType.build(AppColors c, {bool useGoogleFonts = true}) {
    TextStyle family(String name, TextStyle s) {
      if (!useGoogleFonts) return s.copyWith(fontFamily: name);
      return switch (name) {
        'Barlow Condensed' => GoogleFonts.barlowCondensed(textStyle: s),
        'IBM Plex Mono' => GoogleFonts.ibmPlexMono(textStyle: s),
        _ => GoogleFonts.barlow(textStyle: s),
      };
    }

    return AppType(
      display: family(
        'Barlow Condensed',
        TextStyle(
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
          color: c.text,
          letterSpacing: -0.5,
        ),
      ),
      title: family(
        'Barlow Condensed',
        TextStyle(fontWeight: FontWeight.w600, color: c.text),
      ),
      metric: family(
        'Barlow',
        TextStyle(
          color: c.text,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      body: family('Barlow', TextStyle(height: 1.45, color: c.text)),
      overline: family(
        'Barlow',
        TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
          color: c.text2,
        ),
      ),
      mono: family(
        'IBM Plex Mono',
        TextStyle(fontSize: 13, height: 1.4, color: c.text),
      ),
    );
  }

  @override
  AppType copyWith() => this;

  @override
  AppType lerp(ThemeExtension<AppType>? other, double t) =>
      other is AppType && t >= 0.5 ? other : this;
}

extension AppTheme on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  AppType get type => Theme.of(this).extension<AppType>()!;

  /// False when the system or the browser asks for reduced motion: loops
  /// stand still and entrances are instant.
  bool get motion => !MediaQuery.disableAnimationsOf(this);
}

/// Screens are see-through and share one background, so a new screen fades
/// in (and settles from 98%) after the old one has faded out.
class _FadeThrough extends PageTransitionsBuilder {
  const _FadeThrough();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.4, 1, curve: Curves.easeOut),
      reverseCurve: const Interval(0.6, 1, curve: Curves.easeIn),
    );
    return FadeTransition(
      opacity: enter,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(enter),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0).animate(
            CurvedAnimation(
              parent: secondaryAnimation,
              curve: const Interval(0, 0.4, curve: Curves.easeIn),
              reverseCurve: const Interval(0, 0.6, curve: Curves.easeOut),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The one theme. Scaffolds are transparent: the aurora behind the app shows
/// through every screen. Buttons, chips and fields are the app's own widgets
/// (lib/widgets/controls.dart); this covers what Material still draws.
ThemeData buildTheme({bool useGoogleFonts = true}) {
  const c = AppColors.dark;
  final t = AppType.build(c, useGoogleFonts: useGoogleFonts);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: c.slate,
    splashFactory: NoSplash.splashFactory,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: c.steel,
          brightness: Brightness.dark,
        ).copyWith(
          primary: c.volt,
          onPrimary: c.onVolt,
          secondary: c.text,
          onSecondary: c.ink,
          surface: c.slate,
          onSurface: c.text,
          onSurfaceVariant: c.text2,
          surfaceTint: Colors.transparent,
          error: c.danger,
          onError: c.ink,
          outline: c.hairline,
          outlineVariant: c.hairline,
        ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values) p: const _FadeThrough(),
      },
    ),
    textTheme: TextTheme(
      titleLarge: t.title(26),
      titleMedium: t.body(17, FontWeight.w600),
      bodyLarge: t.body(16),
      bodyMedium: t.body(15),
      bodySmall: t.caption.copyWith(color: c.text2),
      labelLarge: t.body(16, FontWeight.w600),
      labelSmall: t.overline,
    ),
    iconTheme: IconThemeData(color: c.text),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.volt),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.volt,
      selectionColor: c.steel,
      selectionHandleColor: c.volt,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    extensions: [c, t],
  );
}
