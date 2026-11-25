import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/dot_matrix.dart';
import '../widgets/gauges.dart';
import '../widgets/identicon.dart';
import '../widgets/main_tabs.dart';
import 'checkin_sheet.dart';
import 'join_sheet.dart';
import 'sponsor_sheet.dart';

/// Home, the one screen. The streak is the hero numeral, with today's state
/// and ONE primary action that changes with it:
///   "Join for 1,000 USD" -> "Check in today" -> "Checked in" (with a hint
///   about tomorrow) -> "Launch the token" once the bar is full (anyone) ->
///   "Claim your share" after the launch.
/// Under it: the bar everyone's check-ins fill, the prize so far, and the
/// members.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state, this.showBar = true});
  final AppState state;

  /// The floating tab bar (off in tests that pump the screen alone).
  final bool showBar;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  /// One sentence when the inline action (launch, refund) failed. The
  /// button stays, so pressing it again is the retry.
  String? _error;

  AppState get _state => widget.state;

  /// Other people's check-ins move the bar, so Home reads the round again
  /// every twenty seconds while it is open.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_busy) _state.refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) showMessage(context, done, kind: BannerKind.success);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openResult() => GoRouter.maybeOf(context)?.go('/result');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final round = _state.round;
      return Scaffold(
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _state.refresh,
                color: context.colors.onVolt,
                backgroundColor: context.colors.volt,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.s2,
                    Space.gutter,
                    260,
                  ),
                  children: [
                    _Header(state: _state),
                    const SizedBox(height: Space.s6),
                    if (round == null)
                      _NoRound(state: _state)
                    else ...[
                      if (_state.roundError != null) ...[
                        ErrorRetry(
                          text: _state.roundError!,
                          onRetry: _state.refresh,
                        ),
                        const SizedBox(height: Space.s5),
                      ],
                      _StreakHero(state: _state),
                      const SizedBox(height: Space.s6),
                      _BarCard(state: _state, round: round),
                      const SizedBox(height: 14),
                      _PrizeCard(state: _state, round: round),
                      const SizedBox(height: Space.s6),
                      _Members(state: _state, round: round),
                      const SizedBox(height: Space.s6),
                      _HowItWorks(state: _state, round: round),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomFade(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      48,
                      Space.gutter,
                      6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._action(context),
                        if (widget.showBar) ...[
                          const SizedBox(height: Space.s3),
                          const MainTabs(current: 0),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  /// The hint, the one primary action, and at most one quiet extra.
  List<Widget> _action(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    const usd = AppConfig.quoteSymbol;
    final stage = _state.stage;

    Widget hint(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _error != null
          ? ErrorLine(_error!)
          : Text(
              text,
              textAlign: TextAlign.center,
              style: t.body(13, FontWeight.w500).copyWith(color: c.text2),
            ),
    );

    switch (stage) {
      case HomeStage.loading || HomeStage.error || HomeStage.noRound:
        return const [];
      case HomeStage.join:
        return [
          hint('Pay once. It comes back if the token never launches.'),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.bolt_rounded,
            label: 'Join for ${formatMoney(_state.deposit, usd)}',
            onPressed: () => showJoinSheet(context, _state),
          ),
        ];
      case HomeStage.checkIn:
        return [
          hint(
            _state.hasPendingCheckIn
                ? 'Today\'s check-in is signed. Finish it on chain.'
                : _state.health.available
                ? 'Reads today\'s steps from your phone.'
                : 'Self-reported in the browser. Testnet only.',
          ),
          PillButton(
            icon: Icons.check_rounded,
            label: 'Check in today',
            onPressed: () => showCheckInSheet(context, _state),
          ),
        ];
      case HomeStage.checkedIn:
        final wait = nextUtcDay(_state.now).difference(_state.now);
        return [
          hint(
            'Come back tomorrow. The next day starts in ${formatWait(wait)}.',
          ),
          const PillButton(
            kind: PillKind.glass,
            icon: Icons.check_rounded,
            label: 'Checked in',
            onPressed: null,
          ),
        ];
      case HomeStage.launch:
        final short = _state.poolShort;
        final canCheckInFirst = _state.isMember && !_state.checkedInToday;
        return [
          hint(
            short > BigInt.zero
                ? 'The bar is full, but the launch pool is '
                      '${formatMoney(short, usd)} short of what Flap needs.'
                : 'The bar is full. Anyone can launch the token now.',
          ),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.rocket_launch_rounded,
            label: 'Launch the token',
            busy: _busy,
            busyLabel: _state.funding
                ? 'Preparing your wallet…'
                : 'Launching on Flap…',
            onPressed: short > BigInt.zero
                ? null
                : () => _run(_state.launch, 'Launched. The token is live.'),
          ),
          if (short > BigInt.zero) ...[
            const SizedBox(height: 10),
            PillButton(
              kind: PillKind.glass,
              height: Sizes.buttonSmall,
              label: 'Sponsor the launch pool',
              onPressed: () => showSponsorSheet(context, _state),
            ),
          ] else if (canCheckInFirst && !_busy)
            _TextAction(
              label: 'Check in first',
              onPressed: () => showCheckInSheet(context, _state),
            ),
        ];
      case HomeStage.claim:
        return [
          hint(
            _state.hasClaimable
                ? 'The token launched. Your share is waiting in the vault.'
                : 'The token launched. More arrives as people trade.',
          ),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.auto_awesome_rounded,
            label: 'Claim your share',
            onPressed: _openResult,
          ),
        ];
      case HomeStage.result:
        return [
          hint('The token launched. You have no check-ins in this round.'),
          PillButton(label: 'See the result', onPressed: _openResult),
        ];
      case HomeStage.refund:
        return [
          hint('The bar did not fill in time. Your deposit is yours again.'),
          PillButton(
            icon: Icons.undo_rounded,
            label: 'Take your deposit back',
            busy: _busy,
            busyLabel: _state.funding
                ? 'Preparing your wallet…'
                : 'Returning your deposit…',
            onPressed: () => _run(_state.refund, 'Your deposit is back.'),
          ),
        ];
      case HomeStage.ended:
        return [
          hint('This round closed without a launch.'),
          const PillButton(
            kind: PillKind.glass,
            label: 'Round ended',
            onPressed: null,
          ),
        ];
    }
  }
}

/// A quiet text button under the primary action.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: context.type
            .body(14, FontWeight.w500)
            .copyWith(color: context.colors.text2),
      ),
    ),
  );
}

/// A greeting and the round's name; the balance and the wallet's orb on the
/// right, which opens Account.
class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AppState state;

  String get _greeting => switch (state.now.hour) {
    >= 5 && < 12 => 'Good morning',
    >= 12 && < 18 => 'Good afternoon',
    _ => 'Good evening',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting, style: t.title(24)),
                const SizedBox(height: 3),
                Text(
                  state.round?.name ?? AppConfig.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body(14).copyWith(color: c.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s3),
          if (state.hasWallet)
            Semantics(
              button: true,
              label:
                  'Account. ${formatMoney(state.usd, AppConfig.quoteSymbol)}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => GoRouter.maybeOf(context)?.go('/account'),
                child: GlassSurface.pill(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 14),
                        Text(
                          formatMoney(state.usd, AppConfig.quoteSymbol),
                          style: t
                              .body(13, FontWeight.w600)
                              .copyWith(
                                height: 1,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        const SizedBox(width: 8),
                        Identicon(address: state.address),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown in place of the round while there is none to show.
class _NoRound extends StatelessWidget {
  const _NoRound({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return switch (state.stage) {
      HomeStage.error => ErrorRetry(
        text: state.roundError!,
        onRetry: state.refresh,
      ),
      HomeStage.noRound => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NO ROUND\nRIGHT NOW.', style: t.display(44)),
            const SizedBox(height: Space.s3),
            Text(
              'A round shows here as soon as one opens.',
              style: t.body(15).copyWith(color: c.text2),
            ),
            const SizedBox(height: Space.s4),
            PillButton(
              kind: PillKind.glass,
              height: Sizes.buttonSmall,
              icon: Icons.refresh_rounded,
              label: 'Look again',
              onPressed: state.refresh,
            ),
          ],
        ),
      ),
      _ => GlassCard(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.text),
            ),
            const SizedBox(width: Space.s3),
            Text('Reading the round…', style: t.body(15)),
          ],
        ),
      ),
    };
  }
}

/// The streak as the hero numeral, today's state, and the last seven days.
class _StreakHero extends StatelessWidget {
  const _StreakHero({required this.state});
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$streak', style: t.metric(104, weight: FontWeight.w200)),
              const SizedBox(width: 10),
              Text(
                streak == 1 ? 'day' : 'days',
                style: t.display(34).copyWith(color: c.text2),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (text.isNotEmpty)
              StatusBadge(text: text, color: colour, live: live),
            if (state.isMember)
              AppChip(
                text: '${days(state.daysOf)} in this round',
                icon: Icons.calendar_today_rounded,
                height: 28,
              ),
          ],
        ),
        const SizedBox(height: Space.s4),
        DayTrack(days: state.week),
      ],
    );
  }
}

/// The world bar: everyone's check-ins against the goal, as a tick gauge.
class _BarCard extends StatelessWidget {
  const _BarCard({required this.state, required this.round});
  final AppState state;
  final Round round;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final total = state.totalCheckIns;
    final goal = round.checkInGoal;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('The bar')),
              Text(
                state.launched
                    ? 'Full'
                    : state.pastDeadline
                    ? 'Closed ${formatDate(round.deadline)}'
                    : 'Closes ${formatDate(round.deadline)}',
                style: t.body(12, FontWeight.w500).copyWith(color: c.text2),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(formatCount(total), style: t.metric(44)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '/ ${formatCount(goal)} check-ins',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body(14, FontWeight.w500).copyWith(color: c.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          TickGauge(
            progress: state.barProgress,
            label: '${formatCount(total)} of ${formatCount(goal)} check-ins',
          ),
          const SizedBox(height: Space.s3),
          Text(
            'Everyone\'s check-ins fill this one bar. When it is full, a '
            'token launches on Flap.',
            style: t.body(13).copyWith(color: c.text2),
          ),
        ],
      ),
    );
  }
}

/// The prize so far in dot-matrix numerals, beside the launch pool.
class _PrizeCard extends StatelessWidget {
  const _PrizeCard({required this.state, required this.round});
  final AppState state;
  final Round round;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    const usd = AppConfig.quoteSymbol;
    final short = state.poolShort;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      tint: c.volt.withValues(alpha: 0.4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Prize so far'),
                const SizedBox(height: Space.s3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: DotMatrixText(
                    formatAmount(round.prizeNow, maxFraction: 0),
                    dot: 7.5,
                    gap: 2.5,
                  ),
                ),
                const SizedBox(height: Space.s3),
                Text(
                  'test $usd, shared by days shown up',
                  style: t.body(12).copyWith(color: c.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Overline('Launch pool'),
                const SizedBox(height: 6),
                Text(
                  formatAmount(state.poolQuoteNow, maxFraction: 0),
                  style: t
                      .metric(28)
                      .copyWith(color: short > BigInt.zero ? c.text : c.volt),
                ),
                const SizedBox(height: 2),
                Text(
                  state.launched
                      ? '$usd, in the pool'
                      : short > BigInt.zero
                      ? 'of ${formatCount(AppConfig.launchPoolFloor)} $usd '
                            'Flap needs'
                      : '$usd, enough for Flap',
                  textAlign: TextAlign.right,
                  style: t.body(12).copyWith(color: c.text2),
                ),
                if (short > BigInt.zero &&
                    !state.launched &&
                    !state.pastDeadline) ...[
                  const SizedBox(height: Space.s2),
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showSponsorSheet(context, state),
                      child: const AppChip(
                        text: 'Sponsor',
                        icon: Icons.add_rounded,
                        height: 30,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The members: one compact list, most days first.
class _Members extends StatelessWidget {
  const _Members({required this.state, required this.round});
  final AppState state;
  final Round round;

  /// Rows shown before "and N more".
  static const _shown = 20;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final members = state.members;
    final count = round.memberCount > members.length
        ? round.memberCount
        : members.length;
    final me = state.hasWallet ? state.address.toLowerCase() : '';
    var most = 7;
    for (final m in members) {
      if (m.daysOf > most) most = m.daysOf;
    }
    final ticks = most > 14 ? 14 : most;
    final rows = members.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Members', trailing: '$count'),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          Text(
            count == 0
                ? 'No one has joined yet. Be the first.'
                : 'The list shows here after the first check-in.',
            style: t.body(14).copyWith(color: c.text2),
          )
        else
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, m) in rows.indexed) ...[
                  _MemberRow(
                    rank: i + 1,
                    member: m,
                    isMe: m.address == me,
                    ticks: ticks,
                  ),
                  if (i < rows.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(color: c.hairline),
                    ),
                ],
              ],
            ),
          ),
        if (members.length > _shown) ...[
          const SizedBox(height: Space.s2),
          Text(
            'and ${members.length - _shown} more',
            style: t.body(13).copyWith(color: c.text2),
          ),
        ],
        if (AppConfig.webBaseUrl.isNotEmpty) ...[
          const SizedBox(height: Space.s3),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Clipboard.setData(ClipboardData(text: AppConfig.webBaseUrl));
                showMessage(context, 'Invite link copied.');
              },
              child: const AppChip(
                text: 'Copy invite link',
                icon: Icons.link_rounded,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.rank,
    required this.member,
    required this.isMe,
    required this.ticks,
  });

  final int rank;
  final Member member;
  final bool isMe;

  /// How many day ticks the row draws.
  final int ticks;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final name = isMe ? 'You' : shortAddress(member.address);
    final detail =
        '${days(member.daysOf)} · streak ${member.streak}'
        '${member.checkedInToday ? ' · in today' : ''}';
    return Semantics(
      label: '$rank. $name, $detail',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Text(
                '$rank',
                style: t.body(13, FontWeight.w600).copyWith(color: c.text2),
              ),
            ),
            const SizedBox(width: 12),
            Identicon(address: member.address, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isMe
                        ? t.body(14, FontWeight.w700).copyWith(color: c.volt)
                        : t.mono.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: t.body(11).copyWith(color: c.text2)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                for (var i = 0; i < ticks; i++)
                  Container(
                    width: 4,
                    height: 16,
                    margin: const EdgeInsets.only(left: 3),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: i < member.daysOf
                          ? (isMe ? c.volt : c.text)
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The rules of the round in six lines, with what the server can and cannot
/// do said plainly.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.state, required this.round});
  final AppState state;
  final Round round;

  @override
  Widget build(BuildContext context) {
    const usd = AppConfig.quoteSymbol;
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
                    'The deposit is ${formatMoney(state.deposit, usd)}, paid '
                    'once: ${formatBps(10000 - round.liquidityBps)} to the '
                    'prize, ${formatBps(round.liquidityBps)} to the launch '
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
                    'When the bar reaches ${formatCount(round.checkInGoal)} '
                    'check-ins, anyone can launch the token on Flap.',
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
