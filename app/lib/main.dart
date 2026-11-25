import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_state.dart';
import 'config.dart';
import 'router.dart';
import 'theme/theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
