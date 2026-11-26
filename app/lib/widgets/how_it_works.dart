import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../util/format.dart';
import 'common.dart';

/// The rules of the round in six lines, with what the server can and cannot
/// do said plainly.
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
                    'The deposit is ${formatTestUsd(state.deposit)}, paid '
                    'once: ${formatBps(10000 - round.liquidityBps)} to the '
                    'prize, ${formatBps(round.liquidityBps)} to the token '
                    'pool.',
              ),
              IconRow(
                icon: Icons.directions_walk_rounded,
                text:
                    'Check in on any day you take at least '
                    '${formatCount(round.minSteps)} steps. One per day, '
                    'counted in UTC.',
              ),
              IconRow(
                icon: Icons.rocket_launch_outlined,
                text:
                    'Launch needs both: '
                    '${formatCount(round.checkInGoal)} check-ins and '
                    '${formatCount(AppConfig.launchPoolFloor)} $testUsd in '
                    'the token pool. Then anyone can launch it on Flap.',
              ),
              const IconRow(
                icon: Icons.pie_chart_outline_rounded,
                text:
                    'The prize, half of the token supply and 80% of the '
                    'trading tax are shared by how many days each member '
                    'showed up.',
              ),
              IconRow(
                icon: Icons.undo_rounded,
                text:
                    'If the token has not launched by '
                    '${formatDate(round.deadline)}, every deposit goes back '
                    'in full.',
              ),
              const IconRow(
                icon: Icons.verified_user_outlined,
                text:
                    'Check-ins are attested by ${AppConfig.productName}\'s '
                    'server, not proven. The server cannot launch early, '
                    'block a launch or move funds.',
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
