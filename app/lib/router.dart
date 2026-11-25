import 'dart:async';

import 'package:go_router/go_router.dart';

import 'app_state.dart';
import 'config.dart';
import 'screens/account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/result_screen.dart';

/// Routes. The first two are the places in the floating tab bar.
///   /            Home: the streak, the one action, the bar, the prize, members
///   /account     address, balances, back up key, import a key, start a round
///   /onboarding  two first-run steps (shown once, before anything else)
///   /result      after the launch: the token, your days, your share, Claim
///   `/r/<launcher>`  a round's link: Home, with that round selected (listed or
///                not). A first-time visitor goes through onboarding first
///                and lands on the round after it.
/// Joining, checking in, sponsoring and inviting are sheets over Home, not
/// routes.
GoRouter buildRouter(AppState state, {String? initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: state,
  redirect: (context, s) {
    if (!state.ready) return null;
    // A round's link: remember the round, then carry on to Home (or to
    // onboarding, which ends on Home).
    if (s.uri.path.startsWith('/r/')) {
      final launcher = AppConfig.launcherFromLink(s.uri.path);
      if (launcher != null) scheduleMicrotask(() => state.openLink(launcher));
      return state.onboarded ? '/' : '/onboarding';
    }
    final onboarding = s.matchedLocation == '/onboarding';
    // First run: everything starts at onboarding.
    if (!state.onboarded) return onboarding ? null : '/onboarding';
    if (onboarding) return '/';
    // The result only exists once the token is launched.
    if (s.matchedLocation == '/result' && !state.launched) return '/';
    return null;
  },
  // Addresses from earlier builds, and anything mistyped, lead Home.
  onException: (context, s, router) => router.go('/'),
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => HomeScreen(state: state),
    ),
    GoRoute(
      path: '/account',
      builder: (_, _) => AccountScreen(state: state),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, _) => OnboardingScreen(state: state),
    ),
    GoRoute(
      path: '/result',
      builder: (_, _) => ResultScreen(state: state),
    ),
    // Never built: the redirect above leads on from a round's link.
    GoRoute(
      path: '/r/:launcher',
      builder: (_, _) => HomeScreen(state: state),
    ),
  ],
);
