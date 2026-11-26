import 'dart:async';

import 'package:go_router/go_router.dart';

import 'app_state.dart';
import 'config.dart';
import 'screens/account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/new_round_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/result_screen.dart';
import 'screens/round_screen.dart';
import 'util/format.dart';

/// Routes. The first two are the places in the floating tab bar; the "+"
/// between them opens the "Add a round" sheet, which is not a route.
///   /            Home: the streak, the one action, the bar, the prize, members
///   /account     Wallet: the balance, the address, back up your key, use
///                another wallet, about. `/wallet` is the same screen.
///   /new         New round: name it, set the deposit and the goal, start it.
///                A full screen with a back control and no tab bar, pushed
///                over the place the person was on.
///   /onboarding  two first-run steps (shown once, before anything else)
///   /result      after the launch: the token, your days, your share, Claim
///   `/round/<launcher>`  Your round: what you get, your money, how it ends,
///                your week, and the one next step. Pushed over Home (or
///                Wallet), so back returns there; opened alone from a web
///                link (`/#/round/<launcher>`), back leads Home. A first-time
///                visitor goes through onboarding first and lands on Home
///                with that round selected.
///   `/r/<launcher>`  a round's link: Home, with that round selected (listed or
///                not). A first-time visitor goes through onboarding first
///                and lands on the round after it.
/// Joining, checking in, sponsoring, inviting and opening an invite link are
/// sheets, not routes.
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
    // Your round's link: the round is looked for by the screen itself.
    if (s.uri.path.startsWith('/round/')) {
      final launcher = s.uri.pathSegments.length == 2
          ? s.uri.pathSegments[1]
          : '';
      if (!isAddress(launcher)) return '/';
      if (state.onboarded) return null;
      scheduleMicrotask(() => state.openLink(launcher));
      return '/onboarding';
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
      path: '/wallet',
      builder: (_, _) => AccountScreen(state: state),
    ),
    GoRoute(
      path: '/new',
      builder: (_, _) => NewRoundScreen(state: state),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, _) => OnboardingScreen(state: state),
    ),
    GoRoute(
      path: '/result',
      builder: (_, _) => ResultScreen(state: state),
    ),
    GoRoute(
      path: '/round/:launcher',
      builder: (_, s) =>
          RoundScreen(state: state, launcher: s.pathParameters['launcher']!),
    ),
    // Never built: the redirect above leads on from a round's link.
    GoRoute(
      path: '/r/:launcher',
      builder: (_, _) => HomeScreen(state: state),
    ),
  ],
);
