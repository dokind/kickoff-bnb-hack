import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/next_action.dart';
import '../util/pot.dart';
import '../widgets/common.dart';
import '../widgets/gauges.dart';
import '../widgets/identicon.dart';
import '../widgets/round_parts.dart';
import 'checkin_sheet.dart';
import 'join_sheet.dart';

/// Your round (`/round/<launcher>`): one round from a member's side, in
/// plain numbers. Opened from a round card that says "You're in" on Home,
/// from the Wallet's "In rounds" rows, from the "You" row of THE PRIZE, by
/// a web link `/#/round/<launcher>`, and after joining.
///
/// Top to bottom: the round's name, state and deadline in local time; WHAT
/// YOU GET (the biggest number: what this wallet would get back if the
/// round launched now, worded as a projection); YOUR MONEY (the deposit as
/// a receipt); HOW IT ENDS (the three endings, the one that applies now
/// lit); YOUR WEEK. One action is pinned to the bottom and is always the
/// right next step ([nextStep]).
///
/// The screen selects its round on Home, so everything it reads from the
/// state is about this round, and Home shows the same round on the way back.
class RoundScreen extends StatefulWidget {
  const RoundScreen({super.key, required this.state, required this.launcher});
  final AppState state;
  final String launcher;

  /// Where Your round of [launcher] lives.
  static String path(String launcher) => '/round/${launcher.toLowerCase()}';

  /// Opens Your round of [launcher] over the current screen, so back
  /// returns there. Does nothing without a router (a screen pumped alone).
  static void open(BuildContext context, String launcher) =>
      GoRouter.maybeOf(context)?.push(path(launcher));

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen> {
  bool _busy = false;
  String? _error;
  Timer? _poll;

  /// The round was not on the slider, and the app was asked to look for it
  /// by its address.
  bool _asked = false;

  /// That search has ended.
  bool _looked = false;
  double _actionHeight = 180;

  AppState get _state => widget.state;
  String get _id => widget.launcher.toLowerCase();

  @override
  void initState() {
    super.initState();
    _state.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
    // Other people's check-ins move the bar and the share.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_busy && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _state.refresh();
      }
    });
  }

  @override
  void dispose() {
    _state.removeListener(_changed);
    _poll?.cancel();
    super.dispose();
  }

  /// Keeps this round the selected one, and asks for it by its address
  /// when it is not on the slider (a link to an unlisted round).
  void _changed() {
    if (!mounted || !_state.hasWallet) return;
    if (_state.roundOf(_id) != null) {
      if (_state.selected != _id) {
        scheduleMicrotask(() {
          if (mounted && _state.selected != _id) _state.select(_id);
        });
      }
    } else if (!_asked && !_state.loading && isAddress(_id)) {
      _asked = true;
      scheduleMicrotask(() async {
        await _state.openLink(_id);
        if (mounted) setState(() => _looked = true);
      });
    }
  }

  void _back() {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.of(context).maybePop();
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final round = _state.roundOf(_id);
      final ready = round != null && _state.selected == _id;
      final canPop = GoRouter.maybeOf(context)?.canPop() ?? true;
      final missing = round == null && _looked && !_state.loading;
      return PopScope(
        canPop: canPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) GoRouter.maybeOf(context)?.go('/');
        },
        child: Scaffold(
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: RefreshIndicator(
                  onRefresh: _state.refresh,
                  color: context.colors.onVolt,
                  backgroundColor: context.colors.volt,
                  child: ListView(
                    key: const Key('round-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.s2,
                      Space.gutter,
                      (ready ? _actionHeight : 0) + Space.s6,
                    ),
                    children: [
                      Row(
                        children: [
                          GlassIconButton(
                            key: const Key('round-back'),
                            icon: Icons.arrow_back_rounded,
                            tooltip: 'Back',
                            onPressed: _back,
                          ),
                          const SizedBox(width: Space.s3),
                          const Overline('Your round'),
                        ],
                      ),
                      const SizedBox(height: Space.s5),
                      if (ready)
                        ..._content(context, round)
                      else if (missing)
                        GlassCard(
                          key: const Key('round-missing'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'This round could not be found. Check the '
                                'link, or pick a round on Home.',
                                style: context.type.body(15),
                              ),
                              const SizedBox(height: Space.s4),
                              PillButton(
                                kind: PillKind.glass,
                                height: Sizes.buttonSmall,
                                label: 'Go to Home',
                                onPressed: () =>
                                    GoRouter.maybeOf(context)?.go('/'),
                              ),
                            ],
                          ),
                        )
                      else
                        const LoadingCard(
                          key: Key('round-loading'),
                          label: 'Reading your round…',
                          minHeight: 260,
                        ),
                    ],
                  ),
                ),
              ),
              if (ready)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizeReporter(
                    onSize: (size) {
                      if (mounted && size.height != _actionHeight) {
                        setState(() => _actionHeight = size.height);
                      }
                    },
                    child: BottomFade(
                      key: const Key('round-action'),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.gutter,
                            BottomFade.defaultRise,
                            Space.gutter,
                            Space.s3,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _action(context, round),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  // What is on the screen ----------------------------------------------------

  /// The next step for this wallet in this round, by [nextStep].
  RoundNext get _next => nextStep(
    member: _state.isMember,
    launched: _state.launched,
    pastDeadline: _state.pastDeadline,
    days: _state.daysOf,
    checkedInToday: _state.checkedInToday,
    barFull: _state.goalReached,
    poolShort: _state.poolShort > BigInt.zero,
    hasClaimable: _state.hasClaimable,
    refundable: _state.refundable,
    chainRead: _state.onChain != null,
  );

  List<Widget> _content(BuildContext context, Round round) {
    final s = _state;
    final member = s.isMember;
    final daysKnown = !member || s.yourDaysKnown;
    final pot = Pot.build(
      prize: round.prizeNow,
      totalCheckIns: s.totalCheckIns,
      memberCount: round.memberCount,
      members: [for (final m in s.members) (m.address, m.daysOf)],
      you: s.address,
      isMember: member && daysKnown,
      yourDays: s.daysOf,
    );
    final money = YourMoney(
      deposit: s.depositOf(_id),
      liquidityBps: round.liquidityBps,
      prize: round.prizeNow,
      days: s.daysOf,
      total: pot.total,
    );
    final ending = endingNow(
      launched: s.launched,
      pastDeadline: s.pastDeadline,
      days: money.days,
    );
    return [
      _Header(state: s, round: round),
      const SizedBox(height: Space.s5),
      if (member && !daysKnown)
        const LoadingCard(label: 'Reading your days…', minHeight: 200)
      else
        _hero(round, money),
      if (member) ...[
        const SizedBox(height: Space.s6),
        YourMoneyCard(lines: _ledger(money), joinTx: s.joinTxOf(_id)),
        const SizedBox(height: Space.s6),
        HowItEnds(cards: _endings(round, money), now: ending),
        const SizedBox(height: Space.s6),
        YourWeek(
          days: s.week,
          today: s.launched || s.pastDeadline
              ? null
              : s.checkedInToday
              ? 'Today: checked in'
              : 'Today: not yet',
        ),
      ],
    ];
  }

  /// WHAT YOU GET, as it stands for this wallet now.
  Widget _hero(Round round, YourMoney money) {
    final s = _state;
    final share = money.share;
    if (!s.isMember) {
      if (s.launched || s.pastDeadline) {
        final back = s.refundedFrom(_id);
        return WhatYouGet(
          label: back ? 'Your deposit' : 'You were not in this round',
          amount: back ? formatAmount(money.deposit) : '0',
          unit: back ? '$testUsd, back in your wallet' : testUsd,
          line: back ? null : 'Only members share the prize and the token.',
        );
      }
      return WhatYouGet(
        label: 'Join to earn a share',
        amount: formatAmount(money.deposit),
        unit: '$testUsd deposit',
        line:
            'Every day you show up is one more part of the prize and of the '
            'token.',
      );
    }
    if (s.launched) {
      final quote = s.claimableQuote + s.claimedQuote;
      final tokens = s.claimableTokens + s.claimedTokens;
      if (money.days == 0) {
        return const WhatYouGet(
          label: 'The token launched',
          amount: '0',
          line: 'You had 0 days at launch, so nothing comes back.',
        );
      }
      return WhatYouGet(
        label: 'Yours from the vault so far',
        amount: formatAmount(quote),
        line:
            'and ${formatAmount(tokens)} tokens: $share of the members\' half '
            'of the token',
        note: s.hasClaimable
            ? '${formatTestUsd(s.claimableQuote)} of it is waiting for you to '
                  'claim. Trading tax keeps adding to it.'
            : 'All claimed so far. Trading tax keeps adding to it.',
      );
    }
    if (s.pastDeadline) {
      final back = s.refundable > BigInt.zero ? s.refundable : money.deposit;
      return WhatYouGet(
        label: 'Comes back to you',
        amount: formatAmount(back),
        line: 'Your whole deposit: the round did not launch in time.',
      );
    }
    if (money.days == 0) {
      return WhatYouGet(
        label: 'If it launched now, you\'d get',
        amount: '0',
        unit: '$testUsd so far',
        call: s.checkedInToday ? null : 'Check in today to earn a share.',
        note: 'A member with 0 days at launch gets nothing back.',
      );
    }
    return WhatYouGet(
      label: 'If it launched now, you\'d get',
      amount: formatAmount(money.projected),
      line: 'and $share of the members\' half of the token',
      call: s.checkedInToday ? null : shareNudge(money.days, money.total),
      note:
          'A projection: the prize split by today\'s check-ins. Every '
          'check-in until the launch changes it.',
    );
  }

  /// YOUR MONEY, row by row.
  List<LedgerLine> _ledger(YourMoney money) {
    final s = _state;
    final closed = !s.launched && s.pastDeadline;
    return [
      LedgerLine('Deposit paid', formatTestUsd(money.deposit)),
      LedgerLine(
        'Goes to the token pool',
        formatTestUsd(money.toPool),
        detail: s.launched
            ? 'In the token pool for good'
            : closed
            ? 'Comes back with Refund'
            : 'For good once it launches',
      ),
      LedgerLine(
        'Goes to the prize',
        formatTestUsd(money.toPrize),
        detail: closed ? 'Comes back with Refund' : 'Shared by days shown up',
      ),
      LedgerLine(
        'Your days shown up',
        '${money.days} of ${formatCount(money.total)} check-ins',
      ),
      LedgerLine(
        s.launched ? 'Your share' : 'Your share now',
        money.share,
        strong: true,
      ),
    ];
  }

  /// HOW IT ENDS, in this round's numbers.
  List<EndingCard> _endings(Round round, YourMoney money) {
    final s = _state;
    final share = money.share;
    final String withDays;
    if (money.days == 0) {
      withDays =
          'You get a share of the prize and of the members\' half of the '
          'token by your days. Claim it on the result screen.';
    } else if (s.launched) {
      withDays =
          'You get ${formatTestUsd(s.claimableQuote + s.claimedQuote)} so far '
          'and $share of the members\' half of the token. Claim it on the '
          'result screen.';
    } else {
      withDays =
          'If it launched now: ${formatTestUsd(money.projected)} and $share '
          'of the members\' half of the token. Claim it on the result '
          'screen.';
    }
    return [
      EndingCard(
        RoundEnding.withDays,
        'Launches with your check-ins',
        withDays,
      ),
      const EndingCard(
        RoundEnding.noDays,
        'Launches and you have 0 days',
        'Nothing comes back. Your deposit stays in the prize and the token '
            'pool.',
      ),
      EndingCard(
        RoundEnding.refund,
        'Not launched by ${formatMoment(round.deadline)}',
        'Your ${formatTestUsd(money.deposit)} comes back with Refund.'
            '${_next == RoundNext.refund ? ' Refund is open now: press it '
                      'below.' : ''}',
      ),
    ];
  }

  // The one action -----------------------------------------------------------

  List<Widget> _action(BuildContext context, Round round) {
    final t = context.type;
    final c = context.colors;
    final s = _state;
    final name = round.name.trim().isEmpty ? 'this round' : round.name.trim();
    final run = s.steps;
    final mine = _busy && run != null && run.launcher == _id ? run : null;

    Widget hint(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _error != null
          ? ErrorLine(_error!)
          : mine != null
          ? RunProgress(
              key: const Key('round-progress'),
              steps: mine.steps,
              current: mine.current,
            )
          : Text(
              text,
              key: const Key('round-hint'),
              textAlign: TextAlign.center,
              style: t.body(13, FontWeight.w500).copyWith(color: c.text2),
            ),
    );
    String busyLabel(String doing) =>
        s.funding ? 'Preparing your wallet…' : doing;

    switch (_next) {
      case RoundNext.join:
        return [
          hint('Pay once. It comes back if the token never launches.'),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.bolt_rounded,
            label: 'Join · ${formatTestUsd(s.deposit)}',
            onPressed: () => showJoinSheet(
              context,
              s,
              round,
              onJoined: () => showMessage(
                context,
                'You\'re in. Check in today to start your share.',
                kind: BannerKind.success,
              ),
            ),
          ),
        ];
      case RoundNext.checkIn:
        return [
          hint(
            s.hasPendingCheckIn
                ? 'Today\'s check-in is signed. Finish it on chain.'
                : s.health.available
                ? 'Reads today\'s steps from your phone.'
                : 'Self-reported in the browser. Testnet only.',
          ),
          PillButton(
            key: const Key('round-checkin'),
            icon: Icons.check_rounded,
            label: 'Check in',
            onPressed: () => showCheckInSheet(
              context,
              s,
              round,
              then: () {},
              thenLabel: 'Back to your round',
            ),
          ),
        ];
      case RoundNext.doneToday:
        final opens = nextUtcDay(s.now).toLocal();
        return [
          hint('Next check-in opens at ${formatTime(opens)}.'),
          const PillButton(
            kind: PillKind.glass,
            icon: Icons.check_rounded,
            label: 'Done for today',
            onPressed: null,
          ),
        ];
      case RoundNext.launch:
        return [
          hint('The bar is full. Anyone can launch the token now.'),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.rocket_launch_rounded,
            label: 'Launch $name',
            shrink: name,
            busy: _busy,
            busyLabel: busyLabel('Launching on Flap…'),
            onPressed: () => _run(
              () => s.launch(launcher: _id),
              'Launched. The token is live.',
            ),
          ),
          if (s.isMember && !s.checkedInToday && !_busy)
            Center(
              child: TextButton(
                onPressed: () => showCheckInSheet(
                  context,
                  s,
                  round,
                  then: () {},
                  thenLabel: 'Back to your round',
                ),
                child: Text(
                  'Check in first',
                  style: t.body(14, FontWeight.w500).copyWith(color: c.text2),
                ),
              ),
            ),
        ];
      case RoundNext.claim:
        return [
          hint('Your share is waiting in the vault.'),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.auto_awesome_rounded,
            label: 'Claim · ${formatTestUsd(s.claimableQuote)}',
            busy: _busy,
            busyLabel: busyLabel('Claiming…'),
            onPressed: () => _run(
              () => s.claim(launcher: _id),
              'Your share is in your wallet.',
            ),
          ),
        ];
      case RoundNext.result:
        return [
          hint(
            s.daysOf > 0
                ? 'Nothing more to claim yet. More arrives as people trade.'
                : 'You had no check-ins when it launched.',
          ),
          PillButton(
            kind: PillKind.glass,
            icon: Icons.open_in_full_rounded,
            label: 'See the result',
            onPressed: () => GoRouter.maybeOf(context)?.go('/result'),
          ),
        ];
      case RoundNext.refund:
        final back = s.refundable > BigInt.zero ? s.refundable : s.deposit;
        return [
          hint('The bar did not fill in time. Your deposit is yours again.'),
          PillButton(
            icon: Icons.undo_rounded,
            label: 'Refund · ${formatTestUsd(back)}',
            busy: _busy,
            busyLabel: busyLabel('Returning your deposit…'),
            onPressed: () =>
                _run(() => s.refund(launcher: _id), 'Your deposit is back.'),
          ),
        ];
      case RoundNext.ended:
        return [
          hint(
            s.refundedFrom(_id)
                ? 'Your deposit is back in your wallet.'
                : 'This round closed without a launch.',
          ),
          const PillButton(
            kind: PillKind.glass,
            label: 'Round ended',
            onPressed: null,
          ),
        ];
    }
  }
}

/// The round's name, its state, the bar and its deadline in local time:
/// "Closes Mon 30 Nov, 07:34 · 3 days left".
class _Header extends StatelessWidget {
  const _Header({required this.state, required this.round});
  final AppState state;
  final Round round;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final s = state;
    final (text, colour) = s.launched
        ? ('Launched', c.success)
        : s.pastDeadline
        ? ('Ended', c.danger)
        : s.goalReached
        ? ('Bar full', c.volt)
        : ('Open', c.volt);
    final left = formatTimeLeft(round.deadline.difference(s.now));
    final when = s.launched
        ? 'Live on Flap'
        : s.pastDeadline
        ? 'Closed ${formatMoment(round.deadline)}'
        : 'Closes ${formatMoment(round.deadline)}';
    final total = formatCount(s.totalCheckIns);
    final goal = formatCount(round.checkInGoal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            round.name,
            key: const Key('round-name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.title(32),
          ),
        ),
        const SizedBox(height: Space.s3),
        Wrap(
          spacing: Space.s2,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(text: text, color: colour),
            Text(
              when,
              key: const Key('round-deadline'),
              style: t.body(14, FontWeight.w500),
            ),
            if (left != null && !s.launched)
              Text(
                left,
                key: const Key('round-left'),
                style: t.body(14).copyWith(color: c.text2),
              ),
          ],
        ),
        const SizedBox(height: Space.s4),
        TickGauge(
          progress: s.barProgress,
          height: 18,
          label: '$total of $goal check-ins',
        ),
        const SizedBox(height: 6),
        Text(
          '$total of $goal check-ins fill the bar · '
          '${round.memberCount == 1 ? '1 member' : '${formatCount(round.memberCount)} members'}',
          style: t.body(13).copyWith(color: c.text2),
        ),
        if (!s.launched && !s.pastDeadline && s.poolShort > BigInt.zero) ...[
          const SizedBox(height: 4),
          Text(
            'The token pool is ${formatTestUsd(s.poolShort)} short of the '
            '${formatCount(AppConfig.launchPoolFloor)} $testUsd Flap needs.',
            style: t.body(13).copyWith(color: c.text2),
          ),
        ],
      ],
    );
  }
}
