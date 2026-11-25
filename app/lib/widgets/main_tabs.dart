import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'tab_bar.dart';

/// The app's two places, as the floating glass bar: Home and Account.
class MainTabs extends StatelessWidget {
  const MainTabs({super.key, required this.current});

  /// 0 Home, 1 Account.
  final int current;

  static const _routes = ['/', '/account'];

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: FloatingTabBar(
      current: current,
      onSelect: (i) => GoRouter.maybeOf(context)?.go(_routes[i]),
      items: const [
        TabItem(icon: Icons.grid_view_rounded, label: 'Home'),
        TabItem(icon: Icons.account_balance_wallet_rounded, label: 'Account'),
      ],
    ),
  );
}
