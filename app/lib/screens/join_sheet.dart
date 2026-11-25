import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Opens the join sheet over the current screen.
Future<void> showJoinSheet(BuildContext context, AppState state) =>
    showAppSheet<void>(context, builder: (_) => JoinSheet(state: state));

/// Joining a round: what the deposit is and where it goes, then two real
/// steps with their progress.
///   1. "Get test dollars": the wallet mints the deposit in Flap's free test
///      USD to itself. On mainnet this step is paying with a stablecoin.
///   2. "Pay deposit": approve, then `join()`.
/// Before the first transaction the sheet waits for the faucet's gas to
/// arrive and says "Preparing your wallet".
class JoinSheet extends StatefulWidget {
  const JoinSheet({super.key, required this.state});
  final AppState state;

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

  AppState get _state => widget.state;

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

  Future<void> _getDollars() =>
      _run(() => _state.getTestDollars(_state.deposit));

  Future<void> _pay() async {
    setState(() => _paying = true);
    await _run(() async {
      await _state.payDeposit();
      if (mounted) setState(() => _done = true);
    });
    if (mounted) setState(() => _paying = false);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Icon(Icons.verified_rounded, size: 44, color: c.volt),
        const SizedBox(height: Space.s3),
        Text('YOU\'RE IN.', style: t.display(60)),
        const SizedBox(height: Space.s3),
        Text(
          '${formatMoney(_state.deposit, AppConfig.quoteSymbol)} is in the '
          'round\'s contract. Check in every day you move: each day is one '
          'more part of the prize and of the token.',
          style: t.body(15).copyWith(color: c.text2),
        ),
        const Spacer(),
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
    final round = _state.round;
    if (round == null) return const SizedBox.shrink();
    final deposit = _state.deposit;
    const usd = AppConfig.quoteSymbol;
    final hasDollars = _paying || _state.usd >= deposit;
    final preparing = _busy && _state.funding;
    final toPool =
        deposit * BigInt.from(round.liquidityBps) ~/ BigInt.from(10000);
    final toPrize = deposit - toPool;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Pay the deposit', style: t.title(30)),
        ),
        const SizedBox(height: Space.s4),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              GlassCard(
                radius: 24,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    KeyValueRow('Deposit', formatMoney(deposit, usd)),
                    KeyValueRow(
                      'To the prize',
                      '${formatMoney(toPrize, usd)} · '
                          '${formatBps(10000 - round.liquidityBps)}',
                    ),
                    KeyValueRow(
                      'To the launch pool',
                      '${formatMoney(toPool, usd)} · '
                          '${formatBps(round.liquidityBps)}',
                    ),
                    const KeyValueRow(
                      'If the bar fills',
                      'You share the prize and the token by your days',
                    ),
                    KeyValueRow(
                      'If it has not by ${formatDate(round.deadline)}',
                      'Full deposit back',
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
                    formatMoney(_state.usd, usd),
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
                    'Approves, then pays ${formatMoney(deposit, usd)} into '
                    'the round\'s contract.',
                done: false,
                active: _busy && hasDollars && !preparing,
              ),
            ],
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
            label: _error != null ? 'Retry' : 'Get test dollars',
            icon: _error != null ? Icons.refresh_rounded : Icons.water_drop,
            busy: _busy,
            busyLabel: preparing
                ? 'Preparing your wallet…'
                : 'Getting test dollars…',
            onPressed: _getDollars,
          )
        else
          PillButton(
            kind: PillKind.volt,
            label: _error != null
                ? 'Retry'
                : 'Pay deposit · ${formatMoney(deposit, usd)}',
            icon: _error != null ? Icons.refresh_rounded : Icons.lock_rounded,
            busy: _busy,
            busyLabel: preparing ? 'Preparing your wallet…' : 'Confirming…',
            onPressed: _pay,
          ),
      ],
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
