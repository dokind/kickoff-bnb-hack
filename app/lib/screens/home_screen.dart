import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/dot_matrix.dart';
import '../widgets/identicon.dart';
import '../widgets/launch_floor_line.dart';
import '../widgets/main_tabs.dart';
import '../widgets/pot_section.dart';
import '../widgets/round_slider.dart';
import '../widgets/so_far_card.dart';
import '../widgets/streak_block.dart';
import 'checkin_sheet.dart';
import 'invite_sheet.dart';
import 'join_sheet.dart';
import 'sponsor_sheet.dart';

/// Home, the one screen. At the top: the rounds, one card each, swiped
/// sideways (they also move on by themselves). The card in view is the
/// selected round and everything under it is about that round: THE PRIZE
/// first (what showing up is worth here, member by member, and what the
/// launch still needs), then the streak and today's state, the prize and
/// the token pool, the rules, the totals so far, and ONE primary action
/// that changes with it:
///   "Join Demo Day · 1,000 USD" -> "Check in · Demo Day" -> "Checked in"
///   (with a hint about tomorrow) -> "Launch Demo Day" once the bar is full
///   (anyone) -> "Claim · Demo Day" after the launch.
/// The action floats over the content on a scrim that is opaque behind it.
///
/// So that nobody pays into a round they did not mean: the cards move on by
/// themselves only until the first touch on Home in this session
/// ([AppState.autoAdvance]), the action's label names the round it acts on,
/// and the action is for the round its label named when it was pressed (the
/// sheets it opens keep that round).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state, this.showBar = true});
  final AppState state;

  /// The floating tab bar (off in tests that pump the screen alone).
  final bool showBar;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  /// One sentence when the inline action (launch, refund) failed. The
  /// button stays, so pressing it again is the retry.
  String? _error;

  AppState get _state => widget.state;

  /// Other people's check-ins move the bar, so Home reads the rounds again
  /// every twenty seconds while it is open and nothing covers it.
  Timer? _poll;

  final _scroll = ScrollController();
  final _slider = GlobalKey<RoundSliderState>();

  /// How tall the floating action is right now. The scrolling content ends
  /// that far above the bottom, so its last card can be read in full.
  double _actionHeight = 260;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_canPoll()) _state.refresh();
    });
    _state.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    _state.removeListener(_changed);
    _poll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Home reads the rounds again only while it is what the person is
  /// looking at. Under a sheet or another screen it waits: each of those
  /// reads again after its own action, and a read started under the
  /// new-round screen could finish after the round was started and put the
  /// list back as it was before, without the new round.
  bool _canPoll() =>
      mounted && !_busy && (ModalRoute.of(context)?.isCurrent ?? true);

  /// A sentence the state wants said once (a link that leads nowhere).
  /// While a sheet or another screen is over Home it is left alone: the
  /// "Open an invite link" sheet says it itself, next to its field.
  void _changed() {
    final notice = _state.notice;
    if (notice == null || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _state.notice = null;
    showMessage(context, notice);
  }

  Future<void> _run(Future<String> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) showMessage(context, done, kind: BannerKind.success);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The result of [round]: the round named on the button that was pressed.
  void _openResult(Round round) {
    if (_state.selected != round.id) _state.select(round.launcher);
    GoRouter.maybeOf(context)?.go('/result');
  }

  /// The first touch on Home (a finger, a mouse button, a wheel or a
  /// trackpad scroll): from now until the app is opened again the cards
  /// never move by themselves.
  void _touched() {
    _state.stopAutoAdvance();
    _slider.currentState?.touched();
  }

  /// The cards move on by themselves only while nobody has touched Home yet
  /// and Home is what the person is looking at: no sheet, dialog or other
  /// screen over it, nothing being sent, and the cards still in view.
  bool _canAdvance() =>
      mounted &&
      _state.autoAdvance &&
      !_busy &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      (!_scroll.hasClients || _scroll.offset < 140);

  void _select(int index, {required bool byPerson}) {
    final rounds = _state.rounds;
    if (index < 0 || index >= rounds.length) return;
    if (_error != null) setState(() => _error = null);
    _state.select(rounds[index].launcher, remember: byPerson);
  }

  /// One card per round. The selected round's numbers are the chain's when
  /// it could be read.
  List<RoundCardInfo> get _cards => [
    for (final r in _state.rounds)
      r.id == _state.selected
          ? RoundCardInfo(
              round: (_state.round ?? r).copyWith(
                featured: r.featured,
                unlisted: r.unlisted,
              ),
              totalCheckIns: _state.totalCheckIns,
              launched: _state.launched,
              joined: _state.isMember,
            )
          : RoundCardInfo(
              round: r,
              totalCheckIns: r.totalCheckIns,
              launched: r.launched,
              joined: _state.isMemberOf(r.launcher),
            ),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final round = _state.round;
      Widget inset(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: child,
      );
      return Scaffold(
        // A touch anywhere on Home keeps the cards where they are, for good.
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            _state.stopAutoAdvance();
            _slider.currentState?.touchDown();
          },
          onPointerUp: (_) => _slider.currentState?.touchUp(),
          onPointerCancel: (_) => _slider.currentState?.touchUp(),
          onPointerSignal: (_) => _touched(),
          onPointerPanZoomStart: (_) => _touched(),
          child: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: RefreshIndicator(
                  onRefresh: _state.refresh,
                  color: context.colors.onVolt,
                  backgroundColor: context.colors.volt,
                  child: ListView(
                    key: const Key('home-list'),
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      top: Space.s2,
                      bottom: _actionHeight + Space.s4,
                    ),
                    children: [
                      inset(_Header(state: _state)),
                      const SizedBox(height: Space.s5),
                      if (round == null)
                        inset(_NoRound(state: _state))
                      else ...[
                        if (_state.roundError != null) ...[
                          inset(
                            ErrorRetry(
                              text: _state.roundError!,
                              onRetry: _state.refresh,
                            ),
                          ),
                          const SizedBox(height: Space.s5),
                        ],
                        RoundSlider(
                          key: _slider,
                          cards: _cards,
                          index: _state.selectedIndex,
                          now: _state.now,
                          onSelect: _select,
                          onInvite: (r) => showInviteSheet(context, _state, r),
                          canAdvance: _canAdvance,
                          autoAdvance: _state.autoAdvance,
                        ),
                        const SizedBox(height: Space.s5),
                        // Money first: what showing up is worth here.
                        inset(
                          PotSection(
                            state: _state,
                            round: round,
                            onInvite: () =>
                                showInviteSheet(context, _state, round),
                          ),
                        ),
                        inset(LaunchFloorLine(state: _state, round: round)),
                        const SizedBox(height: Space.s6),
                        inset(StreakBlock(state: _state)),
                        const SizedBox(height: Space.s6),
                        inset(_PrizeCard(state: _state, round: round)),
                        const SizedBox(height: Space.s6),
                        inset(
                          _HowItWorks(
                            key: const Key('how-it-works'),
                            state: _state,
                            round: round,
                          ),
                        ),
                        if (_state.stats != null) ...[
                          const SizedBox(height: Space.s6),
                          inset(
                            SoFarCard(
                              stats: _state.stats!,
                              inARound: _state.joined.isNotEmpty,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizeReporter(
                  onSize: (size) {
                    if (mounted && size.height != _actionHeight) {
                      setState(() => _actionHeight = size.height);
                    }
                  },
                  child: BottomFade(
                    key: const Key('home-action'),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.gutter,
                          BottomFade.defaultRise,
                          Space.gutter,
                          6,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (round != null) ..._action(context, round),
                            if (widget.showBar) ...[
                              const SizedBox(height: Space.s3),
                              MainTabs(current: MainTabs.home, state: _state),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// The hint, the one primary action, and at most one quiet extra, for
  /// [round], the selected round as this frame shows it. The label names
  /// the round, and every press acts on [round] and no other: the address
  /// is taken here, where the label is made, not read again later.
  List<Widget> _action(BuildContext context, Round round) {
    final t = context.type;
    final c = context.colors;
    const usd = AppConfig.quoteSymbol;
    final stage = _state.stage;
    final at = round.launcher;
    // A press that began on one round's button never lands on another's: a
    // new round is a new button, and the press in flight is dropped.
    final key = ValueKey('action-${round.id}');
    // A long name is cut short inside the label; the words around it stay.
    final name = round.name.trim().isEmpty ? 'this round' : round.name.trim();

    Widget hint(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _error != null
          ? ErrorLine(_error!)
          : Text(
              text,
              textAlign: TextAlign.center,
              style: t.body(13, FontWeight.w500).copyWith(color: c.text2),
            ),
    );

    switch (stage) {
      case HomeStage.loading || HomeStage.error || HomeStage.noRound:
        return const [];
      case HomeStage.join:
        return [
          hint('Pay once. It comes back if the token never launches.'),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.bolt_rounded,
            label: 'Join $name · ${formatMoney(_state.deposit, usd)}',
            shrink: name,
            key: key,
            onPressed: () => showJoinSheet(context, _state, round),
          ),
        ];
      case HomeStage.checkIn:
        return [
          hint(
            _state.hasPendingCheckIn
                ? 'Today\'s check-in is signed. Finish it on chain.'
                : _state.health.available
                ? 'Reads today\'s steps from your phone.'
                : 'Self-reported in the browser. Testnet only.',
          ),
          PillButton(
            icon: Icons.check_rounded,
            label: 'Check in · $name',
            shrink: name,
            key: key,
            onPressed: () => showCheckInSheet(context, _state, round),
          ),
        ];
      case HomeStage.checkedIn:
        final wait = nextUtcDay(_state.now).difference(_state.now);
        return [
          hint(
            'Come back tomorrow. The next day starts in ${formatWait(wait)}.',
          ),
          const PillButton(
            kind: PillKind.glass,
            icon: Icons.check_rounded,
            label: 'Checked in',
            onPressed: null,
          ),
        ];
      case HomeStage.launch:
        final short = _state.poolShort;
        final canCheckInFirst = _state.isMember && !_state.checkedInToday;
        return [
          hint(
            short > BigInt.zero
                ? 'The bar is full, but the token pool is '
                      '${formatTestUsd(short)} short of what Flap needs.'
                : 'The bar is full. Anyone can launch the token now.',
          ),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.rocket_launch_rounded,
            label: 'Launch $name',
            shrink: name,
            key: key,
            busy: _busy,
            busyLabel: _state.funding
                ? 'Preparing your wallet…'
                : 'Launching on Flap…',
            onPressed: short > BigInt.zero
                ? null
                : () => _run(
                    () => _state.launch(launcher: at),
                    'Launched. The token is live.',
                  ),
          ),
          if (short > BigInt.zero) ...[
            const SizedBox(height: 10),
            PillButton(
              kind: PillKind.glass,
              height: Sizes.buttonSmall,
              label: 'Sponsor the token pool',
              onPressed: () => showSponsorSheet(context, _state, round),
            ),
          ] else if (canCheckInFirst && !_busy)
            _TextAction(
              label: 'Check in first',
              onPressed: () => showCheckInSheet(context, _state, round),
            ),
        ];
      case HomeStage.claim:
        return [
          hint(
            _state.hasClaimable
                ? 'The token launched. Your share is waiting in the vault.'
                : 'The token launched. More arrives as people trade.',
          ),
          PillButton(
            kind: PillKind.volt,
            icon: Icons.auto_awesome_rounded,
            label: 'Claim · $name',
            shrink: name,
            key: key,
            onPressed: () => _openResult(round),
          ),
        ];
      case HomeStage.result:
        return [
          hint('The token launched. You have no check-ins in this round.'),
          PillButton(
            label: 'See the result · $name',
            shrink: name,
            key: key,
            onPressed: () => _openResult(round),
          ),
        ];
      case HomeStage.refund:
        return [
          hint('The bar did not fill in time. Your deposit is yours again.'),
          PillButton(
            icon: Icons.undo_rounded,
            label: 'Deposit back · $name',
            shrink: name,
            key: key,
            busy: _busy,
            busyLabel: _state.funding
                ? 'Preparing your wallet…'
                : 'Returning your deposit…',
            onPressed: () => _run(
              () => _state.refund(launcher: at),
              'Your deposit is back.',
            ),
          ),
        ];
      case HomeStage.ended:
        return [
          hint('This round closed without a launch.'),
          const PillButton(
            kind: PillKind.glass,
            label: 'Round ended',
            onPressed: null,
          ),
        ];
    }
  }
}

/// A quiet text button under the primary action.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: context.type
            .body(14, FontWeight.w500)
            .copyWith(color: context.colors.text2),
      ),
    ),
  );
}

/// A greeting and how many rounds there are; the balance and the wallet's
/// orb on the right, which opens Wallet.
class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AppState state;

  String get _greeting => switch (state.now.hour) {
    >= 5 && < 12 => 'Good morning',
    >= 12 && < 18 => 'Good afternoon',
    _ => 'Good evening',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting, style: t.title(24)),
                const SizedBox(height: 3),
                // Every amount on Home is test money. On a narrow phone
                // with large text the pill goes under the count rather
                // than overflow.
                Wrap(
                  spacing: Space.s2,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      switch (state.rounds.length) {
                        0 => AppConfig.productName,
                        1 => '1 round',
                        final n => '$n rounds',
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body(14).copyWith(color: c.text2),
                    ),
                    const TestnetPill(height: 20),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s3),
          if (state.hasWallet)
            Semantics(
              button: true,
              label: 'Wallet. ${formatMoney(state.usd, AppConfig.quoteSymbol)}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => GoRouter.maybeOf(context)?.go('/account'),
                child: GlassSurface.pill(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 14),
                        Text(
                          formatMoney(state.usd, AppConfig.quoteSymbol),
                          style: t
                              .body(13, FontWeight.w600)
                              .copyWith(
                                height: 1,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        const SizedBox(width: 8),
                        Identicon(address: state.address),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown in place of the round while there is none to show.
class _NoRound extends StatelessWidget {
  const _NoRound({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return switch (state.stage) {
      HomeStage.error => ErrorRetry(
        text: state.roundError!,
        onRetry: state.refresh,
      ),
      HomeStage.noRound => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NO ROUND\nRIGHT NOW.', style: t.display(44)),
            const SizedBox(height: Space.s3),
            Text(
              'Press + to start one, or to open an invite link someone '
              'sent you.',
              style: t.body(15).copyWith(color: c.text2),
            ),
            const SizedBox(height: Space.s4),
            PillButton(
              kind: PillKind.glass,
              height: Sizes.buttonSmall,
              icon: Icons.refresh_rounded,
              label: 'Look again',
              onPressed: state.refresh,
            ),
          ],
        ),
      ),
      _ => GlassCard(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.text),
            ),
            const SizedBox(width: Space.s3),
            Text('Reading the round…', style: t.body(15)),
          ],
        ),
      ),
    };
  }
}

/// The prize so far in dot-matrix numerals, beside the token pool.
class _PrizeCard extends StatelessWidget {
  const _PrizeCard({required this.state, required this.round});
  final AppState state;
  final Round round;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    const usd = AppConfig.quoteSymbol;
    final short = state.poolShort;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      tint: c.volt.withValues(alpha: 0.4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Prize so far'),
                const SizedBox(height: Space.s3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: DotMatrixText(
                    formatAmount(round.prizeNow, maxFraction: 0),
                    dot: 7.5,
                    gap: 2.5,
                  ),
                ),
                const SizedBox(height: Space.s3),
                Text(
                  'test $usd, shared by days shown up',
                  style: t.body(12).copyWith(color: c.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Overline('Token pool'),
                const SizedBox(height: 6),
                Text(
                  formatAmount(state.poolQuoteNow, maxFraction: 0),
                  style: t
                      .metric(28)
                      .copyWith(color: short > BigInt.zero ? c.text : c.volt),
                ),
                const SizedBox(height: 2),
                Text(
                  state.launched
                      ? '$testUsd, in the pool'
                      : short > BigInt.zero
                      ? 'of ${formatCount(AppConfig.launchPoolFloor)} $testUsd '
                            'Flap needs'
                      : '$testUsd, enough for Flap',
                  textAlign: TextAlign.right,
                  style: t.body(12).copyWith(color: c.text2),
                ),
                if (short > BigInt.zero &&
                    !state.launched &&
                    !state.pastDeadline) ...[
                  const SizedBox(height: Space.s2),
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showSponsorSheet(context, state, round),
                      child: const AppChip(
                        text: 'Sponsor',
                        icon: Icons.add_rounded,
                        height: 30,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The rules of the round in six lines, with what the server can and cannot
/// do said plainly.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks({super.key, required this.state, required this.round});
  final AppState state;
  final Round round;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('How it works'),
        const SizedBox(height: 14),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              IconRow(
                icon: Icons.payments_outlined,
                text:
                    'The deposit is ${formatTestUsd(state.deposit)}, paid '
                    'once: ${formatBps(10000 - round.liquidityBps)} to the '
                    'prize, ${formatBps(round.liquidityBps)} to the token '
                    'pool.',
              ),
              IconRow(
                icon: Icons.directions_walk_rounded,
                text:
                    'Check in on any day you take at least '
                    '${formatCount(round.minSteps)} steps. One per day, '
                    'counted in UTC.',
              ),
              IconRow(
                icon: Icons.rocket_launch_outlined,
                text:
                    'Launch needs both: '
                    '${formatCount(round.checkInGoal)} check-ins and '
                    '${formatCount(AppConfig.launchPoolFloor)} $testUsd in '
                    'the token pool. Then anyone can launch it on Flap.',
              ),
              const IconRow(
                icon: Icons.pie_chart_outline_rounded,
                text:
                    'The prize, half of the token supply and 80% of the '
                    'trading tax are shared by how many days each member '
                    'showed up.',
              ),
              IconRow(
                icon: Icons.undo_rounded,
                text:
                    'If the token has not launched by '
                    '${formatDate(round.deadline)}, every deposit goes back '
                    'in full.',
              ),
              const IconRow(
                icon: Icons.verified_user_outlined,
                text:
                    'Check-ins are attested by ${AppConfig.productName}\'s '
                    'server, not proven. The server cannot launch early, '
                    'block a launch or move funds.',
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
