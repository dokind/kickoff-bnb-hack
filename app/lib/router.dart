import 'package:go_router/go_router.dart';

import 'app_state.dart';
import 'screens/account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/result_screen.dart';

/// Routes. The first two are the places in the floating tab bar.
///   /            Home: the streak, the one action, the bar, the prize, members
///   /account     address, balances, back up key, import a key, start a round
///   /onboarding  two first-run steps (shown once, before anything else)
///   /result      after the launch: the token, your days, your share, Claim
/// Joining, checking in and sponsoring are sheets over Home, not routes.
GoRouter buildRouter(AppState state, {String? initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: state,
  redirect: (context, s) {
    if (!state.ready) return null;
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
  ],
);
