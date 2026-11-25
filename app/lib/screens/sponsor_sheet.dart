import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Opens the sponsor sheet for [round] over the current screen.
Future<void> showSponsorSheet(
  BuildContext context,
  AppState state,
  Round round,
) => showAppSheet<void>(
  context,
  builder: (_) => SponsorSheet(state: state, round: round),
);

/// Optional: anyone may add test USD that goes only to the token pool. It
/// earns no share and comes back to the sponsor if the round does not
/// launch. Flap will not open a pool under its floor, so a small round needs
/// this to launch.
///
/// The sheet is about [round] from the moment it opens until it closes,
/// whatever card is in view on Home behind it.
class SponsorSheet extends StatefulWidget {
  const SponsorSheet({super.key, required this.state, required this.round});
  final AppState state;

  /// The round the sheet was opened for.
  final Round round;

  @override
  State<SponsorSheet> createState() => _SponsorSheetState();
}

class _SponsorSheetState extends State<SponsorSheet> {
  late final TextEditingController _amount;
  bool _busy = false;
  String? _error;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    // Start with what the pool is short of, rounded up to a whole dollar.
    final unit = wholeUnits(1);
    final short = _state.poolShortOf(widget.round.id);
    final whole = (short + unit - BigInt.one) ~/ unit;
    _amount = TextEditingController(
      text: whole > BigInt.zero ? '$whole' : '100',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _sponsor() async {
    final amount = parseUnits(_amount.text);
    if (amount == null) {
      setState(() => _error = 'Type an amount in whole test USD.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _state.sponsor(amount, launcher: widget.round.launcher);
      if (!mounted) return;
      showMessage(
        context,
        '${formatMoney(amount, AppConfig.quoteSymbol)} added to the token '
        'pool.',
        kind: BannerKind.success,
      );
      Navigator.of(context).pop();
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
      final t = context.type;
      final c = context.colors;
      const usd = AppConfig.quoteSymbol;
      return PopScope(
        canPop: !_busy,
        child: SheetFrame(
          tall: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RoundLabel(
                (_state.roundOf(widget.round.id) ?? widget.round).name,
              ),
              const SizedBox(height: Space.s1),
              Semantics(
                header: true,
                child: Text('Sponsor the token pool', style: t.title(30)),
              ),
              const SizedBox(height: Space.s2),
              Text(
                'Sponsor money goes only to the token pool. It earns no '
                'share, and it comes back to you if the token does not '
                'launch.',
                style: t.body(15).copyWith(color: c.text2),
              ),
              const SizedBox(height: Space.s4),
              GlassCard(
                radius: 24,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    KeyValueRow(
                      'In the pool now',
                      formatMoney(
                        _state.roundOf(widget.round.id) == null
                            ? widget.round.poolQuoteNow
                            : _state.poolQuoteNowOf(widget.round.id),
                        usd,
                      ),
                    ),
                    KeyValueRow(
                      'Flap needs',
                      '${formatCount(AppConfig.launchPoolFloor)} $usd',
                      last: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s5),
              const Overline('Amount'),
              const SizedBox(height: 10),
              GlassField(
                fieldKey: const Key('sponsor-amount'),
                controller: _amount,
                placeholder: '600',
                label: 'Amount in test USD',
                number: true,
                suffix: usd,
              ),
              const SizedBox(height: 10),
              Text(
                'Testnet: the test dollars are minted to your wallet first. '
                'On mainnet a sponsor pays with a stablecoin.',
                style: t.body(12).copyWith(color: c.text2),
              ),
              const SizedBox(height: Space.s5),
              if (_error != null) ...[
                ErrorLine(_error!),
                const SizedBox(height: Space.s3),
              ],
              PillButton(
                kind: PillKind.volt,
                label: _error != null ? 'Try again' : 'Add to the token pool',
                busy: _busy,
                busyLabel: _state.funding
                    ? 'Preparing your wallet…'
                    : 'Confirming…',
                onPressed: _sponsor,
              ),
            ],
          ),
        ),
      );
    },
  );
}
