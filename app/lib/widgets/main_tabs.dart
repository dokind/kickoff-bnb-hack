import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_state.dart';
import '../screens/add_round_sheet.dart';
import 'tab_bar.dart';

/// The floating glass bar: Home, "+" and Wallet. Home and Wallet are the
/// app's two places. The "+" between them is an action, not a place: it
/// opens the "Add a round" sheet over whichever place you are on and is
/// never the selected one.
class MainTabs extends StatelessWidget {
  const MainTabs({super.key, required this.current, required this.state});

  /// The place you are on: [home] or [wallet].
  final int current;

  /// What the "Add a round" sheet works on.
  final AppState state;

  static const int home = 0;
  static const int add = 1;
  static const int wallet = 2;

  static const _routes = {home: '/', wallet: '/account'};

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: FloatingTabBar(
      current: current,
      onSelect: (i) {
        if (i == add) {
          showAddRoundSheet(context, state);
        } else {
          GoRouter.maybeOf(context)?.go(_routes[i]!);
        }
      },
      items: const [
        TabItem(icon: Icons.grid_view_rounded, label: 'Home'),
        TabItem(icon: Icons.add_rounded, label: 'Add a round', action: true),
        TabItem(icon: Icons.account_balance_wallet_rounded, label: 'Wallet'),
      ],
    ),
  );
}
