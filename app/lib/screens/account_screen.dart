import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/dot_matrix.dart';
import '../widgets/gauges.dart';
import '../widgets/identicon.dart';
import '../widgets/main_tabs.dart';

/// Account: the only place the wallet shows. Address, balances, "Back up
/// key", "Import a key", and a small "Start a new round" form for whoever
/// creates rounds. Nobody has to come here to use the app.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.state, this.showBar = true});
  final AppState state;

  /// The floating tab bar (off in tests that pump the screen alone).
  final bool showBar;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _showKey = false;

  AppState get _state => widget.state;

  void _copy(String text, String said) {
    Clipboard.setData(ClipboardData(text: text));
    showMessage(context, said);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final t = context.type;
      final c = context.colors;
      if (!_state.hasWallet) return const Scaffold(body: SizedBox.shrink());
      final address = _state.address;
      return Scaffold(
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _state.refreshBalances,
                color: c.onVolt,
                backgroundColor: c.volt,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.s3,
                    Space.gutter,
                    140,
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Identicon(address: address, size: 72),
                    ),
                    const SizedBox(height: Space.s4),
                    Semantics(
                      header: true,
                      child: Text('ACCOUNT', style: t.display(56)),
                    ),
                    const SizedBox(height: Space.s4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        label: 'Copy address $address',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _copy(address, 'Address copied.'),
                          child: GlassSurface.pill(
                            child: SizedBox(
                              height: Sizes.touch,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      shortAddress(address),
                                      style: t.mono.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.copy_rounded,
                                      size: 14,
                                      color: c.text,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _Balances(state: _state),
                    const SizedBox(height: 22),
                    const SectionHeader('Back up key'),
                    const SizedBox(height: Space.s3),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CapsuleToggle(
                            title: 'Show private key',
                            detail:
                                'Anyone with this key controls this wallet.',
                            value: _showKey,
                            onChanged: (v) => setState(() => _showKey = v),
                          ),
                          if (_showKey) ...[
                            const SizedBox(height: Space.s3),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(Radii.sm),
                              ),
                              child: SelectableText(
                                _state.keyHex,
                                style: t.mono.copyWith(
                                  fontSize: 12,
                                  color: c.volt,
                                ),
                              ),
                            ),
                            const SizedBox(height: Space.s3),
                            PillButton(
                              kind: PillKind.glass,
                              height: Sizes.buttonSmall,
                              icon: Icons.copy_rounded,
                              label: 'Copy key',
                              onPressed: () =>
                                  _copy(_state.keyHex, 'Key copied.'),
                            ),
                          ],
                          const SizedBox(height: Space.s3),
                          Text(
                            'The key was made on this device and stays here. '
                            'It is the only way to open this wallet '
                            'somewhere else: clear this app or this site\'s '
                            'data without a backup and it is gone.',
                            style: t.body(12).copyWith(color: c.text2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.s3),
                    PillButton(
                      kind: PillKind.glass,
                      height: Sizes.buttonSmall,
                      icon: Icons.key_rounded,
                      label: 'Import a key',
                      onPressed: () => showAppSheet<void>(
                        context,
                        builder: (_) => ImportKeySheet(state: _state),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const SectionHeader(
                      'Start a new round',
                      trailing: 'for the round creator',
                    ),
                    const SizedBox(height: Space.s3),
                    StartRoundForm(state: _state),
                    const SizedBox(height: 22),
                    const SectionHeader('About'),
                    const SizedBox(height: Space.s3),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FlapAttribution(),
                          const SizedBox(height: Space.s2),
                          Text(
                            'A round creates its token through Flap Pool '
                            'Launch on BNB Smart Chain testnet. '
                            '${AppConfig.productName} is a hackathon project '
                            'and is not run or endorsed by Flap.',
                            style: t.body(13).copyWith(color: c.text2),
                          ),
                          const SizedBox(height: Space.s3),
                          Text(
                            'Check-ins are attested, not proven: our server '
                            'signs that a wallet moved enough on a day, from '
                            'phone health data or, in a browser, from what '
                            'the person typed. It cannot launch early, block '
                            'a launch, choose who is paid beyond signing '
                            'daily check-ins, or move funds.',
                            style: t.body(13).copyWith(color: c.text2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.showBar)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: MainTabs(current: 1),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Test USD in dot-matrix numerals over a tick gauge, and the gas below.
class _Balances extends StatelessWidget {
  const _Balances({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    const usd = AppConfig.quoteSymbol;
    // The gauge fills as the balance approaches one deposit.
    final deposit = state.deposit;
    final progress = deposit > BigInt.zero
        ? (state.usd * BigInt.from(1000) ~/ deposit).toInt() / 1000
        : (state.usd > BigInt.zero ? 1.0 : 0.0);
    return GlassCard(
      padding: const EdgeInsets.all(20),
      tint: c.volt.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Balance')),
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'BSC testnet',
                  style: t
                      .body(12, FontWeight.w600)
                      .copyWith(color: c.text2, height: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: DotMatrixText(
                    formatAmount(state.usd),
                    dot: 8,
                    gap: 2.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'test $usd',
                style: t.body(14, FontWeight.w600).copyWith(color: c.text2),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TickGauge(
            progress: math.min(progress, 1),
            ticks: 40,
            height: 20,
            label: '${formatMoney(state.usd, usd)} of test dollars',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.local_gas_station_outlined, size: 16, color: c.text2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Network fees',
                  style: t.body(13).copyWith(color: c.text2),
                ),
              ),
              Text(
                formatMoney(state.bnb, 'tBNB', maxFraction: 4),
                style: t
                    .body(13, FontWeight.w600)
                    .copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          Text(
            state.funding
                ? 'Preparing your wallet: a little test BNB is on its way.'
                : 'Test dollars and test BNB. Nothing here has real value.',
            style: t.body(12).copyWith(color: c.text2),
          ),
        ],
      ),
    );
  }
}

/// "Import a key": paste a private key to use that wallet on this device.
class ImportKeySheet extends StatefulWidget {
  const ImportKeySheet({super.key, required this.state});
  final AppState state;

  @override
  State<ImportKeySheet> createState() => _ImportKeySheetState();
}

class _ImportKeySheetState extends State<ImportKeySheet> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.importKey(_key.text);
      if (!mounted) return;
      showMessage(context, 'Wallet imported.', kind: BannerKind.success);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return SheetFrame(
      tall: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Import a key', style: t.title(30)),
          ),
          const SizedBox(height: Space.s2),
          Text(
            'Paste a private key (64 hex characters). It replaces the wallet '
            'on this device and is stored only here. Back up the current key '
            'first if you still need it.',
            style: t.body(15).copyWith(color: c.text2),
          ),
          const SizedBox(height: Space.s4),
          GlassField(
            fieldKey: const Key('import-key'),
            controller: _key,
            placeholder: '0x…',
            label: 'Private key',
            mono: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: Space.s5),
          if (_error != null) ...[
            ErrorLine(_error!),
            const SizedBox(height: Space.s3),
          ],
          PillButton(
            label: 'Import',
            busy: _busy,
            onPressed: _key.text.trim().length < 64 ? null : _import,
          ),
        ],
      ),
    );
  }
}

/// "Start a new round": name, deposit, launch pool share, check-in goal and
/// deadline. Mines the launch salt, calls `Portal.newLauncher` with the
/// CheckInLauncherFactory and shows the new round's address to copy. Making
/// it the current round is a step for whoever runs the server.
class StartRoundForm extends StatefulWidget {
  const StartRoundForm({super.key, required this.state, this.missing});
  final AppState state;

  /// The build values that are not set. Defaults to
  /// [AppConfig.missingValues]; a parameter so tests can show both cases.
  final List<String>? missing;

  @override
  State<StartRoundForm> createState() => _StartRoundFormState();
}

class _StartRoundFormState extends State<StartRoundForm> {
  final _name = TextEditingController();
  int _deposit = 1000;
  int _bps = AppConfig.defaultLiquidityBps;
  int _goal = 6;
  int _daysOpen = 7;
  bool _busy = false;
  String? _error;
  String? _launcher;

  AppState get _state => widget.state;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// How many members fill Flap's pool floor with no sponsor.
  int get _membersForFloor {
    final perMember = _deposit * _bps / 10000;
    return perMember <= 0 ? 0 : (AppConfig.launchPoolFloor / perMember).ceil();
  }

  Future<void> _start() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the round a name first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final launcher = await _state.createRound(
        name: name,
        deposit: wholeUnits(_deposit),
        liquidityBps: _bps,
        checkInGoal: _goal,
        deadline: _state.now.add(Duration(days: _daysOpen)),
      );
      if (mounted) setState(() => _launcher = launcher);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    const usd = AppConfig.quoteSymbol;
    final missing = widget.missing ?? AppConfig.missingValues;

    if (missing.isNotEmpty) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This build cannot start a round yet.',
              style: t.body(15, FontWeight.w600),
            ),
            const SizedBox(height: Space.s2),
            Text(
              'It was made without the addresses of the contracts. Missing '
              'build values:',
              style: t.body(13).copyWith(color: c.text2),
            ),
            const SizedBox(height: Space.s2),
            for (final name in missing) Text(name, style: t.mono),
          ],
        ),
      );
    }

    final launcher = _launcher;
    if (launcher != null) {
      return GlassCard(
        tint: c.volt.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('Round started'),
            const SizedBox(height: Space.s2),
            SelectableText(launcher, style: t.mono.copyWith(fontSize: 12.5)),
            const SizedBox(height: Space.s3),
            PillButton(
              height: Sizes.buttonSmall,
              icon: Icons.copy_rounded,
              label: 'Copy round address',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: launcher));
                showMessage(context, 'Round address copied.');
              },
            ),
            const SizedBox(height: Space.s3),
            Text(
              'Give this address to whoever runs the server. The app shows '
              'the round once the server is set to it.',
              style: t.body(13).copyWith(color: c.text2),
            ),
            LinkRow(
              label: 'View on BscScan testnet',
              url: '${AppConfig.explorerAddress}$launcher',
            ),
          ],
        ),
      );
    }

    Widget field(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Overline(label), const SizedBox(height: 10), child],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field(
          'Name',
          GlassField(
            fieldKey: const Key('round-name'),
            controller: _name,
            placeholder: 'Morning Movers',
            label: 'Round name',
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        field(
          'Deposit (test $usd)',
          ChipPicker<int>(
            options: const [100, 500, 1000, 2000],
            selection: _deposit,
            label: formatCount,
            onChanged: (v) => setState(() => _deposit = v),
          ),
        ),
        field(
          'Launch pool share of each deposit',
          ChipPicker<int>(
            options: const [1000, 3000, 5000, 10000],
            selection: _bps,
            label: formatBps,
            onChanged: (v) => setState(() => _bps = v),
          ),
        ),
        field(
          'Check-in goal',
          ChipPicker<int>(
            options: const [3, 6, 12, 30, 60],
            selection: _goal,
            label: (v) => '$v check-ins',
            onChanged: (v) => setState(() => _goal = v),
          ),
        ),
        field(
          'Deadline',
          ChipPicker<int>(
            options: const [1, 3, 7, 14, 30],
            selection: _daysOpen,
            label: (v) => 'In ${days(v)}',
            onChanged: (v) => setState(() => _daysOpen = v),
          ),
        ),
        CustomPaint(
          painter: _DashedBorder(c.hairline),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Summary'),
                const SizedBox(height: 10),
                Text(
                  'Members pay ${formatCount(_deposit)} $usd once: '
                  '${formatBps(_bps)} to the launch pool, '
                  '${formatBps(10000 - _bps)} to the prize. After $_goal '
                  'check-ins by everyone, anyone can launch the token. If '
                  'that has not happened in ${days(_daysOpen)}, every '
                  'deposit goes back. Flap needs '
                  '${formatCount(AppConfig.launchPoolFloor)} $usd in the '
                  'pool: $_membersForFloor members, or a sponsor.',
                  style: t.body(14).copyWith(color: c.text2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s4),
        if (_error != null) ...[
          ErrorLine(_error!),
          const SizedBox(height: Space.s3),
        ],
        PillButton(
          icon: _error != null ? Icons.refresh_rounded : Icons.bolt_rounded,
          label: _error != null ? 'Retry' : 'Start the round',
          busy: _busy,
          busyLabel: _state.funding
              ? 'Preparing your wallet…'
              : 'Starting the round…',
          onPressed: _start,
        ),
      ],
    );
  }
}

/// A dashed rounded outline, for the summary box.
class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(Radii.row),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
