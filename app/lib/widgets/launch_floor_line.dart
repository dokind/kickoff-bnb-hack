import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/pot.dart';

/// The second condition of a launch, under THE PRIZE on Home: a full bar is
/// not enough while the token pool is below the floor Flap's Portal asks
/// for (its `launch()` reverts below it). One line, only while the round is
/// open and the pool is short; nothing otherwise.
class LaunchFloorLine extends StatelessWidget {
  const LaunchFloorLine({super.key, required this.state, required this.round});

  final AppState state;

  /// The selected round, as Home shows it.
  final Round round;

  /// The sentence for the selected round, or null when there is nothing to
  /// say: launched, past the deadline, or the pool already has enough.
  static String? textFor(AppState state, Round round) {
    if (state.launched || state.pastDeadline) return null;
    final short = state.poolShort;
    if (short <= BigInt.zero) return null;
    final floor = formatCount(AppConfig.launchPoolFloor);
    const usd = AppConfig.quoteSymbol;
    final n = membersToFillPool(
      short: short,
      deposit: state.deposit,
      liquidityBps: round.liquidityBps,
    );
    if (n == null) {
      return 'Launch also needs $floor test $usd in the token pool. In this '
          'round a deposit adds nothing to it, so it takes a sponsor.';
    }
    final members = n == 1 ? '1 more member' : '${formatCount(n)} more members';
    return 'Launch also needs $floor test $usd in the token pool: about '
        '$members at this deposit, or a sponsor.';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final text = textFor(state, round);
      if (text == null) return const SizedBox.shrink();
      final c = context.colors;
      return Padding(
        padding: const EdgeInsets.only(top: Space.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.water_drop_outlined, size: 16, color: c.text2),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                text,
                key: const Key('launch-floor'),
                style: context.type.body(13).copyWith(color: c.text2),
              ),
            ),
          ],
        ),
      );
    },
  );
}
