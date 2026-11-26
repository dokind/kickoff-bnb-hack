import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/dot_matrix.dart';
import '../widgets/gauges.dart';
import '../widgets/identicon.dart';

/// The result, after the launch: the token's address with links to BscScan
/// testnet and to Flap, this wallet's days, its share (tokens and test USD)
/// and Claim. Claim can be pressed again later: the trading tax reaches the
/// vault for the coin's first 30 days, and only when people trade.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _busy = false;
  String? _error;

  /// The last claim transaction made from this screen.
  String? _tx;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    setAuroraTone(AuroraPalette.volt);
  }

  @override
  void dispose() {
    setAuroraTone(AuroraPalette.ink);
    super.dispose();
  }

  /// Claims from the round at [launcher]: the one this screen named when
  /// the button was pressed.
  Future<void> _claim(String? launcher) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tx = await _state.claim(launcher: launcher);
      if (!mounted) return;
      setState(() => _tx = tx);
      showMessage(
        context,
        'Your share is in your wallet.',
        kind: BannerKind.success,
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/');
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final t = context.type;
      final c = context.colors;
      const usd = AppConfig.quoteSymbol;
      final round = _state.round;
      final token = _state.token;
      final myDays = _state.daysOf;
      final total = _state.totalCheckIns;
      final part = total > 0 ? myDays * 100 / total : 0.0;

      return Scaffold(
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.s2,
                  Space.gutter,
                  170,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: _back,
                    ),
                  ),
                  const SizedBox(height: Space.s5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusBadge(
                      text: 'Launched on Flap',
                      color: c.success,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (round != null) ...[
                    RoundLabel(round.name),
                    const SizedBox(height: Space.s1),
                  ],
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      header: true,
                      child: Text('THE COIN\nIS LIVE.', style: t.display(58)),
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  Text(
                    '${round?.name ?? 'The round'} filled the bar with '
                    '${formatCount(total)} check-ins. The prize and 500,000 '
                    'of the 1,000,000 new coins are in the group\'s piggy '
                    'bank, split by days shown up. The other half is in the '
                    'shop, locked forever.',
                    style: t.body(15).copyWith(color: c.text2),
                  ),
                  const SizedBox(height: 22),
                  if (token != null) ...[
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Overline('Coin'),
                          const SizedBox(height: Space.s2),
                          Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  token,
                                  style: t.mono.copyWith(fontSize: 12.5),
                                ),
                              ),
                              const SizedBox(width: Space.s2),
                              GlassIconButton(
                                icon: Icons.copy_rounded,
                                tooltip: 'Copy coin address',
                                size: 38,
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: token));
                                  showMessage(context, 'Coin address copied.');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.s2),
                          Divider(color: c.hairline),
                          LinkRow(
                            label: 'View on BscScan testnet',
                            url: '${AppConfig.explorerToken}$token',
                          ),
                          Divider(color: c.hairline),
                          LinkRow(
                            label: 'Open on Flap',
                            url:
                                round?.flapUrl ??
                                '${AppConfig.flapToken}$token',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.s3),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.calendar_today_rounded,
                          label: 'Your days',
                          value: '$myDays',
                          unit: '/ ${formatCount(total)}',
                        ),
                      ),
                      const SizedBox(width: Space.s3),
                      Expanded(
                        child: StatTile(
                          icon: Icons.pie_chart_outline_rounded,
                          label: 'Your part',
                          value: part == part.roundToDouble()
                              ? '${part.round()}'
                              : part.toStringAsFixed(1),
                          unit: '%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s3),
                  if (myDays == 0)
                    GlassCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_rounded, size: 20, color: c.text2),
                          const SizedBox(width: Space.s2),
                          Expanded(
                            child: Text(
                              'You have no check-ins in this round, so there '
                              'is no share to claim.',
                              style: t.body(15),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      tint: c.volt.withValues(alpha: 0.4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Overline('Your share')),
                              if (_state.hasWallet)
                                Identicon(address: _state.address, size: 24),
                            ],
                          ),
                          const SizedBox(height: Space.s3),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: DotMatrixText(
                                    formatAmount(_state.claimableQuote),
                                    dot: 8,
                                    gap: 2.6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'test $usd',
                                style: t
                                    .body(14, FontWeight.w600)
                                    .copyWith(color: c.text2),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.s4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    formatAmount(_state.claimableTokens),
                                    style: t.metric(30),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'coins',
                                style: t
                                    .body(13, FontWeight.w500)
                                    .copyWith(color: c.text2),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.s3),
                          Divider(color: c.hairline),
                          const SizedBox(height: Space.s3),
                          Row(
                            children: [
                              Text(
                                'Already claimed',
                                style: t.body(13).copyWith(color: c.text2),
                              ),
                              const SizedBox(width: Space.s3),
                              Expanded(
                                child: Text(
                                  '${formatAmount(_state.claimedTokens)} '
                                  'coins · '
                                  '${formatTestUsd(_state.claimedQuote)}',
                                  textAlign: TextAlign.right,
                                  style: t.body(13, FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.s2),
                          Text(
                            '$taxLine Claim again whenever there is more.',
                            key: const Key('result-tax'),
                            style: t.body(12).copyWith(color: c.text2),
                          ),
                          if (_tx != null) ...[
                            const SizedBox(height: Space.s2),
                            Divider(color: c.hairline),
                            LinkRow(
                              label: 'Claim transaction',
                              url: '${AppConfig.explorerTx}$_tx',
                              value: _tx,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (myDays > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomFade(
                  rise: 30,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        30,
                        Space.gutter,
                        Space.s3,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            ErrorLine(_error!),
                            const SizedBox(height: 10),
                          ],
                          // The claim's steps, as the state runs them.
                          if (_busy &&
                              _state.stepsFor(StepAction.claim) != null) ...[
                            RunProgress(
                              key: const Key('claim-progress'),
                              steps: _state.steps!.steps,
                              current: _state.steps!.current,
                            ),
                            const SizedBox(height: Space.s3),
                          ],
                          if (_state.hasClaimable || _busy)
                            PillButton(
                              kind: PillKind.volt,
                              icon: _error != null
                                  ? Icons.refresh_rounded
                                  : Icons.auto_awesome_rounded,
                              label: _error != null ? 'Try again' : 'Claim',
                              busy: _busy,
                              busyLabel: _state.funding
                                  ? 'Preparing your wallet…'
                                  : 'Claiming…',
                              onPressed: () => _claim(round?.launcher),
                            )
                          else
                            const PillButton(
                              kind: PillKind.glass,
                              icon: Icons.check_rounded,
                              label: 'Nothing more to claim yet',
                              onPressed: null,
                            ),
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
}
