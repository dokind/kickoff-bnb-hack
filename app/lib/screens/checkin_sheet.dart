import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/health_service.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/pot.dart';
import '../widgets/common.dart';
import '../widgets/gauges.dart';
import 'health_sheet.dart';

/// Opens the check-in sheet for [round] over the current screen. With
/// [then], once the day is on chain the sheet shows the new share for a
/// moment ([CheckInSheet.linger]), closes itself and calls [then] (Home
/// opens Your round); its button, [thenLabel], does the same at once.
Future<void> showCheckInSheet(
  BuildContext context,
  AppState state,
  Round round, {
  VoidCallback? then,
  String thenLabel = 'See your round',
}) => showAppSheet<void>(
  context,
  builder: (_) => CheckInSheet(
    state: state,
    round: round,
    then: then,
    thenLabel: thenLabel,
  ),
);

/// Today's check-in.
///
/// On a phone the sheet reads today's steps from Apple Health / Health
/// Connect and shows them against the minimum. When the read finds nothing
/// (on an iPhone that is also what a read the person did not allow looks
/// like) or fails, it does not dead-end: "Sync again", "Fix in Health"
/// (the Health sheet) and, on this testnet build, "Type today's steps
/// instead". In a browser there is no health store, so it shows a number
/// field labelled "Self-reported, testnet only"; typed steps go as source
/// "self" from a phone too. Either way the steps go to the server, which
/// answers with the
/// attester's signature; the app then sends `checkIn(dayIndex, signature)`
/// itself and shows the transaction.
///
/// The sheet is about [round] from the moment it opens until it closes: its
/// name is over the title, and the check-in is for that round whatever card
/// is in view on Home behind it.
class CheckInSheet extends StatefulWidget {
  const CheckInSheet({
    super.key,
    required this.state,
    required this.round,
    this.then,
    this.thenLabel = 'See your round',
  });
  final AppState state;

  /// The round named on the button that opened the sheet.
  final Round round;

  /// Called after the sheet has closed itself on a recorded check-in.
  final VoidCallback? then;
  final String thenLabel;

  /// How long the new share stays in view before the sheet closes itself.
  static const linger = Duration(milliseconds: 2600);

  @override
  State<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<CheckInSheet> {
  final _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The check-in transaction, once it is mined.
  String? _tx;

  /// "Your share went from 25% to 40%.", once the day is on chain and the
  /// round has been read again.
  String? _shareMoved;
  Timer? _leave;

  /// The last read of the health store. Null before the first read ends.
  StepsRead? _last;
  bool _reading = false;

  /// On a phone: the person chose to type today's steps (source "self").
  bool _typing = false;

  late final AppLifecycleListener _life;

  AppState get _state => widget.state;
  HealthService get _health => _state.health;
  bool get _phone => _health.available;

  /// The steps are a number the person types: always in a browser, on a
  /// phone when they chose to.
  bool get _typedMode => !_phone || _typing;

  /// Today's steps from the health store. Null while reading or when the
  /// read found none.
  int? get _steps => _last?.isOk == true ? _last!.steps : null;

  /// The sheet's round as the app reads it now; as it was when the sheet
  /// opened if it has left the slider since.
  Round get _round => _state.roundOf(widget.round.id) ?? widget.round;
  bool get _pending => _state.hasPendingCheckInFor(widget.round.id);

  @override
  void initState() {
    super.initState();
    // Back from the Health app with nothing read yet: read again, without
    // asking. Coming back to the app must never bring up a permission
    // screen (on Android each refusal counts towards the limit of two), and
    // while the Health sheet is open it reads again itself.
    _life = AppLifecycleListener(
      onResume: () {
        if (mounted &&
            _phone &&
            !_typing &&
            !_reading &&
            !_healthOpen &&
            _tx == null) {
          if (!(_last?.isOk ?? false)) _read(ask: false);
        }
      },
    );
    if (_phone) _firstRead();
  }

  /// The read when the sheet opens: asks for access only if the app has
  /// never asked on this device. After that, asking again is a button.
  Future<void> _firstRead() async {
    setState(() => _reading = true);
    final asked = await _health.askedBefore();
    if (!mounted) return;
    await _read(ask: !asked);
  }

  @override
  void dispose() {
    _leave?.cancel();
    _life.dispose();
    _typed.dispose();
    super.dispose();
  }

  /// Closes the sheet and goes on to [CheckInSheet.then].
  void _goOn() {
    _leave?.cancel();
    final then = widget.then;
    if (!mounted || then == null) return;
    Navigator.of(context).pop();
    then();
  }

  /// This wallet's days and all check-ins of the sheet's round, counted
  /// the way THE PRIZE and Your round count them ([Pot]), when the state is
  /// reading that round (it is the selected one).
  (int, int)? _shareNow() {
    final id = widget.round.id;
    if (_state.selected != id || !_state.yourDaysKnown) return null;
    final days = _state.daysIn(id);
    final pot = Pot.build(
      prize: BigInt.zero,
      totalCheckIns: _state.totalCheckIns,
      memberCount: 0,
      members: [for (final m in _state.members) (m.address, m.daysOf)],
      you: _state.address,
      isMember: true,
      yourDays: days,
    );
    return (days, pot.total);
  }

  /// Reads today's steps. [ask] is true when the person pressed a button
  /// that reads (and may ask for access).
  Future<void> _read({bool ask = true}) async {
    setState(() {
      _reading = true;
      _error = null;
    });
    final read = await _health.readSteps(ask: ask);
    if (mounted) {
      setState(() {
        _last = read;
        _reading = false;
      });
    }
  }

  /// The Health sheet is open over this one.
  bool _healthOpen = false;

  Future<void> _fixInHealth() async {
    _healthOpen = true;
    try {
      await showHealthSheet(
        context,
        _health,
        initial: _last,
        onRead: (read) {
          if (mounted) setState(() => _last = read);
        },
      );
    } finally {
      _healthOpen = false;
    }
  }

  void _typeInstead(bool typing) => setState(() {
    _typing = typing;
    _error = null;
  });

  Future<void> _checkIn() async {
    // An empty field is said here and nothing is sent: the server would only
    // answer "0 steps".
    if (_typedMode &&
        !_pending &&
        int.tryParse(_typed.text.trim().replaceAll(',', '')) == null) {
      setState(() => _error = 'Type today\'s steps first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final before = _shareNow();
    try {
      final tx = await _state.checkIn(
        selfReported: _typedMode
            ? int.tryParse(_typed.text.trim().replaceAll(',', '')) ?? 0
            : null,
        launcher: widget.round.launcher,
      );
      final after = _shareNow();
      if (mounted) {
        setState(() {
          _tx = tx;
          _shareMoved = before == null || after == null
              ? null
              : shareChangeSentence(before.$1, before.$2, after.$1, after.$2);
        });
        if (widget.then != null) _leave = Timer(CheckInSheet.linger, _goOn);
      }
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
        if (_shareMoved != null) ...[
          const SizedBox(height: Space.s3),
          Semantics(
            container: true,
            liveRegion: true,
            child: Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 20, color: c.volt),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text(
                    _shareMoved!,
                    key: const Key('checkin-share-moved'),
                    style: t.body(16, FontWeight.w700).copyWith(color: c.volt),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        if (widget.then != null)
          PillButton(
            kind: PillKind.volt,
            icon: Icons.arrow_forward_rounded,
            label: widget.thenLabel,
            onPressed: _goOn,
          )
        else
          PillButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final min = _round.minSteps;
    final pending = _pending;
    final enough = pending || _typedMode || (_steps ?? 0) >= min;
    final read = _last;
    final nothingRead = _phone && !_reading && read != null && !read.isOk;

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
        else if (!_typedMode && nothingRead)
          _noStepsCard(context, read)
        else if (!_typedMode)
          _stepsCard(context, min)
        else ...[
          const Overline('Steps today'),
          const SizedBox(height: 10),
          GlassField(
            fieldKey: const Key('steps'),
            controller: _typed,
            placeholder: 'Type today\'s steps',
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
            _phone
                ? 'Typed steps count on this testnet build only. '
                      '${_health.storeName} is read when it has steps.'
                : 'A browser cannot read health data. The phone app reads '
                      'your steps from Apple Health or Health Connect '
                      'instead.',
            style: t.body(12).copyWith(color: c.text2),
          ),
          if (_phone) ...[
            const SizedBox(height: Space.s1),
            _QuietLink(
              key: const Key('checkin-use-health'),
              label: 'Read ${_health.storeName} instead',
              onPressed: () {
                _typeInstead(false);
                _read();
              },
            ),
          ],
        ],
        if (!pending) ...[
          const SizedBox(height: Space.s3),
          // Said here, where the steps are sent, on the web and on a phone
          // (a browser skips the onboarding step that used to say it).
          Row(
            key: const Key('checkin-attested'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: c.text2,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your step count goes to our server, which signs the day: '
                  'check-ins are attested, not proven. Only the day goes on '
                  'chain.',
                  style: t.body(12).copyWith(color: c.text2),
                ),
              ),
            ],
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
              ? 'Try again'
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
              Text('0', style: t.body(12).copyWith(color: c.text2)),
              const Spacer(),
              Text(
                '${formatCount(min)} steps to check in',
                style: t.body(12).copyWith(color: c.text2),
              ),
            ],
          ),
          if (!_reading && !enough) ...[
            const SizedBox(height: Space.s3),
            PillButton(
              key: const Key('checkin-sync'),
              kind: PillKind.glass,
              height: Sizes.buttonSmall,
              icon: Icons.sync_rounded,
              label: 'Sync again',
              onPressed: _read,
            ),
          ],
        ],
      ),
    );
  }

  /// Phone: the read found no steps, or failed. Never a dead end: read
  /// again, fix it in the Health sheet, or type the steps (testnet only).
  /// An iPhone cannot tell an app that reading was turned off, so this
  /// never says it was.
  Widget _noStepsCard(BuildContext context, StepsRead read) {
    final t = context.type;
    final c = context.colors;
    final name = _health.storeName;
    final apple = _health.isAppleHealth;
    final (String title, String text) = switch (read.result) {
      StepsResult.notInstalled => (
        'Health Connect is not on this phone.',
        'Install it to read your steps, or type them for now.',
      ),
      StepsResult.error => (
        'No steps from $name today.',
        '$name did not answer. Try again in a moment.',
      ),
      _ => (
        'No steps from $name today.',
        apple
            ? 'No steps came from Apple Health. If you turned access off, '
                  'turn it on in the Health app.'
            : 'No steps came from Health Connect. If you turned access off, '
                  'allow Steps in Health Connect.',
      ),
    };
    return GlassCard(
      key: const Key('checkin-no-steps'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    read.result == StepsResult.error
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    size: 20,
                    color: c.text2,
                  ),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.body(15, FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(text, style: t.body(13).copyWith(color: c.text2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
          PillButton(
            key: const Key('checkin-sync'),
            kind: PillKind.glass,
            height: Sizes.buttonSmall,
            icon: Icons.sync_rounded,
            label: 'Sync again',
            onPressed: _read,
          ),
          const SizedBox(height: Space.s2),
          PillButton(
            key: const Key('checkin-fix'),
            kind: PillKind.glass,
            height: Sizes.buttonSmall,
            icon: Icons.favorite_border_rounded,
            label: apple ? 'Fix in Health' : 'Fix in Health Connect',
            onPressed: _fixInHealth,
          ),
          const SizedBox(height: Space.s1),
          _QuietLink(
            key: const Key('checkin-type-instead'),
            label: 'Type today\'s steps instead',
            onPressed: () => _typeInstead(true),
          ),
        ],
      ),
    );
  }
}

/// A quiet text action, at least 44 high, read as a button.
class _QuietLink extends StatelessWidget {
  const _QuietLink({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Center(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.touch),
          foregroundColor: c.text2,
        ),
        child: Text(
          label,
          style: t
              .body(14, FontWeight.w500)
              .copyWith(
                color: c.text2,
                decoration: TextDecoration.underline,
                decorationColor: c.text2,
              ),
        ),
      ),
    );
  }
}
