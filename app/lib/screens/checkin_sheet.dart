import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/gauges.dart';

/// Opens the check-in sheet for [round] over the current screen.
Future<void> showCheckInSheet(
  BuildContext context,
  AppState state,
  Round round,
) => showAppSheet<void>(
  context,
  builder: (_) => CheckInSheet(state: state, round: round),
);

/// Today's check-in.
///
/// On a phone the sheet reads today's steps from Apple Health / Health
/// Connect and shows them against the minimum. In a browser there is no
/// health store, so it shows a number field labelled "Self-reported, testnet
/// only". Either way the steps go to the server, which answers with the
/// attester's signature; the app then sends `checkIn(dayIndex, signature)`
/// itself and shows the transaction.
///
/// The sheet is about [round] from the moment it opens until it closes: its
/// name is over the title, and the check-in is for that round whatever card
/// is in view on Home behind it.
class CheckInSheet extends StatefulWidget {
  const CheckInSheet({super.key, required this.state, required this.round});
  final AppState state;

  /// The round named on the button that opened the sheet.
  final Round round;

  @override
  State<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<CheckInSheet> {
  final _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The check-in transaction, once it is mined.
  String? _tx;

  /// Today's steps from the health store. Null while reading or when the
  /// read failed.
  int? _steps;
  bool _reading = false;

  AppState get _state => widget.state;
  bool get _phone => _state.health.available;

  /// The sheet's round as the app reads it now; as it was when the sheet
  /// opened if it has left the slider since.
  Round get _round => _state.roundOf(widget.round.id) ?? widget.round;
  bool get _pending => _state.hasPendingCheckInFor(widget.round.id);

  @override
  void initState() {
    super.initState();
    if (_phone) _read();
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final steps = await _state.health.stepsToday();
      if (mounted) setState(() => _steps = steps);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _checkIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tx = await _state.checkIn(
        selfReported: _phone ? null : int.tryParse(_typed.text.trim()) ?? 0,
        launcher: widget.round.launcher,
      );
      if (mounted) setState(() => _tx = tx);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) => PopScope(
      canPop: !_busy,
      child: SheetFrame(
        tall: false,
        palette: _tx != null ? AuroraPalette.volt : AuroraPalette.steel,
        child: _tx != null ? _doneView(context) : _form(context),
      ),
    ),
  );

  Widget _doneView(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final streak = _state.streakIn(widget.round.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.s4),
        Icon(Icons.verified_rounded, size: 44, color: c.volt),
        const SizedBox(height: Space.s3),
        RoundLabel(_round.name),
        const SizedBox(height: Space.s1),
        Text('CHECKED IN.', style: t.display(60)),
        const SizedBox(height: Space.s3),
        Text(
          'Today is on chain. You have '
          '${days(_state.daysIn(widget.round.id))} in this round'
          '${streak > 1 ? ' and a streak of $streak' : ''}. Come back '
          'tomorrow.',
          style: t.body(15).copyWith(color: c.text2),
        ),
        const SizedBox(height: Space.s4),
        GlassCard(
          radius: Radii.row,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: LinkRow(
            label: 'Transaction',
            url: '${AppConfig.explorerTx}$_tx',
            value: _tx,
          ),
        ),
        const SizedBox(height: Space.s6),
        PillButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final min = _round.minSteps;
    final pending = _pending;
    final enough = pending || !_phone || (_steps ?? 0) >= min;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoundLabel(_round.name),
        const SizedBox(height: Space.s1),
        Semantics(
          header: true,
          child: Text('Check in today', style: t.title(30)),
        ),
        const SizedBox(height: Space.s2),
        Text(
          pending
              ? 'Today\'s check-in is signed. Record it on chain to finish.'
              : 'A day counts with at least ${formatCount(min)} steps. One '
                    'check-in per day, counted in UTC.',
          style: t.body(15).copyWith(color: c.text2),
        ),
        const SizedBox(height: Space.s5),
        if (pending)
          const SizedBox.shrink()
        else if (_phone)
          _stepsCard(context, min)
        else ...[
          const Overline('Steps today'),
          const SizedBox(height: 10),
          GlassField(
            fieldKey: const Key('steps'),
            controller: _typed,
            placeholder: formatCount(min * 6),
            label: 'Steps today, self-reported',
            number: true,
            suffix: 'steps',
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: c.text2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Self-reported, testnet only',
                  style: t.body(13, FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A browser cannot read health data. The phone app reads your '
            'steps from Apple Health or Health Connect instead.',
            style: t.body(12).copyWith(color: c.text2),
          ),
        ],
        const SizedBox(height: Space.s5),
        if (_busy && _state.funding) ...[
          Text(
            'Preparing your wallet: a little test BNB for network fees is '
            'on its way.',
            style: t.body(13, FontWeight.w500),
          ),
          const SizedBox(height: Space.s3),
        ],
        if (_error != null) ...[
          ErrorLine(_error!),
          const SizedBox(height: Space.s3),
        ],
        PillButton(
          label: _error != null
              ? 'Retry'
              : pending
              ? 'Finish check-in'
              : 'Check in',
          icon: _error != null ? Icons.refresh_rounded : Icons.check_rounded,
          busy: _busy,
          busyLabel: _state.funding
              ? 'Preparing your wallet…'
              : _pending
              ? 'Recording on chain…'
              : 'Checking your steps…',
          onPressed: enough && !_reading ? _checkIn : null,
        ),
      ],
    );
  }

  /// Phone: today's steps as a big figure against the minimum.
  Widget _stepsCard(BuildContext context, int min) {
    final t = context.type;
    final c = context.colors;
    final steps = _steps;
    final enough = (steps ?? 0) >= min;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('Steps today'),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              steps == null ? '–' : formatCount(steps),
                              style: t.metric(40),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'steps',
                          style: t
                              .body(14, FontWeight.w500)
                              .copyWith(color: c.text3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: enough ? c.volt : Colors.white.withValues(alpha: 0.1),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  _reading
                      ? 'Reading…'
                      : enough
                      ? 'Ready'
                      : 'Keep going',
                  style: t
                      .body(12, FontWeight.w600)
                      .copyWith(color: enough ? c.onVolt : c.text, height: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          MarkerScale(value: (steps ?? 0) / (min <= 0 ? 1 : min)),
          Row(
            children: [
              Text('0', style: t.body(11).copyWith(color: c.text2)),
              const Spacer(),
              Text(
                '${formatCount(min)} steps to check in',
                style: t.body(11).copyWith(color: c.text2),
              ),
            ],
          ),
          if (!_reading && !enough) ...[
            const SizedBox(height: Space.s3),
            PillButton(
              kind: PillKind.glass,
              height: Sizes.buttonSmall,
              icon: Icons.refresh_rounded,
              label: 'Read my steps again',
              onPressed: _read,
            ),
          ],
        ],
      ),
    );
  }
}
