import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/names.dart';
import '../util/pot.dart';
import '../util/season_text.dart';
import 'common.dart';
import 'identicon.dart';

/// THE PRIZE: what showing up is worth in the selected round, and how this
/// wallet compares with everyone else in it.
///
/// Before the launch every amount is a projection and says so ("if it
/// launched now"): the prize as it stands, split by today's check-ins the
/// way the vault will split it. After the launch the same list shows what
/// each member's days were worth of everything the vault has received. The
/// amounts are test USD only; the token part is said in words, because a
/// token that does not trade yet has no honest price.
///
/// Nothing here is read from the chain per member: the days come from the
/// server's members list (one call), the totals from the round.
class PotSection extends StatefulWidget {
  const PotSection({
    super.key,
    required this.state,
    required this.round,
    this.onInvite,
    this.onShareCard,
    this.onOpenYou,
  });

  final AppState state;

  /// The selected round, as Home shows it.
  final Round round;

  /// "Invite someone", while the round is open.
  final VoidCallback? onInvite;

  /// "Share card", beside "Invite someone": the round as a picture to post.
  final VoidCallback? onShareCard;

  /// The "You" row was pressed: Your round, with every number about you.
  final VoidCallback? onOpenYou;

  /// Rows shown before "Show everyone".
  static const top = 5;

  /// Ticks in a row's bar.
  static const ticks = 24;

  @override
  State<PotSection> createState() => _PotSectionState();
}

enum _Phase { open, launched, ended }

class _PotSectionState extends State<PotSection> {
  bool _everyone = false;

  @override
  void didUpdateWidget(PotSection old) {
    super.didUpdateWidget(old);
    if (old.round.id != widget.round.id) _everyone = false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final round = widget.round;
      final t = context.type;
      final c = context.colors;
      final phase = state.launched
          ? _Phase.launched
          : state.pastDeadline
          ? _Phase.ended
          : _Phase.open;
      // A member whose own read has not come back yet: their days are not
      // known, so the list's count stands and the hero waits.
      final daysKnown = !state.isMember || state.yourDaysKnown;
      final ended = phase == _Phase.ended;
      final pot = Pot.build(
        prize: round.prizeNow,
        totalCheckIns: state.totalCheckIns,
        // After the deadline refunds take members off the contract's
        // count, so the rows are what is said.
        memberCount: ended ? 0 : round.memberCount,
        members: [for (final m in state.members) (m.address, m.daysOf)],
        you: state.hasWallet ? state.address : null,
        isMember: state.isMember && daysKnown,
        yourDays: state.daysOf,
      );
      final shown = pot.shown(everyone: _everyone, top: PotSection.top);
      final more = pot.rows.length - shown.length;
      final reading = !state.membersRead && state.membersError == null;
      final failed = !state.membersRead && state.membersError != null;
      final note = _note(phase, pot);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The round's card right above says how many members it has.
          // After the deadline refunds take members off that count, so
          // here the rows are counted instead.
          SectionHeader(
            'THE PRIZE',
            trailing: ended && pot.rows.isNotEmpty
                ? '${formatCount(pot.rows.length)} joined'
                : null,
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: _Hero(
                    state: state,
                    phase: phase,
                    pot: pot,
                    goal: round.checkInGoal,
                    daysKnown: daysKnown,
                  ),
                ),
                Divider(color: c.hairline),
                if (reading && pot.rows.isEmpty)
                  const _Skeleton()
                else if (failed && pot.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ErrorLine(state.membersError!),
                        _Quiet(
                          label: 'Try again',
                          icon: Icons.refresh_rounded,
                          onPressed: state.loading ? null : state.refresh,
                        ),
                      ],
                    ),
                  )
                else if (pot.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      _empty(phase, pot.memberCount),
                      style: t.body(14).copyWith(color: c.text2),
                    ),
                  )
                else ...[
                  const SizedBox(height: 6),
                  for (final (i, row) in shown.indexed) ...[
                    if (i > 0)
                      i == shown.length - 1 && pot.youBelow(shown)
                          // Under the orbs: rows were left out here.
                          ? Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                                color: c.text3,
                                semanticLabel: 'Further down the list',
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(left: 60),
                              child: Divider(color: c.hairline),
                            ),
                    _RowTile(
                      row: row,
                      total: pot.total,
                      phase: phase,
                      onOpen: row.isYou ? widget.onOpenYou : null,
                    ),
                  ],
                  if (more > 0 || _everyone)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _Quiet(
                        key: const Key('pot-everyone'),
                        label: _everyone ? 'Show fewer' : 'Show everyone',
                        icon: _everyone
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        expanded: _everyone,
                        onPressed: () => setState(() => _everyone = !_everyone),
                      ),
                    )
                  else
                    const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          if (_everyone && more > 0) ...[
            const SizedBox(height: Space.s2),
            Text(
              'and ${formatCount(more)} more',
              style: t.body(13).copyWith(color: c.text2),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: Space.s3),
            Text(note, style: t.body(13).copyWith(color: c.text2)),
          ],
          if (phase == _Phase.open &&
              (widget.onInvite != null || widget.onShareCard != null)) ...[
            const SizedBox(height: Space.s3),
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: [
                // container: each chip is its own button; without it the
                // label merges up and the whole Prize card reads as one.
                if (widget.onInvite != null)
                  Semantics(
                    container: true,
                    button: true,
                    onTap: widget.onInvite,
                    label: 'Invite someone to ${round.name}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onInvite,
                      child: const AppChip(
                        text: 'Invite someone',
                        icon: Icons.ios_share_rounded,
                      ),
                    ),
                  ),
                if (widget.onShareCard != null)
                  Semantics(
                    container: true,
                    button: true,
                    onTap: widget.onShareCard,
                    label: 'Share a card of ${round.name}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const Key('pot-share-card'),
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onShareCard,
                      child: const AppChip(
                        text: 'Share card',
                        icon: Icons.image_outlined,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );

  /// What the card says with nobody in the list. The server lists a member
  /// once it has seen them in the app (their first GET /me or check-in).
  static String _empty(_Phase phase, int members) {
    if (phase == _Phase.ended) return 'No one is listed for this round.';
    if (members == 0) return 'No one has joined yet. Be the first.';
    return members == 1
        ? '1 member has joined. They show here once they open the app.'
        : '${formatCount(members)} members have joined. They show here once '
              'they open the app.';
  }

  /// The plain words under the list: who is not in it, and what no
  /// check-in means for a deposit.
  String? _note(_Phase phase, Pot pot) {
    final parts = <String>[];
    final n = pot.unlisted;
    final over = phase != _Phase.open;
    if (n > 0 && pot.rows.isNotEmpty) {
      parts.add(
        pot.unlistedHaveNoDays
            ? (over
                  ? (n == 1
                        ? '1 more member did not check in.'
                        : '${formatCount(n)} more members did not check in.')
                  : (n == 1
                        ? '1 more member has not checked in yet.'
                        : '${formatCount(n)} more members have not checked '
                              'in yet.'))
            : (n == 1
                  ? '1 more member is not in this list.'
                  : '${formatCount(n)} more members are not in this list.'),
      );
    }
    if (pot.someoneHasNoDays) {
      // With none of the deposits in the shop (a sponsor fills it), a
      // deposit only ever goes to the prize.
      final into = widget.round.liquidityBps == 0
          ? 'prize'
          : 'prize and the shop';
      if (phase == _Phase.open) {
        parts.add(
          '0 days = nothing. If the coin launches, that deposit stays in the '
          '$into; it comes back (with Refund) only if there is no launch by '
          'the deadline.',
        );
      } else if (phase == _Phase.launched) {
        parts.add(
          'A member with 0 days gets nothing: that deposit went to the '
          '$into.',
        );
      }
    }
    return parts.isEmpty ? null : parts.join(' ');
  }
}

/// The top of the card: what this wallet would get, or what a day is worth.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.state,
    required this.phase,
    required this.pot,
    required this.goal,
    required this.daysKnown,
  });
  final AppState state;
  final _Phase phase;
  final Pot pot;

  /// Check-ins the bar needs before the round can launch.
  final int goal;

  /// This wallet's own days have been read (always true for a visitor).
  final bool daysKnown;

  static const noCheckIns =
      'No check-ins yet. The first one would hold 100% of the prize share '
      'until someone else shows up.';

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    const usd = AppConfig.quoteSymbol;
    final quiet = t.body(14).copyWith(color: c.text2);

    if (phase == _Phase.launched) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The coin launched. These shares are final.',
            style: t.body(16, FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Each amount is that member\'s part of the prize and of the tax '
            'money the piggy bank has received so far. The same share of the '
            'piggy bank\'s 500,000 coins goes with it.',
            style: quiet,
          ),
        ],
      );
    }
    if (phase == _Phase.ended) {
      return Text(
        'No launch by the deadline, so nothing is shared. Each member '
        'presses Refund to get their whole deposit back.',
        style: t.body(15),
      );
    }

    // A member whose days have not been read: no amount, no share and no
    // nudge, rather than a 0 that is not true.
    if (state.isMember && !daysKnown) {
      return state.selectedReadOnce
          ? Text(
              'Your days in this round could not be read yet. Your share '
              'shows here as soon as they are.',
              key: const Key('pot-hero-unread'),
              style: quiet,
            )
          : const _HeroSkeleton();
    }

    final mine = pot.you;
    final member = state.isMember && mine != null;
    // A Season before its first check-in day (or after its last): there is
    // no check-in to nudge towards today.
    final waiting = state.round?.season?.checkInRefusal(state.now) != null;
    final nudge = !member || waiting
        ? null
        : state.checkedInToday
        ? const _Nudge(
            done: true,
            text: 'You\'re done for today. Come back tomorrow to grow it.',
          )
        : _Nudge(done: false, text: shareNudge(mine.days, pot.total));

    if (pot.total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(noCheckIns, style: t.body(16, FontWeight.w600)),
          if (nudge != null) ...[const SizedBox(height: Space.s3), nudge],
        ],
      );
    }

    if (!member) {
      return Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text:
                  'If it launched now, each day shown up would be worth '
                  'about ',
            ),
            TextSpan(
              text: '${formatAmount(pot.perDay)} test $usd',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        style: t.body(16),
      );
    }

    final amount = formatAmount(mine.amount);
    final needs = barNeedsSentence(goal, pot.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One sentence for a screen reader: the words and the number.
        Semantics(
          container: true,
          label: 'If it launched now, you\'d get $amount test $usd',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('If it launched now, you\'d get', style: quiet),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      amount,
                      key: const Key('pot-amount'),
                      style: t.metric(56, weight: FontWeight.w200),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'test $usd',
                      style: t.body(15).copyWith(color: c.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${mine.days} of ${formatCount(pot.total)} check-ins '
          '${mine.days == 1 ? 'is' : 'are'} yours: '
          '${formatShare(mine.days, pot.total)} of the prize and of the '
          'piggy bank\'s coins.',
          style: t.body(14),
        ),
        if (needs != null) ...[
          const SizedBox(height: 4),
          Text(
            needs,
            key: const Key('pot-bar-needs'),
            style: t.body(13).copyWith(color: c.text2),
          ),
        ],
        if (nudge != null) ...[const SizedBox(height: Space.s3), nudge],
      ],
    );
  }
}

/// The hero while this wallet's days are read: two still lines where the
/// amount and the share will be.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    final faint = Colors.white.withValues(alpha: 0.08);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(color: faint, shape: const StadiumBorder()),
    );
    return Semantics(
      label: 'Reading your days in this round',
      child: ExcludeSemantics(
        child: Column(
          key: const Key('pot-hero-skeleton'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(150, 12),
            const SizedBox(height: 12),
            bar(200, 36),
            const SizedBox(height: 12),
            bar(240, 12),
          ],
        ),
      ),
    );
  }
}

/// One line under the hero: what checking in today does to the share.
class _Nudge extends StatelessWidget {
  const _Nudge({required this.done, required this.text});
  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            done ? Icons.check_circle_rounded : Icons.bolt_rounded,
            size: 16,
            color: done ? c.success : c.volt,
          ),
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Text(
            text,
            key: const Key('pot-nudge'),
            style: context.type.body(14, FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// One member: orb, name and amount on the first line, the short address
/// under the name (not under "You"), then days and the bar. The name is a
/// friendly one made from the address ("Quiet Otter"); the address beside
/// it is what tells two wallets apart for sure.
class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.total,
    required this.phase,
    this.onOpen,
  });
  final PotRow row;
  final int total;
  final _Phase phase;

  /// The "You" row opens Your round.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final name = row.isYou ? 'You' : friendlyName(row.address);
    final none = row.days == 0 || total == 0;
    final amount = switch (phase) {
      _Phase.ended => null,
      _Phase.open => none ? 'nothing yet' : formatTestUsd(row.amount),
      _Phase.launched => none ? 'nothing' : formatTestUsd(row.amount),
    };
    final said = switch (phase) {
      _Phase.ended => '',
      _Phase.open => none ? ', nothing yet' : ', $amount if it launched now',
      _Phase.launched => ', $amount',
    };
    final open = onOpen;
    return Semantics(
      container: true,
      button: open != null,
      onTap: open,
      hint: open != null ? 'Opens your round' : null,
      label:
          '$name, ${days(row.days)}, ${formatShare(row.days, total)} of all '
          'check-ins$said',
      excludeSemantics: true,
      child: GestureDetector(
        key: open != null ? const Key('pot-you-open') : null,
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: [
              Identicon(address: row.address, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: row.isYou
                                ? t
                                      .body(14, FontWeight.w700)
                                      .copyWith(color: c.volt)
                                : t.body(14, FontWeight.w600),
                          ),
                        ),
                        if (amount != null) ...[
                          const SizedBox(width: Space.s2),
                          Expanded(
                            flex: 4,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  amount,
                                  maxLines: 1,
                                  style: none
                                      ? t.body(13).copyWith(color: c.text2)
                                      : t
                                            .body(14, FontWeight.w600)
                                            .copyWith(
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!row.isYou)
                      Text(
                        shortAddress(row.address),
                        maxLines: 1,
                        style: t.mono.copyWith(
                          fontSize: 11,
                          height: 1.3,
                          color: c.text2,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: MediaQuery.textScalerOf(
                              context,
                            ).scale(50),
                          ),
                          child: Text(
                            days(row.days),
                            maxLines: 1,
                            style: t
                                .body(12)
                                .copyWith(
                                  height: 1.1,
                                  color: c.text2,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ShareTicks(
                            fraction: row.fraction,
                            accent: row.isYou,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (open != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.volt),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A member's share of all check-ins as a row of ticks, in the language of
/// the bar on the round's card. The filled ticks are white; in the "You"
/// row, and only there, they are the accent.
class ShareTicks extends StatelessWidget {
  const ShareTicks({super.key, required this.fraction, this.accent = false});

  /// 0 to 1.
  final double fraction;
  final bool accent;

  /// How many of [ticks] are filled for [fraction]. Any share above zero
  /// fills at least one, and only a whole share fills them all.
  static int filledFor(double fraction, [int ticks = PotSection.ticks]) {
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    if (f <= 0) return 0;
    if (f >= 1) return ticks;
    return (f * ticks).round().clamp(1, ticks - 1);
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size(double.infinity, 12),
      painter: _SharePainter(
        filled: filledFor(fraction),
        colour: accent ? context.colors.volt : Colors.white,
      ),
    ),
  );
}

class _SharePainter extends CustomPainter {
  _SharePainter({required this.filled, required this.colour});
  final int filled;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    const ticks = PotSection.ticks;
    const width = 2.5;
    final step = (size.width - width) / (ticks - 1);
    for (var i = 0; i < ticks; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * step, 0, width, size.height),
          const Radius.circular(width / 2),
        ),
        Paint()
          ..color = i < filled
              ? colour.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.16),
      );
    }
  }

  @override
  bool shouldRepaint(_SharePainter old) =>
      old.filled != filled || old.colour != colour;
}

/// Three still rows while the members are read for the first time.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final faint = Colors.white.withValues(alpha: 0.08);
    Widget bar(double width) => Container(
      width: width,
      height: 10,
      decoration: ShapeDecoration(color: faint, shape: const StadiumBorder()),
    );
    return Semantics(
      label: 'Reading the members',
      child: ExcludeSemantics(
        child: Padding(
          key: const Key('pot-skeleton'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final width in const [96.0, 72.0, 84.0])
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: faint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            bar(width),
                            const SizedBox(height: 10),
                            FractionallySizedBox(
                              widthFactor: 1,
                              child: Container(
                                height: 10,
                                decoration: ShapeDecoration(
                                  color: faint,
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet control inside the card: a chip, with a full-height touch target.
class _Quiet extends StatelessWidget {
  const _Quiet({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.expanded,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// For a control that opens and closes something.
  final bool? expanded;

  @override
  Widget build(BuildContext context) => Pressable(
    label: label,
    onPressed: onPressed,
    expanded: expanded,
    ringInset: 6,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.touch + 4),
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: Opacity(
          opacity: onPressed == null ? 0.5 : 1,
          child: AppChip(text: label, icon: icon),
        ),
      ),
    ),
  );
}
