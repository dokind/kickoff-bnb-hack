import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_state.dart';
import 'config.dart';
import 'router.dart';
import 'theme/theme.dart';
import 'widgets/common.dart';

/// Kept for the life of the app: while it is held the web build keeps its
/// accessibility tree on, so screen readers and accessibility tools see
/// every screen without the visitor first turning it on.
SemanticsHandle? webSemantics;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) webSemantics = SemanticsBinding.instance.ensureSemantics();
  // Find the server (OriginRegistry on chain, or the host kept from the last
  // visit) before the first call. Bounded: a slow RPC leaves the app on the
  // page's splash for a few seconds at most, never on a black screen.
  await AppConfig.resolveServer();
  final state = AppState();
  await state.init();
  final theme = buildTheme();
  // Wait a moment for the type to arrive, so the first screen is not drawn
  // in a fallback font and then redrawn. Never blocks the app for long.
  try {
    await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 2));
  } catch (_) {
    // Offline or slow: start with the fallback font.
  }
  runApp(CypherRunApp(state: state, theme: theme));
}

class CypherRunApp extends StatefulWidget {
  const CypherRunApp({super.key, required this.state, required this.theme});
  final AppState state;
  final ThemeData theme;

  @override
  State<CypherRunApp> createState() => _CypherRunAppState();
}

class _CypherRunAppState extends State<CypherRunApp> {
  late final _router = buildRouter(widget.state);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: AppConfig.productName,
    debugShowCheckedModeBanner: false,
    theme: widget.theme,
    routerConfig: _router,
    builder: (context, child) => AppBackdrop(child: child!),
  );
}
