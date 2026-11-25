import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'controls.dart';
import 'gauges.dart';
import 'identicon.dart';

/// The streak, today's state and the last seven days: kept compact, under
/// THE PRIZE, since a streak is 0 for everyone who has not joined.
class StreakBlock extends StatelessWidget {
  const StreakBlock({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final streak = state.streak;
    final (text, colour, live) = switch (state.stage) {
      HomeStage.join => ('Round open · not joined yet', c.volt, false),
      HomeStage.checkIn => ('Not checked in today', c.volt, true),
      HomeStage.checkedIn => ('Checked in today', c.success, false),
      HomeStage.launch => ('Bar full · ready to launch', c.volt, true),
      HomeStage.claim ||
      HomeStage.result => ('Token launched', c.success, false),
      HomeStage.refund || HomeStage.ended => ('Round ended', c.danger, false),
      _ => ('', c.text, false),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('Your streak'),
        Semantics(
          label: 'Your streak: ${days(streak)}',
          excludeSemantics: true,
          // Scaled down when a long streak in large text is wider than a
          // small phone.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$streak',
                  key: const Key('streak-number'),
                  style: t.metric(56, weight: FontWeight.w200),
                ),
                const SizedBox(width: 8),
                Text(
                  streak == 1 ? 'day' : 'days',
                  style: t.display(22).copyWith(color: c.text2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (text.isNotEmpty)
              StatusBadge(text: text, color: colour, live: live),
            // Not before this wallet's days are read: "0 days" would not be
            // true yet.
            if (state.isMember && state.yourDaysKnown)
              AppChip(
                text: '${days(state.daysOf)} in this round',
                icon: Icons.calendar_today_rounded,
                height: 28,
              ),
          ],
        ),
        const SizedBox(height: Space.s3),
        // The week's pills have a fixed height: past 1.3 their weekday
        // labels wrap on a narrow phone and overflow, so the text there
        // grows no further.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: DayTrack(days: state.week),
        ),
      ],
    );
  }
}
