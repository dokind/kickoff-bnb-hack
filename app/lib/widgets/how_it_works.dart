import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../util/format.dart';
import 'common.dart';

/// The rules of the round in eight short lines, in plain words (the shop is
/// the coin's trading pool, the piggy bank is the round's vault), with what
/// the server can and cannot do said plainly.
class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key, required this.state, required this.round});
  final AppState state;
  final Round round;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('How it works'),
        const SizedBox(height: 14),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              IconRow(
                icon: Icons.payments_outlined,
                text:
                    'You pay ${formatTestUsd(state.deposit)} once: '
                    '${formatBps(10000 - round.liquidityBps)} to the prize, '
                    '${formatBps(round.liquidityBps)} to the shop money (the '
                    'coin\'s trading pool).',
              ),
              IconRow(
                icon: Icons.directions_walk_rounded,
                text:
                    'Walk ${formatCount(round.minSteps)}+ steps, then check '
                    'in. One check-in per wallet per day (UTC). Each one adds '
                    '1 day to the bar.',
              ),
              IconRow(
                icon: Icons.rocket_launch_outlined,
                text:
                    'Bar full (${formatCount(round.checkInGoal)} check-ins) '
                    'and ${formatCount(AppConfig.launchPoolFloor)} $testUsd '
                    'of shop money (Flap\'s floor)? Then anyone can press '
                    'Launch.',
              ),
              const IconRow(
                icon: Icons.storefront_outlined,
                text:
                    'Launch makes 1,000,000 new coins on Flap: half go into '
                    'the shop with the shop money, half into the group\'s '
                    'piggy bank. The shop is locked forever (LP burned).',
              ),
              const IconRow(
                icon: Icons.percent_rounded,
                text:
                    'For 30 days each trade pays a tax: 3% on buys, 5% on '
                    'sells. 80% goes to the piggy bank, 20% is burned.',
              ),
              const IconRow(
                icon: Icons.pie_chart_outline_rounded,
                text:
                    'The prize and the piggy bank are split by days: your '
                    'days ÷ all days, frozen at launch. 0 days = nothing.',
              ),
              IconRow(
                icon: Icons.undo_rounded,
                text:
                    'Not launched by ${formatDate(round.deadline)}? Each '
                    'member presses Refund and gets back exactly what they '
                    'paid. Sponsors too.',
              ),
              const IconRow(
                icon: Icons.verified_user_outlined,
                text:
                    'Check-ins are signed by ${AppConfig.productName}\'s '
                    'server, not proven. It cannot move money, launch early '
                    'or block a launch.',
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
