import 'package:flutter/material.dart';

import '../config.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/next_action.dart';
import 'common.dart';
import 'gauges.dart';

/// The pieces of Your round (`/round/<launcher>`), top to bottom under the
/// header: WHAT YOU GET, YOUR MONEY, HOW IT ENDS and YOUR WEEK. Each is
/// given its numbers; none reads the state, so each can be tested alone.

/// The hero: the biggest number on Your round.
///
/// Before the launch it is a projection and says so: what this wallet's
/// days would take from the prize if the round launched now. After the
/// launch it is what the vault has paid or holds for this wallet. After a
/// missed deadline it is the deposit that comes back.
class WhatYouGet extends StatelessWidget {
  const WhatYouGet({
    super.key,
    required this.amount,
    required this.label,
    this.unit = testUsd,
    this.line,
    this.call,
    this.note,
  });

  /// The number, written: "40", "822.32".
  final String amount;

  /// One line over it: "If it launched now, you'd get".
  final String label;

  /// Under the number, after it: "test USD", "test USD so far".
  final String unit;

  /// The token part, in words: "and 40% of the members' half of the token".
  final String? line;

  /// One line in the accent: what to do about it ("Check in today to earn a
  /// share.").
  final String? call;

  /// A quiet line at the bottom: why it is a projection.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return GlassCard(
      key: const Key('round-hero'),
      padding: const EdgeInsets.all(20),
      tint: c.volt.withValues(alpha: 0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('What you get'),
          const SizedBox(height: Space.s3),
          Semantics(
            container: true,
            label: '$label $amount $unit',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.body(14).copyWith(color: c.text2)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      _Rolling(
                        text: amount,
                        style: t.metric(64, weight: FontWeight.w200),
                      ),
                      const SizedBox(width: 8),
                      Text(unit, style: t.body(15).copyWith(color: c.text2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (line != null) ...[
            const SizedBox(height: 4),
            Text(line!, style: t.body(15, FontWeight.w500)),
          ],
          if (call != null) ...[
            const SizedBox(height: Space.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.bolt_rounded, size: 16, color: c.volt),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text(
                    call!,
                    key: const Key('round-hero-call'),
                    style: t.body(15, FontWeight.w600).copyWith(color: c.volt),
                  ),
                ),
              ],
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: Space.s3),
            Text(note!, style: t.body(12).copyWith(color: c.text2)),
          ],
        ],
      ),
    );
  }
}

/// A number that slides up into place when it changes (a check-in moved the
/// share), and simply changes with reduced motion.
class _Rolling extends StatelessWidget {
  const _Rolling({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: context.motion
        ? const Duration(milliseconds: 420)
        : Duration.zero,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: Text(text, key: ValueKey(text), style: style),
  );
}

/// One line of the receipt: what it is (and one quiet sentence under it),
/// and the amount.
class LedgerLine {
  const LedgerLine(this.label, this.value, {this.detail, this.strong = false});
  final String label;
  final String value;
  final String? detail;

  /// The line the receipt adds up to: in the accent.
  final bool strong;
}

/// YOUR MONEY: the member's deposit as a receipt, row by row, and the join
/// transaction when this device sent it.
class YourMoneyCard extends StatelessWidget {
  const YourMoneyCard({super.key, required this.lines, this.joinTx});
  final List<LedgerLine> lines;
  final String? joinTx;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('YOUR MONEY'),
        const SizedBox(height: 14),
        GlassCard(
          key: const Key('round-ledger'),
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, line) in lines.indexed) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    // The last line is the total of the ones above it.
                    child: line.strong
                        ? _Dashed(color: c.text3)
                        : Divider(color: c.hairline),
                  ),
                Semantics(
                  container: true,
                  label:
                      '${line.label}: ${line.value}'
                      '${line.detail == null ? '' : '. ${line.detail}'}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.label,
                                style: t.body(14, FontWeight.w500),
                              ),
                              if (line.detail != null)
                                Text(
                                  line.detail!,
                                  style: t.body(12).copyWith(color: c.text2),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.s3),
                        Expanded(
                          flex: 5,
                          child: Text(
                            line.value,
                            textAlign: TextAlign.right,
                            style: t
                                .body(15, FontWeight.w600)
                                .copyWith(
                                  color: line.strong ? c.volt : c.text,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (joinTx != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(color: c.hairline),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinkRow(
                    key: const Key('round-join-tx'),
                    label: 'Join transaction',
                    url: '${AppConfig.explorerTx}$joinTx',
                    value: joinTx,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A receipt's dashed rule over its total.
class _Dashed extends StatelessWidget {
  const _Dashed({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    child: LayoutBuilder(
      builder: (context, box) {
        final n = (box.maxWidth / 8).floor();
        return Row(
          children: [
            for (var i = 0; i < n; i++)
              Container(
                width: 4,
                height: 1,
                margin: const EdgeInsets.only(right: 4),
                color: color,
              ),
          ],
        );
      },
    ),
  );
}

/// One ending of the round in a few words.
class EndingCard {
  const EndingCard(this.ending, this.title, this.text);
  final RoundEnding ending;
  final String title;
  final String text;
}

/// HOW IT ENDS: the three ways a round ends, the one that applies now
/// lit and marked "Now".
class HowItEnds extends StatelessWidget {
  const HowItEnds({super.key, required this.cards, required this.now});
  final List<EndingCard> cards;
  final RoundEnding now;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('HOW IT ENDS'),
        const SizedBox(height: 14),
        for (final (i, card) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: Space.s2),
          Semantics(
            container: true,
            label:
                '${card.ending == now ? 'Applies now. ' : ''}'
                '${card.title}. ${card.text}',
            excludeSemantics: true,
            child: AnimatedContainer(
              key: Key('ending-${card.ending.name}'),
              duration: context.motion
                  ? const Duration(milliseconds: 300)
                  : Duration.zero,
              decoration: ShapeDecoration(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.row),
                  side: BorderSide(
                    color: card.ending == now ? c.volt : c.hairline,
                    width: card.ending == now ? 1.5 : 1,
                  ),
                ),
                color: card.ending == now
                    ? c.volt.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.03),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (card.ending) {
                      RoundEnding.withDays => Icons.rocket_launch_outlined,
                      RoundEnding.noDays => Icons.remove_circle_outline_rounded,
                      RoundEnding.refund => Icons.undo_rounded,
                    },
                    size: 20,
                    color: card.ending == now ? c.volt : c.text2,
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                card.title,
                                style: t.body(15, FontWeight.w600),
                              ),
                            ),
                            if (card.ending == now)
                              Container(
                                key: const Key('ending-now'),
                                height: 22,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                alignment: Alignment.center,
                                decoration: ShapeDecoration(
                                  color: c.volt,
                                  shape: const StadiumBorder(),
                                ),
                                child: Text(
                                  'Now',
                                  style: t
                                      .body(12, FontWeight.w700)
                                      .copyWith(color: c.onVolt, height: 1),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          card.text,
                          style: t.body(13).copyWith(color: c.text2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// YOUR WEEK: the last seven days (the strip from Home) and today in words.
class YourWeek extends StatelessWidget {
  const YourWeek({super.key, required this.days, required this.today});
  final List<(DateTime, DayState)> days;

  /// "Today: checked in", "Today: not yet". Null when check-ins are closed.
  final String? today;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('YOUR WEEK'),
        const SizedBox(height: 14),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: DayTrack(days: days),
        ),
        if (today != null) ...[
          const SizedBox(height: Space.s3),
          Text(
            today!,
            key: const Key('round-today'),
            style: t
                .body(14, FontWeight.w600)
                .copyWith(
                  color: today!.endsWith('checked in') ? c.success : c.text,
                ),
          ),
        ],
      ],
    );
  }
}
