import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'checkin_sheet.dart';

/// Opens the join sheet for [round] over the current screen.
Future<void> showJoinSheet(BuildContext context, AppState state, Round round) =>
    showAppSheet<void>(
      context,
      builder: (_) => JoinSheet(state: state, round: round),
    );

/// Joining a round: what the deposit is and where it goes, what can be lost,
/// then two real steps with their progress.
///   1. "Get test dollars": the wallet mints the deposit in Flap's free test
///      USD to itself. On mainnet this step is paying with a stablecoin.
///   2. "Pay deposit": approve, then `join()`.
/// Before the first transaction the sheet waits for the faucet's gas to
/// arrive and says "Preparing your wallet".
///
/// Over the button, three plain lines say what happens to the deposit
/// (CheckInLauncher.refund, StreakVault's shares, the pool at launch). When
/// the bar is one check-in from full, or full, the round can launch before
/// this wallet checks in once, and a member with no check-in receives
/// nothing: the sheet says so and the deposit takes a second press, "Join
/// anyway". After the join the sheet offers today's check-in for the same
/// round.
///
/// The sheet is about [round] from the moment it opens until it closes: its
/// name is over the title, and the deposit is paid into that round whatever
/// card is in view on Home behind it.
class JoinSheet extends StatefulWidget {
  const JoinSheet({super.key, required this.state, required this.round});
  final AppState state;

  /// The round named on the button that opened the sheet.
  final Round round;

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

  /// One more check-in by anyone fills the bar (or it is full already), so
  /// the round can launch before this wallet's first check-in. A member
  /// with no check-in receives nothing from the vault.
  bool get _late {
    final goal = _round.checkInGoal;
    return _open && goal > 0 && goal - _checkIns <= 1;
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

  Future<void> _getDollars() => _run(() => _state.getTestDollars(_deposit));

  Future<void> _pay() async {
    if (_late && !_lateConfirmed) {
      // The first press only arms the button: it now says "Join anyway".
      setState(() => _lateConfirmed = true);
      return;
    }
    setState(() => _paying = true);
    await _run(() async {
      await _state.payDeposit(launcher: widget.round.launcher);
      if (mounted) setState(() => _done = true);
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
    final open = _open;
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
          '${formatTestUsd(_deposit)} is in the round\'s contract. Check in '
          'every day you move: each day is one more part of the prize and of '
          'the token.',
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
    final hasDollars = _paying || _state.usd >= deposit;
    final preparing = _busy && _state.funding;
    final toPool =
        deposit * BigInt.from(round.liquidityBps) ~/ BigInt.from(10000);
    final toPrize = deposit - toPool;
    final late = _late;
    final armed = late && _lateConfirmed;

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
                        'To the token pool',
                        '${formatTestUsd(toPool)} · '
                            '${formatBps(round.liquidityBps)}',
                      ),
                      const KeyValueRow(
                        'If it launches',
                        'You share the prize and the token by your days',
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
                  active: _busy && !hasDollars && !preparing,
                ),
                const SizedBox(height: 10),
                _StepRow(
                  number: 2,
                  title: 'Pay deposit',
                  detail:
                      'Approves, then pays ${formatTestUsd(deposit)} into '
                      'the round\'s contract.',
                  done: false,
                  active: _busy && hasDollars && !preparing,
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
          if (_error != null) ...[
            ErrorLine(_error!),
            const SizedBox(height: Space.s3),
          ],
          if (!hasDollars)
            PillButton(
              label: _error != null ? 'Try again' : 'Get test dollars',
              icon: _error != null ? Icons.refresh_rounded : Icons.water_drop,
              busy: _busy,
              busyLabel: preparing
                  ? 'Preparing your wallet…'
                  : 'Getting test dollars…',
              onPressed: _getDollars,
            )
          else
            PillButton(
              kind: armed && _error == null ? PillKind.danger : PillKind.volt,
              label: _error != null
                  ? 'Try again'
                  : armed
                  ? 'Join anyway'
                  : 'Pay deposit · ${formatTestUsd(deposit)}',
              icon: _error != null ? Icons.refresh_rounded : Icons.lock_rounded,
              busy: _busy,
              busyLabel: preparing ? 'Preparing your wallet…' : 'Confirming…',
              onPressed: _pay,
            ),
        ],
      ),
    );
  }
}

/// What happens to the deposit, one plain line each, as the contracts do
/// it:
///   - no launch by the deadline: `CheckInLauncher.refund()` pays the whole
///     deposit back;
///   - a launch, and this wallet has no check-in: StreakVault shares by
///     days, so it receives nothing, and the deposit stays in the pool and
///     the prize;
///   - a launch: `liquidityBps` of the deposit seeds the token's pool, whose
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
            'Round never launches: your ${formatTestUsd(deposit)} comes '
            'back.',
      ),
      const _OutcomeLine(
        icon: Icons.remove_circle_outline_rounded,
        text: 'It launches and you have no check-ins: nothing comes back.',
      ),
      if (liquidityBps > 0)
        _OutcomeLine(
          icon: Icons.water_drop_outlined,
          text:
              'It launches: ${formatBps(liquidityBps)} of your deposit '
              'becomes the token pool for good.',
        ),
    ],
  );
}

class _OutcomeLine extends StatelessWidget {
  const _OutcomeLine({required this.icon, required this.text});
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

/// The round is one check-in from full, or full: it can launch before this
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
                        ? 'The bar is full: ${formatCount(checkIns)} of '
                              '${formatCount(goal)} check-ins.'
                        : '${formatCount(checkIns)} of ${formatCount(goal)} '
                              'check-ins: one more fills the bar.',
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

/// One numbered step of a flow: a number (a tick when [done], a spinner
/// while [active]), a title and one sentence.
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
        : active
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.text),
          )
        : Text('$number', style: t.body(14, FontWeight.w600));
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
