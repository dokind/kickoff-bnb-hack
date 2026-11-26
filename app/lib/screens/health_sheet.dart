import 'package:flutter/material.dart';

import '../config.dart';
import '../services/health_service.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Opens the Health sheet for [health] over the current screen. [initial]
/// is the last read the opener has, shown until the sheet reads again;
/// [onRead] is told every read the sheet makes, so the opener can show the
/// same steps when the sheet closes.
Future<void> showHealthSheet(
  BuildContext context,
  HealthService health, {
  StepsRead? initial,
  ValueChanged<StepsRead>? onRead,
}) => showAppSheet<void>(
  context,
  builder: (_) => HealthSheet(health: health, initial: initial, onRead: onRead),
);

/// Apple Health (Health Connect on Android): what the app reads, the state
/// now, and the way to fix it from inside the app.
///
/// It says in plain words that the app reads today's step count and nothing
/// else, and writes nothing. Then the state of the last read, and the
/// actions that fit it: "Connect Apple Health" the first time (the system
/// asks), "Sync again" after that, and "Open the Health app" with the path
/// to the switch, since on an iPhone only the person can turn access back
/// on. On Android: "Open Health Connect", or "Install Health Connect" where
/// it is missing.
///
/// An iPhone never tells an app whether reading was allowed, so a read of
/// nothing is never called "denied" here. When the person comes back from
/// the Health app the sheet reads again by itself.
class HealthSheet extends StatefulWidget {
  const HealthSheet({
    super.key,
    required this.health,
    this.initial,
    this.onRead,
  });

  final HealthService health;
  final StepsRead? initial;
  final ValueChanged<StepsRead>? onRead;

  @override
  State<HealthSheet> createState() => _HealthSheetState();
}

class _HealthSheetState extends State<HealthSheet> {
  /// Null until the storage answers.
  bool? _asked;
  StepsRead? _read;
  bool _reading = false;

  /// The Health app (or the store) was opened from here: read again when
  /// the app comes back.
  bool _away = false;

  /// One sentence when the Health app could not be opened.
  String? _note;

  late final AppLifecycleListener _life;

  HealthService get _health => widget.health;
  bool get _apple => _health.isAppleHealth;
  String get _name => _health.storeName;

  @override
  void initState() {
    super.initState();
    _read = widget.initial;
    _life = AppLifecycleListener(onResume: _back);
    _load();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final asked = await _health.askedBefore();
    if (!mounted) return;
    setState(() => _asked = asked || (_read?.isOk ?? false));
    // Asked before: read now, so the state shown is today's. Without
    // asking: opening this sheet must never bring up a permission screen
    // (on Android each refusal counts towards the limit of two).
    if (asked && widget.initial == null) await _sync(ask: false);
  }

  void _back() {
    if (!_away || !mounted) return;
    _away = false;
    _sync(ask: false);
  }

  /// Reads today's steps. [ask] is true only when the person pressed a
  /// button that asks for access.
  Future<void> _sync({bool ask = true}) async {
    setState(() {
      _reading = true;
      _note = null;
    });
    final read = await _health.readSteps(ask: ask);
    if (!mounted) return;
    widget.onRead?.call(read);
    setState(() {
      _read = read;
      _reading = false;
      _asked = true;
    });
  }

  Future<void> _connect() async {
    setState(() => _reading = true);
    await _health.connect();
    if (!mounted) return;
    // connect() has just asked: read without asking a second time.
    await _sync(ask: false);
  }

  Future<void> _openSettings() async {
    setState(() => _note = null);
    _away = true;
    final opened = await _health.openSettings();
    if (!mounted) return;
    if (!opened) {
      _away = false;
      setState(
        () => _note = _apple
            ? 'The Health app did not open. Open it yourself and follow the '
                  'steps below.'
            : 'Health Connect did not open. Open it from Settings and follow '
                  'the steps below.',
      );
    } else if (!_apple) {
      // Android answers in place: the permission screen has closed, so
      // read without bringing it up again.
      _away = false;
      await _sync(ask: false);
    }
  }

  Future<void> _install() async {
    _away = true;
    await _health.installHealthConnect();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final read = _read;
    final missing = read?.result == StepsResult.notInstalled;
    final firstTime = _asked == false && !(read?.isOk ?? false);
    return SheetFrame(
      tall: false,
      palette: AuroraPalette.ink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(_name, style: t.title(30))),
          const SizedBox(height: Space.s2),
          Text(
            '${AppConfig.productName} reads one number from $_name: '
            'today\'s step count. It is sent to our server only when you '
            'check in.',
            style: t.body(15).copyWith(color: c.text2),
          ),
          const SizedBox(height: Space.s4),
          GlassCard(
            key: const Key('health-reads'),
            padding: EdgeInsets.zero,
            radius: Radii.row,
            child: const Column(
              children: [
                IconRow(
                  icon: Icons.directions_walk_rounded,
                  title: 'Today\'s step count',
                  text: 'Read when you check in or sync.',
                ),
                IconRow(
                  icon: Icons.visibility_off_outlined,
                  title: 'Nothing else',
                  text: 'No heart rate, location, workouts or other data.',
                ),
                IconRow(
                  icon: Icons.edit_off_rounded,
                  title: 'Nothing written',
                  text: 'The app never adds to or changes your health data.',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
          _status(context),
          const SizedBox(height: Space.s4),
          if (_note != null) ...[
            ErrorLine(_note!),
            const SizedBox(height: Space.s3),
          ],
          if (_health.store != HealthStore.none) ...[
            if (missing)
              PillButton(
                key: const Key('health-install'),
                icon: Icons.download_rounded,
                label: 'Install Health Connect',
                onPressed: _reading ? null : _install,
              )
            else if (firstTime)
              PillButton(
                key: const Key('health-connect'),
                kind: PillKind.volt,
                icon: Icons.favorite_rounded,
                label: 'Connect $_name',
                busy: _reading,
                busyLabel: 'Connecting…',
                onPressed: _asked == null ? null : _connect,
              )
            else
              PillButton(
                key: const Key('health-sync'),
                icon: Icons.sync_rounded,
                label: 'Sync again',
                busy: _reading,
                busyLabel: 'Reading your steps…',
                onPressed: _sync,
              ),
            if (missing) ...[
              const SizedBox(height: Space.s3),
              PillButton(
                key: const Key('health-sync'),
                kind: PillKind.glass,
                height: Sizes.buttonSmall,
                icon: Icons.sync_rounded,
                label: 'Sync again',
                busy: _reading,
                busyLabel: 'Reading your steps…',
                onPressed: _sync,
              ),
            ],
            if (!firstTime && !missing) ...[
              const SizedBox(height: Space.s3),
              PillButton(
                key: const Key('health-open'),
                kind: PillKind.glass,
                height: Sizes.buttonSmall,
                icon: Icons.open_in_new_rounded,
                label: _apple ? 'Open the Health app' : 'Open Health Connect',
                onPressed: _reading ? null : _openSettings,
              ),
              const SizedBox(height: Space.s3),
              _path(context),
            ],
          ],
        ],
      ),
    );
  }

  /// The state of the last read, in one line and one sentence.
  Widget _status(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final read = _read;
    final (IconData icon, Color tone, String title, String text) = switch ((
      _reading,
      read?.result,
    )) {
      (true, _) => (
        Icons.sync_rounded,
        c.text2,
        'Reading…',
        'Asking $_name for today\'s steps.',
      ),
      (_, StepsResult.ok) => (
        Icons.check_circle_rounded,
        c.volt,
        'Connected',
        '${formatCount(read!.steps)} steps today.',
      ),
      (_, StepsResult.noData) => (
        Icons.info_outline_rounded,
        c.text,
        'No steps today',
        _apple
            ? 'No steps came from Apple Health. If you turned access off, '
                  'turn it on in the Health app.'
            : 'No steps came from Health Connect. If you turned access off, '
                  'allow Steps in Health Connect.',
      ),
      (_, StepsResult.notInstalled) => (
        Icons.download_rounded,
        c.text,
        'Health Connect is not on this phone',
        'Install it from Google Play, then come back here.',
      ),
      (_, StepsResult.error) => (
        Icons.warning_amber_rounded,
        c.danger,
        '$_name did not answer',
        'Try again in a moment.',
      ),
      (_, StepsResult.unavailable) => (
        Icons.phonelink_off_rounded,
        c.text2,
        'No health data here',
        'This device cannot read steps. Type them when you check in.',
      ),
      (_, null) => (
        Icons.link_off_rounded,
        c.text2,
        _asked == true ? 'Not read yet' : 'Not connected yet',
        _asked == true
            ? 'Sync to read today\'s steps.'
            : 'Connect once. You can change it at any time in '
                  '${_apple ? 'the Health app' : 'Health Connect'}.',
      ),
    };
    return Semantics(
      key: const Key('health-status'),
      container: true,
      liveRegion: true,
      child: GlassCard(
        radius: Radii.row,
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: tone),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Overline('Now'),
                  const SizedBox(height: 2),
                  Text(title, style: t.body(15, FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(text, style: t.body(13).copyWith(color: c.text2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Where the switch is, under "Open the Health app".
  Widget _path(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final app = AppConfig.productName;
    final steps = _apple
        ? ['Tap your profile, top right.', 'Apps, then $app.', 'Turn on Steps.']
        : ['App permissions.', app, 'Allow Steps.'];
    return Column(
      key: const Key('health-path'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _apple ? 'In the Health app' : 'In Health Connect',
          style: t.body(13, FontWeight.w600),
        ),
        const SizedBox(height: Space.s2),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: t.body(12, FontWeight.w600).copyWith(height: 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[i],
                      style: t.body(13).copyWith(color: c.text2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_apple) ...[
          const SizedBox(height: Space.s1),
          Text(
            'Or in Settings: Health, then Data Access & Devices, then $app.',
            style: t.body(12).copyWith(color: c.text2),
          ),
        ],
      ],
    );
  }
}
