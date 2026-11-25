import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/dot_matrix.dart';
import '../widgets/identicon.dart';
import '../widgets/main_tabs.dart';
import '../widgets/tab_bar.dart';

/// Wallet (`/account`, also `/wallet`): your money and your key, and nothing
/// else. The balance is the hero. Under it, one list of four rows: the
/// address (press to copy), "Back up your key", "Use another wallet" and
/// "About", the last three each a sheet. Nobody has to come here to use the
/// app. The only word about rounds is the money in them ("In rounds", under
/// the balance, when this wallet is in an open round): starting one and
/// opening an invite link are behind the "+" on the tab bar.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.state, this.showBar = true});
  final AppState state;

  /// The floating tab bar (off in tests that pump the screen alone).
  final bool showBar;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final t = context.type;
      final c = context.colors;
      if (!state.hasWallet) return const Scaffold(body: SizedBox.shrink());
      final address = state.address;
      // The list ends above the floating bar, so its last row can be read
      // and pressed when scrolled to the end.
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      final underList = showBar
          ? safeBottom + _barGap + FloatingTabBar.height + Space.s6
          : safeBottom + Space.s6;
      return Scaffold(
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: state.refreshBalances,
                color: c.onVolt,
                backgroundColor: c.volt,
                child: ListView(
                  key: const Key('wallet-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.s5,
                    Space.gutter,
                    underList,
                  ),
                  children: [
                    Semantics(
                      header: true,
                      child: Text('WALLET', style: t.display(56)),
                    ),
                    const SizedBox(height: Space.s5),
                    BalanceCard(state: state),
                    const SizedBox(height: Space.s5),
                    GlassCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          ActionRow(
                            key: const Key('wallet-address'),
                            leading: Identicon(address: address, size: 32),
                            title: 'Address',
                            value: shortAddress(address),
                            trailingIcon: Icons.copy_rounded,
                            semanticLabel: 'Copy address $address',
                            last: false,
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: address));
                              showMessage(context, 'Address copied.');
                            },
                          ),
                          ActionRow(
                            key: const Key('wallet-backup'),
                            icon: Icons.key_rounded,
                            title: 'Back up your key',
                            detail:
                                'The only way to open this wallet on another '
                                'device.',
                            last: false,
                            onPressed: () => showAppSheet<void>(
                              context,
                              builder: (_) => BackupKeySheet(state: state),
                            ),
                          ),
                          ActionRow(
                            key: const Key('wallet-import'),
                            icon: Icons.swap_horiz_rounded,
                            title: 'Use another wallet',
                            detail:
                                'Replace this wallet with a key you already '
                                'have.',
                            last: false,
                            onPressed: () => showAppSheet<void>(
                              context,
                              builder: (_) => ImportKeySheet(state: state),
                            ),
                          ),
                          ActionRow(
                            key: const Key('wallet-about'),
                            icon: Icons.info_outline_rounded,
                            title: 'About',
                            detail: 'How check-ins are verified, and Flap.',
                            onPressed: () => showAppSheet<void>(
                              context,
                              builder: (_) => const AboutSheet(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showBar)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _barGap),
                    child: MainTabs(current: MainTabs.wallet, state: state),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  /// Between the floating bar and the bottom of the screen.
  static const double _barGap = 6;
}

/// The balance: test USD in dot-matrix numerals, the test BNB for network
/// fees under it, the deposits in open rounds, one note that none of it is
/// real money, the wallet on BscScan, and "Get test dollars", which mints free test USD to this wallet the way the join
/// sheet's first step does ([AppState.getTestDollars]).
class BalanceCard extends StatefulWidget {
  const BalanceCard({super.key, required this.state});
  final AppState state;

  @override
  State<BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<BalanceCard> {
  bool _busy = false;
  String? _error;

  AppState get _state => widget.state;

  /// One deposit of the round in view on Home; 1,000 when there is none.
  BigInt get _amount =>
      _state.deposit > BigInt.zero ? _state.deposit : wholeUnits(1000);

  Future<void> _getDollars() async {
    final amount = _amount;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _state.getTestDollars(amount);
      if (mounted) {
        showMessage(
          context,
          '${formatAmount(amount)} test ${AppConfig.quoteSymbol} added.',
          kind: BannerKind.success,
        );
      }
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
    final preparing = _busy && _state.funding;
    final inRounds = openRoundsJoined(_state);
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
                    formatAmount(_state.usd),
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
          const SizedBox(height: Space.s5),
          Row(
            children: [
              Icon(Icons.local_gas_station_outlined, size: 16, color: c.text2),
              const SizedBox(width: 6),
              Expanded(
                // The amount at the right; under the label when large text
                // on a narrow screen leaves no room beside it.
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: Space.s2,
                  children: [
                    Text(
                      'Network fees',
                      style: t.body(13).copyWith(color: c.text2),
                    ),
                    Text(
                      formatMoney(_state.bnb, 'test BNB', maxFraction: 4),
                      style: t
                          .body(13, FontWeight.w600)
                          .copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (inRounds.isNotEmpty) ...[
            const SizedBox(height: Space.s3),
            _InRounds(state: _state, rounds: inRounds),
          ],
          const SizedBox(height: Space.s3),
          Text(
            _state.funding
                ? 'Preparing your wallet: a little test BNB is on its way.'
                : 'Test money on BSC testnet. It has no real value.',
            style: t.body(12).copyWith(color: c.text2),
          ),
          const SizedBox(height: Space.s2),
          LinkRow(
            key: const Key('wallet-bscscan'),
            label: 'View on BscScan',
            url: '${AppConfig.explorerAddress}${_state.address}',
          ),
          const SizedBox(height: Space.s2),
          if (_error != null) ...[
            ErrorLine(_error!),
            const SizedBox(height: Space.s3),
          ],
          PillButton(
            kind: PillKind.glass,
            height: Sizes.buttonSmall,
            icon: _error != null ? Icons.refresh_rounded : Icons.water_drop,
            label: _error != null ? 'Try again' : 'Get test dollars',
            busy: _busy,
            busyLabel: preparing
                ? 'Preparing your wallet…'
                : 'Getting test dollars…',
            onPressed: _getDollars,
          ),
        ],
      ),
    );
  }
}

/// The open rounds (not launched, deadline not passed) this wallet has paid
/// the deposit of, as the state knows them: the rounds on Home's slider
/// and the set of rounds it is a member of. A launched round's deposit has
/// left its contract; an ended one's is waiting as a refund.
List<Round> openRoundsJoined(AppState state) => [
  for (final r in state.rounds)
    if (state.isMemberOf(r.launcher) &&
        !r.launched &&
        !(r.id == state.selected && state.launched) &&
        !state.now.isAfter(r.deadline))
      r,
];

/// "In rounds: 1,500 test USD" and the rounds' names: the deposits this
/// wallet has in open rounds, which are not in the balance above.
class _InRounds extends StatelessWidget {
  const _InRounds({required this.state, required this.rounds});
  final AppState state;
  final List<Round> rounds;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final total = rounds.fold<BigInt>(
      BigInt.zero,
      (sum, r) => sum + state.depositOf(r.id),
    );
    return Row(
      key: const Key('wallet-in-rounds'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.lock_outline_rounded, size: 16, color: c.text2),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'In rounds: ${formatTestUsd(total)}',
                style: t
                    .body(13, FontWeight.w600)
                    .copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              Text(
                rounds.map((r) => r.name).join(', '),
                style: t.body(13).copyWith(color: c.text2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Back up your key": what the key is, then a switch that shows it and a
/// button that copies it. The key is hidden again every time the sheet
/// opens. It is never written anywhere but the screen and, when asked, the
/// clipboard.
class BackupKeySheet extends StatefulWidget {
  const BackupKeySheet({super.key, required this.state});
  final AppState state;

  @override
  State<BackupKeySheet> createState() => _BackupKeySheetState();
}

class _BackupKeySheetState extends State<BackupKeySheet> {
  /// Starts hidden with every new sheet.
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return SheetFrame(
      tall: false,
      // Sentences to read, so the darker palette: the quiet text keeps its
      // contrast across the whole sheet.
      palette: AuroraPalette.ink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Back up your key', style: t.title(30)),
          ),
          const SizedBox(height: Space.s2),
          Text(
            // True for a key made here and for one pasted in: it says where
            // the app keeps it, not where it came from.
            'This key is the wallet. The app keeps it on this device and '
            'nowhere else. If you delete the app or clear this site\'s data '
            'without a copy, the wallet is gone.',
            style: t.body(15).copyWith(color: c.text2),
          ),
          const SizedBox(height: Space.s4),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            radius: Radii.row,
            child: CapsuleToggle(
              key: const Key('backup-show'),
              title: 'Show key',
              detail: 'Anyone who sees it can take what is in this wallet.',
              value: _show,
              onChanged: (v) => setState(() => _show = v),
            ),
          ),
          if (_show) ...[
            const SizedBox(height: Space.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: SelectableText(
                widget.state.keyHex,
                key: const Key('backup-key'),
                style: t.mono.copyWith(fontSize: 12, color: c.volt),
              ),
            ),
            const SizedBox(height: Space.s4),
            PillButton(
              icon: Icons.copy_rounded,
              label: 'Copy key',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.state.keyHex));
                showMessage(context, 'Key copied.');
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// "Use another wallet": paste a private key to use that wallet on this
/// device in place of the one it has.
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
      showMessage(context, 'Wallet replaced.', kind: BannerKind.success);
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
      palette: AuroraPalette.ink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Use another wallet', style: t.title(30)),
          ),
          const SizedBox(height: Space.s2),
          Text(
            'Paste a private key (64 hex characters). It replaces the wallet '
            'on this device. The app keeps it on this device and nowhere '
            'else. Back up the current key first if you still need it.',
            style: t.body(15).copyWith(color: c.text2),
          ),
          const SizedBox(height: Space.s4),
          const Overline('Private key'),
          const SizedBox(height: 10),
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
            label: 'Replace wallet',
            busy: _busy,
            busyLabel: 'Replacing the wallet…',
            onPressed: _key.text.trim().length < 64 ? null : _import,
          ),
        ],
      ),
    );
  }
}

/// "About": Flap's attribution, what the project is, and what a check-in
/// does and does not prove.
class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return SheetFrame(
      tall: false,
      palette: AuroraPalette.ink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('About', style: t.title(30))),
          const SizedBox(height: Space.s4),
          const FlapAttribution(),
          const SizedBox(height: Space.s2),
          Text(
            'A round creates its token through Flap Pool Launch on BNB '
            'Smart Chain testnet. ${AppConfig.productName} is a hackathon '
            'project and is not run or endorsed by Flap.',
            style: t.body(14).copyWith(color: c.text2),
          ),
          const SizedBox(height: Space.s3),
          Text(
            'Check-ins are attested, not proven: our server signs that a '
            'wallet moved enough on a day, from phone health data or, in a '
            'browser, from what the person typed. It cannot launch early, '
            'block a launch, choose who is paid beyond signing daily '
            'check-ins, or move funds.',
            style: t.body(14).copyWith(color: c.text2),
          ),
        ],
      ),
    );
  }
}
