import 'package:flutter/material.dart';

import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'controls.dart' show Overline;
import 'glass.dart';

/// SO FAR: two rows of plain counts at the bottom of Home. "You" is this
/// wallet across every round it joined; "Everyone" is every round the app's
/// factory created, listed or not (an unlisted round is counted, never
/// named).
///
/// The numbers are shown as they are: small ones stay small, nothing is
/// rounded up, and a figure the server could not give is left out.
class SoFarCard extends StatelessWidget {
  const SoFarCard({super.key, required this.stats, this.inARound = false});
  final Stats stats;

  /// The app knows this wallet is in a round (from the chain). The server's
  /// totals can be a moment behind a join; then the "You" row is left out
  /// rather than saying no rounds were joined.
  final bool inARound;

  /// The figures of the "You" row, each as (number, words). Empty when the
  /// wallet has joined nothing.
  static List<(String, String)> yours(WalletStats you) => [
    if (you.rounds > 0) ...[
      (formatCount(you.days), you.days == 1 ? 'day shown up' : 'days shown up'),
      (formatCount(you.rounds), you.rounds == 1 ? 'round' : 'rounds'),
      if (you.claimed > BigInt.zero)
        (formatAmount(you.claimed), 'test ${AppConfig.quoteSymbol} claimed'),
    ],
  ];

  /// The figures of the "Everyone" row.
  static List<(String, String)> everyones(Stats s) => [
    (formatCount(s.people), s.people == 1 ? 'person' : 'people'),
    (formatCount(s.checkIns), s.checkIns == 1 ? 'check-in' : 'check-ins'),
    (formatAmount(s.deposited), 'test ${AppConfig.quoteSymbol} deposited'),
    (
      formatCount(s.launched),
      s.launched == 1 ? 'coin launched' : 'coins launched',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final read = stats.you;
    final you = read != null && read.rounds == 0 && inARound ? null : read;
    return GlassCard(
      key: const Key('so-far'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('So far'),
          if (you != null) ...[
            const SizedBox(height: Space.s3),
            _Line(
              who: 'You',
              figures: yours(you),
              empty: 'No rounds joined yet.',
            ),
            const SizedBox(height: Space.s3),
            Divider(color: c.hairline),
          ],
          const SizedBox(height: Space.s3),
          _Line(who: 'Everyone', figures: everyones(stats)),
        ],
      ),
    );
  }
}

/// Who, then their figures. The figures wrap on a narrow screen or with
/// large text; a number never parts from its words.
class _Line extends StatelessWidget {
  const _Line({required this.who, required this.figures, this.empty});
  final String who;
  final List<(String, String)> figures;

  /// What the line says with no figures.
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final said = figures.isEmpty
        ? (empty ?? '')
        : [for (final (n, words) in figures) '$n $words'].join(', ');
    return Semantics(
      container: true,
      label: '$who: $said',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who, style: t.body(13, FontWeight.w600)),
          const SizedBox(height: 4),
          if (figures.isEmpty)
            Text(empty ?? '', style: t.body(14).copyWith(color: c.text2))
          else
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final (n, words) in figures)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: n,
                          style: t
                              .body(15, FontWeight.w600)
                              .copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        TextSpan(
                          text: ' $words',
                          style: t.body(13).copyWith(color: c.text2),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
