import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/season_text.dart';
import '../widgets/common.dart';
import 'checkin_sheet.dart';

/// Opens the join sheet for [round] over the current screen. With
/// [onJoined] the sheet closes itself once the deposit is paid and calls it
/// (Home opens Your round); without, it says "You're in" itself.
Future<void> showJoinSheet(
  BuildContext context,
  AppState state,
  Round round, {
  VoidCallback? onJoined,
}) => showAppSheet<void>(
  context,
  builder: (_) => JoinSheet(state: state, round: round, onJoined: onJoined),
);

/// Joining a round: what the deposit is and where it goes, what can be lost,
/// then ONE button that does every step ([AppState.joinRound]), with the
/// step running shown over it ([RunProgress]):
///   1. "Get test dollars": the wallet mints what it is short of the deposit
///      in Flap's free test USD. On mainnet this step is paying with a
///      stablecoin. Left out when the wallet already holds the deposit
///      (the button then says "Pay deposit").
///   2. "Approve test USD", then "Pay the deposit": `join()`.
/// Before the first transaction the sheet waits for the faucet's gas to
/// arrive and says "Preparing your wallet".
///
/// Over the button, plain lines say what happens to the deposit: the two
/// endings first (no launch: CheckInLauncher.refund; a launch: StreakVault
/// pays by days), then what can be lost. When the bar can fill today (what
/// is left of the goal is no more than one check-in per member), the round
/// can launch before this wallet checks in once, and a member with no
/// check-in receives nothing: the sheet says so and the deposit takes a
/// second press, "Join anyway". After the join the sheet offers today's
/// check-in for the same round.
///
/// A Season squad ([Round.season]) says when it starts ("Starts Tue 1 Dec.
/// Everyone starts at 0.") or, once started, how much of it is left. After
/// the Season's last day to join, or at its squad size, the app stops
/// offering Join: the button is a disabled "Joining closed 7 Dec" or "Squad
/// full", and a line says the contract still takes joins.
///
/// The sheet is about [round] from the moment it opens until it closes: its
/// name is over the title, and the deposit is paid into that round whatever
/// card is in view on Home behind it.
class JoinSheet extends StatefulWidget {
  const JoinSheet({
    super.key,
    required this.state,
    required this.round,
    this.onJoined,
  });
  final AppState state;

  /// The round named on the button that opened the sheet.
  final Round round;

  /// Called after the sheet has closed itself on a paid deposit.
  final VoidCallback? onJoined;

  @override
  State<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<JoinSheet> {
  bool _busy = false;

  /// The deposit is being paid: the dollars are there, and stay "there"
  /// while the balance drops at the end of the step.
  bool _paying = false;
  bool _done = false;
  String? _error;

  /// The person has read that the round can launch before their first
  /// check-in and pressed the button once: the next press pays.
  bool _lateConfirmed = false;

  AppState get _state => widget.state;

  /// The sheet's round as the app reads it now; as it was when the sheet
  /// opened if it has left the slider since.
  Round get _round => _state.roundOf(widget.round.id) ?? widget.round;
  BigInt get _deposit => _state.roundOf(widget.round.id) == null
      ? widget.round.deposit
      : _state.depositOf(widget.round.id);

  /// The round's check-ins so far: the chain's count when this is the
  /// selected round and the chain was read, the server's otherwise.
  int get _checkIns {
    final r = _round;
    return _state.selected == r.id
        ? math.max(_state.totalCheckIns, r.totalCheckIns)
        : r.totalCheckIns;
  }

  bool get _launched =>
      _round.launched || (_state.selected == _round.id && _state.launched);

  /// Joining, checking in and launching are still possible.
  bool get _open => !_launched && !_state.now.isAfter(_round.deadline);

  /// The bar can fill today: what is left of the goal is no more than one
  /// check-in per member (or it is full already), so the round can launch
  /// before this wallet's first check-in. A member with no check-in
  /// receives nothing from the vault.
  bool get _late {
    final goal = _round.checkInGoal;
    return _open &&
        goal > 0 &&
        goal - _checkIns <= math.max(1, _round.memberCount);
  }

  /// The Season this round is a squad of, if any.
  Season? get _season => _round.season;

  /// The app no longer offers Join in this Season squad: its last day to
  /// join is over, or it is full. The contract still takes joins.
  bool get _closed {
    final season = _season;
    return season != null &&
        _open &&
        season.joinClosed(_state.now, _round.memberCount);
  }

  Future<void> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The one press: test dollars when the wallet is short of them, then
  /// approve and pay.
  Future<void> _pay() async {
    if (_closed) return;
    if (_late && !_lateConfirmed) {
      // The first press only arms the button: it now says "Join anyway".
      setState(() => _lateConfirmed = true);
      return;
    }
    setState(() => _paying = true);
    await _run(() async {
      await _state.joinRound(launcher: widget.round.launcher);
      if (!mounted) return;
      final then = widget.onJoined;
      if (then != null) {
        Navigator.of(context).pop();
        then();
      } else {
        setState(() => _done = true);
      }
    });
    if (mounted) setState(() => _paying = false);
  }

  /// Closes this sheet and opens today's check-in for the same round.
  void _checkInNow() {
    final navigator = Navigator.of(context);
    final round = _round;
    navigator.pop();
    showCheckInSheet(navigator.context, _state, round);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) => PopScope(
      canPop: !_busy,
      child: SheetFrame(
        palette: _done ? AuroraPalette.volt : AuroraPalette.steel,
        child: _done ? _doneView(context) : _form(context),
      ),
    ),
  );

  Widget _doneView(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    // A Season that has not started (or has ended): no check-in to offer.
    final wait = _season?.checkInRefusal(_state.now);
    final open = _open && wait == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.verified_rounded, size: 44, color: c.volt),
        ),
        const SizedBox(height: Space.s3),
        RoundLabel(_round.name),
        const SizedBox(height: Space.s1),
        Text('YOU\'RE IN.', style: t.display(60)),
        const SizedBox(height: Space.s3),
        Text(
          '${formatTestUsd(_deposit)} is in the round\'s contract. '
          '${wait ?? 'Check in every day you move: each day is one more part '
                  'of the prize and of the coins.'}',
          key: const Key('join-done-text'),
          style: t.body(15).copyWith(color: c.text2),
        ),
        const Spacer(),
        if (open) ...[
          PillButton(
            kind: PillKind.volt,
            icon: Icons.check_rounded,
            label: 'Check in now',
            onPressed: _checkInNow,
          ),
          const SizedBox(height: 10),
          PillButton(
            kind: PillKind.glass,
            height: Sizes.buttonSmall,
            label: 'Later',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ] else
          PillButton(
            label: 'Let\'s go',
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final round = _round;
    final deposit = _deposit;
    final run = _state.stepsFor(StepAction.join, launcher: round.id);
    final step = run == null ? null : run.steps[run.current];
    // The dollars are there: in the wallet, or the run is past getting them
    // (the balance drops again once the deposit is paid).
    final hasDollars =
        _state.usd >= deposit ||
        (run != null &&
            run.current > run.steps.indexOf(ActionSteps.getDollars) &&
            run.steps[run.current] != ActionSteps.prepare);
    final mint = !_paying && _state.usd < deposit;
    final preparing = _busy && _state.funding;
    final toPool =
        deposit * BigInt.from(round.liquidityBps) ~/ BigInt.from(10000);
    final toPrize = deposit - toPool;
    final now = _state.now;
    final season = _season;
    // A press in flight keeps its button until the join is done.
    final closed = _closed && !_busy;
    final late = _late && !closed;
    final armed = late && _lateConfirmed;
    final seasonLine = season == null || !_open
        ? null
        : season.notStarted(now)
        ? season.startsLine
        : season.checkInsOver(now)
        ? season.endedHint
        : season.lateLine(now);

    // The label and title scroll with the card, so on a short screen with
    // large text only the lines over the button and the button are pinned.
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                RoundLabel(round.name),
                const SizedBox(height: Space.s1),
                Semantics(
                  header: true,
                  child: Text('Pay the deposit', style: t.title(30)),
                ),
                if (season != null && seasonLine != null) ...[
                  const SizedBox(height: Space.s2),
                  _SeasonLine(name: season.name, text: seasonLine),
                ],
                const SizedBox(height: Space.s4),
                GlassCard(
                  radius: 24,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      KeyValueRow('Deposit', formatTestUsd(deposit)),
                      KeyValueRow(
                        'To the prize',
                        '${formatTestUsd(toPrize)} · '
                            '${formatBps(10000 - round.liquidityBps)}',
                      ),
                      KeyValueRow(
                        'Into the shop',
                        round.liquidityBps == 0
                            ? 'None · a sponsor fills it'
                            : '${formatTestUsd(toPool)} · '
                                  '${formatBps(round.liquidityBps)}',
                      ),
                      const KeyValueRow(
                        'If it launches',
                        'You split the prize and the coins by your days',
                      ),
                      KeyValueRow(
                        'Last day to launch',
                        formatDate(round.deadline),
                        last: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Wallet balance',
                        style: t.body(13).copyWith(color: c.text2),
                      ),
                    ),
                    Text(
                      formatTestUsd(_state.usd),
                      style: t
                          .body(13, FontWeight.w600)
                          .copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s5),
                _StepRow(
                  number: 1,
                  title: 'Get test dollars',
                  detail:
                      'Testnet: free test dollars. On mainnet this step is '
                      'paying with a stablecoin.',
                  done: hasDollars,
                  active: step == ActionSteps.getDollars,
                ),
                const SizedBox(height: 10),
                _StepRow(
                  number: 2,
                  title: 'Pay deposit',
                  detail:
                      'Approves, then pays ${formatTestUsd(deposit)} into '
                      'the round\'s contract.',
                  done: false,
                  active:
                      step == ActionSteps.approve || step == ActionSteps.pay,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s3),
          // Over the button, always in view. On a short screen (or with large
          // text) this part scrolls by itself rather than push the button
          // off the sheet.
          // Capped by the sheet's own height, not the screen's, so the
          // button always has room under it.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: box.maxHeight.isFinite
                  ? box.maxHeight * 0.4
                  : MediaQuery.sizeOf(context).height * 0.34,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The app stops here; the chain does not.
                  if (closed) ...[
                    const _ClosedNote(),
                    const SizedBox(height: Space.s3),
                  ],
                  if (late) ...[
                    _LateWarning(checkIns: _checkIns, goal: round.checkInGoal),
                    const SizedBox(height: Space.s3),
                  ],
                  _Outcomes(deposit: deposit, liquidityBps: round.liquidityBps),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.s3),
          if (preparing) ...[
            const _Preparing(),
            const SizedBox(height: Space.s3),
          ],
          // The step running now, from what the state is really doing.
          if (_busy && run != null) ...[
            RunProgress(
              key: const Key('join-progress'),
              steps: run.steps,
              current: run.current,
            ),
            const SizedBox(height: Space.s4),
          ],
          if (closed && season != null) ...[
            PillButton(
              key: const Key('join-closed'),
              kind: PillKind.glass,
              icon: Icons.lock_outline_rounded,
              label: season.joinClosedLabel(now),
              onPressed: null,
            ),
          ] else ...[
            if (_error != null) ...[
              ErrorLine(_error!),
              const SizedBox(height: Space.s3),
            ],
            PillButton(
              kind: armed && _error == null ? PillKind.danger : PillKind.volt,
              label: _error != null
                  ? 'Try again'
                  : armed
                  ? 'Join anyway'
                  : mint
                  ? 'Join with test dollars · ${formatTestUsd(deposit)}'
                  : 'Pay deposit · ${formatTestUsd(deposit)}',
              icon: _error != null
                  ? Icons.refresh_rounded
                  : mint
                  ? Icons.bolt_rounded
                  : Icons.lock_rounded,
              busy: _busy,
              busyLabel: preparing ? 'Preparing your wallet…' : 'Joining…',
              onPressed: _pay,
            ),
          ],
        ],
      ),
    );
  }
}

/// Which Season the round is a squad of, and when it starts or how much of
/// it is left: "SEASON 1 · Starts Tue 1 Dec. Everyone starts at 0."
class _SeasonLine extends StatelessWidget {
  const _SeasonLine({required this.name, required this.text});
  final String name;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Row(
      key: const Key('join-season'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.flag_rounded, size: 18, color: c.volt),
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$name · ',
                  style: t.body(14, FontWeight.w600).copyWith(color: c.volt),
                ),
                TextSpan(text: text),
              ],
            ),
            style: t.body(14, FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// Over the disabled join button, first in the part that scrolls by itself,
/// once the app stops offering Join in a Season squad.
class _ClosedNote extends StatelessWidget {
  const _ClosedNote();

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Row(
      key: const Key('join-closed-note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: context.colors.text2,
          ),
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Text(
            joinStopNote,
            style: context.type.body(13).copyWith(color: context.colors.text2),
          ),
        ),
      ],
    ),
  );
}

/// What happens to the deposit, one plain line each, as the contracts do
/// it. The two endings first:
///   - no launch by the deadline: `CheckInLauncher.refund()` pays the whole
///     deposit back;
///   - a launch: StreakVault pays by days (your days / all days), not by
///     deposit.
/// Then, when no part of the deposits goes to the shop (`liquidityBps` 0, a
/// sponsor fills it), the Keep-Up Guarantee: the prize is every deposit, so
/// days at or above the average (all days / all members, frozen at launch)
/// get at least the deposit back in test USD, and fewer days get less from
/// the prize. Then what can be lost:
///   - a launch, and this wallet has no check-in: it receives nothing, and
///     the deposit stays in the prize (and the shop);
///   - a launch: `liquidityBps` of the deposit seeds the coin's shop, whose
///     LP Flap burns. Left out when that share is 0.
class _Outcomes extends StatelessWidget {
  const _Outcomes({required this.deposit, required this.liquidityBps});
  final BigInt deposit;
  final int liquidityBps;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('join-outcomes'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _OutcomeLine(
        icon: Icons.undo_rounded,
        text:
            'No launch by the deadline: press Refund and your '
            '${formatTestUsd(deposit)} comes back.',
      ),
      const _OutcomeLine(
        icon: Icons.rocket_launch_outlined,
        text: 'It launches: you\'re paid by your days, not by your deposit.',
      ),
      if (liquidityBps == 0) ...const [
        _OutcomeLine(
          key: Key('join-keep-up'),
          icon: Icons.verified_outlined,
          text:
              'It launches and your days are at least the average: your '
              'whole deposit back, or more.',
        ),
        _OutcomeLine(
          icon: Icons.trending_down_rounded,
          text: 'Fewer days than the average: you get back less.',
        ),
      ],
      const _OutcomeLine(
        icon: Icons.remove_circle_outline_rounded,
        text: 'It launches and you have no check-ins: nothing comes back.',
      ),
      if (liquidityBps > 0)
        _OutcomeLine(
          icon: Icons.water_drop_outlined,
          text:
              'It launches: ${formatBps(liquidityBps)} of your deposit goes '
              'into the shop, locked forever.',
        ),
    ],
  );
}

class _OutcomeLine extends StatelessWidget {
  const _OutcomeLine({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: context.colors.text2),
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Text(
            text,
            style: context.type.body(13).copyWith(color: context.colors.text2),
          ),
        ),
      ],
    ),
  );
}

/// The bar can fill today, or is full: the round can launch before this
/// wallet's first check-in.
class _LateWarning extends StatelessWidget {
  const _LateWarning({required this.checkIns, required this.goal});
  final int checkIns;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final full = checkIns >= goal;
    final count = '${formatCount(checkIns)} of ${formatCount(goal)} check-ins';
    return Semantics(
      container: true,
      liveRegion: true,
      child: GlassCard(
        key: const Key('join-late'),
        radius: Radii.row,
        padding: const EdgeInsets.all(14),
        blur: false,
        tint: c.danger.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: c.danger),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This round can launch before your first check-in. If '
                    'it does, you get nothing back.',
                    style: t.body(14, FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    full
                        ? 'The bar is full: $count.'
                        : goal - checkIns == 1
                        ? '$count: one more fills the bar.'
                        : '$count. The bar can fill today.',
                    style: t.body(13).copyWith(color: c.text2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The short state before the first transaction: the faucet's gas is on its
/// way.
class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        Icon(
          Icons.hourglass_top_rounded,
          size: 18,
          color: context.colors.text2,
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Text(
            'Preparing your wallet: a little test BNB for network fees is '
            'on its way.',
            style: context.type.body(13, FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// One numbered step of a flow: a number (a tick when [done], ringed in the
/// accent while [active]), a title and one sentence. The running step's
/// progress is the [RunProgress] over the button, not a second spinner.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.title,
    required this.detail,
    required this.done,
    required this.active,
  });

  final int number;
  final String title;
  final String detail;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final Widget mark = done
        ? Icon(Icons.check_rounded, size: 18, color: c.onVolt)
        : Text(
            '$number',
            style: t
                .body(14, FontWeight.w600)
                .copyWith(color: active ? c.volt : c.text),
          );
    return Semantics(
      label:
          'Step $number: $title. '
          '${done
              ? 'Done.'
              : active
              ? 'In progress.'
              : ''}',
      child: GlassCard(
        radius: Radii.row,
        padding: const EdgeInsets.all(12),
        blur: false,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? c.volt : Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: active ? Border.all(color: c.volt, width: 2) : null,
              ),
              child: mark,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.body(15, FontWeight.w600)),
                  Text(detail, style: t.body(13).copyWith(color: c.text2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
