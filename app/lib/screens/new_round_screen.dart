import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'invite_sheet.dart';

/// "New round" (`/new`): one screen with one job, starting a round. No tab
/// bar; a back control returns to where the person came from.
///
/// The name comes first. Then the three numbers every round has (deposit,
/// check-in goal, how long it runs), each with one sentence that says what
/// it does. The token pool's share and "Unlisted" sit under "More options":
/// their defaults suit most rounds. "The deal" spells the choices out in
/// money, line by line, and the one button is pinned at the bottom.
///
/// Pressing it mines the launch salt, calls `Portal.newLauncher` with the
/// CheckInLauncherFactory and tells the server whether the round is shown
/// in the public list, signed by this wallet ([AppState.createRound]). The
/// same screen then says the round has started, by its name, and opens the
/// invite sheet with its link. The round is on this device's Home at once.
class NewRoundScreen extends StatefulWidget {
  const NewRoundScreen({super.key, required this.state, this.missing});
  final AppState state;

  /// The build values that are not set. Defaults to
  /// [AppConfig.missingValues]; a parameter so tests can show both cases.
  final List<String>? missing;

  static const depositOptions = [100, 500, 1000, 2000];
  static const goalOptions = [3, 6, 12, 30, 60];
  static const dayOptions = [1, 3, 7, 14, 30];
  static const poolOptions = [1000, 3000, 5000, 10000];

  /// How many members fill Flap's pool floor with no sponsor, when each
  /// pays [deposit] whole test USD and [bps] of it goes to the token pool.
  static int membersForFloor({required int deposit, required int bps}) {
    final perMember = deposit * bps / 10000;
    return perMember <= 0 ? 0 : (AppConfig.launchPoolFloor / perMember).ceil();
  }

  /// "The deal": what the choices mean, one short line each, in money.
  /// Every line is what the round's contract does:
  ///   - each member pays the same deposit once (`join`);
  ///   - [bps] of every deposit seeds the token's pool at launch and the
  ///     rest is the prize, shared by days checked in. When the whole
  ///     deposit goes to the pool there is no prize, and the one line says
  ///     both;
  ///   - whatever the split, half the token supply and 80% of the trading
  ///     tax go to the round's vault and are shared by days checked in
  ///     ("most of": the deal has no percentages);
  ///   - anyone can launch once the round has [goal] check-ins;
  ///   - after the deadline with no launch, every deposit can be taken back.
  static List<String> dealLines({
    required int deposit,
    required int bps,
    required int goal,
    required int daysOpen,
  }) {
    const usd = AppConfig.quoteSymbol;
    final toPool = deposit * bps ~/ 10000;
    final toPrize = deposit - toPool;
    return [
      'Join: ${formatCount(deposit)} $usd each, paid once.',
      if (toPrize > 0) ...[
        'Prize: ${formatCount(toPrize)} $usd of each deposit, shared by '
            'days shown up.',
        'Token pool: ${formatCount(toPool)} $usd of each deposit.',
      ] else
        'Prize: none. The whole deposit goes to the token pool.',
      'Token: half the supply and most of the trading tax, shared by days '
          'shown up.',
      'Launch: once the group has ${formatCount(goal)} check-ins, anyone '
          'can launch the token.',
      'No launch in ${days(daysOpen)}: every deposit goes back.',
    ];
  }

  /// The quiet line under the deal: what Flap needs before it opens a pool.
  static String floorLine({required int deposit, required int bps}) {
    final n = membersForFloor(deposit: deposit, bps: bps);
    final people = n == 1 ? '1 person' : '${formatCount(n)} people';
    return 'Flap needs ${formatCount(AppConfig.launchPoolFloor)} '
        '${AppConfig.quoteSymbol} in the pool to launch: $people at this '
        'deposit, or a sponsor.';
  }

  @override
  State<NewRoundScreen> createState() => _NewRoundScreenState();
}

class _NewRoundScreenState extends State<NewRoundScreen> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _nameSection = GlobalKey();
  final _nameField = GlobalKey();

  int _deposit = 1000;
  int _bps = AppConfig.defaultLiquidityBps;
  int _goal = 6;
  int _daysOpen = 7;

  /// Not shown in the public list. Still open to anyone with the link, and
  /// on the public chain.
  bool _unlisted = false;

  /// "More options" is open.
  bool _more = false;

  /// The round is being started.
  bool _busy = false;

  /// The server is being asked again to save whether the round is listed.
  bool _saving = false;

  /// Said under the name field when the button was pressed without a name.
  String? _nameError;

  /// One sentence when starting the round failed.
  String? _error;

  /// The round that was started here, and the name it was given.
  String? _launcher;
  String _startedName = '';

  /// How tall the pinned action is, so the content ends above it.
  double _actionHeight = 150;

  AppState get _state => widget.state;

  @override
  void dispose() {
    if (_launcher != null) setAuroraTone(AuroraPalette.ink);
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Round? _roundAt(String launcher) {
    for (final r in _state.rounds) {
      if (r.id == launcher.toLowerCase()) return r;
    }
    return null;
  }

  /// Back to where the person came from; Home when this is the first
  /// screen (the address was opened directly).
  void _back() {
    if (_busy) return;
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.of(context).maybePop();
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  /// Brings the name, its field and the sentence under it into the part of
  /// the list nothing covers: below the top edge and above the pinned
  /// action's fade. Moves only when some of it is out of sight.
  void _revealName() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final section = _nameSection.currentContext;
      if (!mounted || section == null) return;
      final box = section.findRenderObject();
      final field = _nameField.currentContext?.findRenderObject();
      final position = Scrollable.maybeOf(section)?.position;
      if (box == null || field == null || position == null) return;
      final viewport = RenderAbstractViewport.of(box);
      // Where the list stands with the section's top at its top edge, with
      // the field's top there, and with the sentence under the field just
      // above the fade (the section ends in [Space.s6] of empty room).
      final atTop = viewport.getOffsetToReveal(box, 0).offset;
      final fieldAtTop = viewport.getOffsetToReveal(field, 0).offset - Space.s2;
      final atBottom =
          viewport.getOffsetToReveal(box, 1).offset +
          BottomFade.defaultRise -
          Space.s6;
      var to = position.pixels;
      // The label has left at the top: back down to it.
      if (to > atTop) to = atTop;
      // The sentence is under the action: up to it, but never so far that
      // the field itself leaves at the top (a small screen, the keyboard
      // up, large text).
      if (to < atBottom) to = atBottom < fieldAtTop ? atBottom : fieldAtTop;
      to = to.clamp(position.minScrollExtent, position.maxScrollExtent);
      if (to != position.pixels) position.jumpTo(to);
    });
  }

  Future<void> _start() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Give your round a name.');
      _nameFocus.requestFocus();
      _revealName();
      return;
    }
    FocusScope.of(context).unfocus();
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
        unlisted: _unlisted,
      );
      if (!mounted) return;
      setState(() {
        _launcher = launcher;
        _startedName = name;
      });
      setAuroraTone(AuroraPalette.volt);
      // Straight to the link to hand out.
      final round = _roundAt(launcher);
      if (round != null) unawaited(showInviteSheet(context, _state, round));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks the server again to save whether the round is listed.
  Future<void> _saveListing(String launcher) async {
    setState(() => _saving = true);
    try {
      await _state.registerRound(launcher);
    } catch (_) {
      // The card shows the sentence the state kept.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _measured(Size size) {
    if (mounted && size.height != _actionHeight) {
      setState(() => _actionHeight = size.height);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final missing = widget.missing ?? AppConfig.missingValues;
      final launcher = _launcher;
      final List<Widget> content;
      final List<Widget> action;
      if (launcher != null) {
        content = _doneContent(context, launcher);
        action = _doneAction(context, launcher);
      } else if (missing.isNotEmpty) {
        content = _missingContent(context, missing);
        action = const [];
      } else {
        content = _formContent(context);
        action = _formAction(context);
      }
      return PopScope(
        canPop: !_busy,
        child: Scaffold(
          // From the keyboard: the whole form first, then the pinned action,
          // wherever the form is scrolled to.
          body: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Stack(
              children: [
                // The list ends where the pinned action turns opaque: only
                // the action's fade is over its last pixels, never the button.
                // A field that scrolls itself into view (the name, with the
                // keyboard up) therefore lands where it can be read.
                Positioned.fill(
                  bottom: action.isEmpty
                      ? 0
                      : (_actionHeight - BottomFade.defaultRise).clamp(
                          0.0,
                          double.infinity,
                        ),
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: FocusTraversalGroup(
                      child: SafeArea(
                        bottom: false,
                        child: ListView(
                          key: const Key('new-round-list'),
                          padding: EdgeInsets.fromLTRB(
                            Space.gutter,
                            Space.s2,
                            Space.gutter,
                            action.isEmpty
                                ? Space.s8 +
                                      MediaQuery.paddingOf(context).bottom
                                : BottomFade.defaultRise + Space.s4,
                          ),
                          children: content,
                        ),
                      ),
                    ),
                  ),
                ),
                if (action.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: FocusTraversalGroup(
                        child: SizeReporter(
                          onSize: _measured,
                          child: BottomFade(
                            key: const Key('new-round-action'),
                            child: SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Space.gutter,
                                  BottomFade.defaultRise,
                                  Space.gutter,
                                  Space.s3,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: action,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  // The form -------------------------------------------------------------------

  Widget _backControl() => Align(
    alignment: Alignment.centerLeft,
    child: GlassIconButton(
      icon: Icons.arrow_back_rounded,
      tooltip: 'Back',
      onPressed: _back,
    ),
  );

  Widget _title(BuildContext context) => Semantics(
    header: true,
    child: Text('NEW ROUND', style: context.type.display(56)),
  );

  /// A choice: its name, one sentence that says what it does, the control.
  Widget _field(
    BuildContext context, {
    required String label,
    required String helper,
    required Widget child,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, helper: helper),
        const SizedBox(height: Space.s3),
        child,
      ],
    ),
  );

  List<Widget> _formContent(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    const usd = AppConfig.quoteSymbol;
    final lines = NewRoundScreen.dealLines(
      deposit: _deposit,
      bps: _bps,
      goal: _goal,
      daysOpen: _daysOpen,
    );
    return [
      _backControl(),
      const SizedBox(height: Space.s5),
      _title(context),
      const SizedBox(height: Space.s5),
      // Nothing can be changed while the round is being sent, by touch or
      // from the keyboard: what "The deal" says stays what is started.
      AbsorbPointer(
        absorbing: _busy,
        child: ExcludeFocus(
          excluding: _busy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: _nameSection,
                padding: const EdgeInsets.only(bottom: Space.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The name is sent to the chain as the token's name
                    // (and its symbol is made from it); it has no setter.
                    const _FieldLabel(
                      label: 'Name',
                      helper:
                          'Also the name of the token. It can\'t be changed '
                          'after you start.',
                    ),
                    const SizedBox(height: Space.s3),
                    GlassField(
                      key: _nameField,
                      fieldKey: const Key('round-name'),
                      controller: _name,
                      focusNode: _nameFocus,
                      large: true,
                      // When it scrolls itself into view (the keyboard comes
                      // up), the field and the sentence under it clear the
                      // pinned action's fade.
                      scrollPadding: const EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        BottomFade.defaultRise + 64,
                      ),
                      placeholder: 'Morning Movers',
                      label: 'Name',
                      onChanged: (_) {
                        if (_nameError != null || _error != null) {
                          setState(() {
                            _nameError = null;
                            _error = null;
                          });
                        }
                      },
                    ),
                    if (_nameError != null) ...[
                      const SizedBox(height: Space.s2),
                      ErrorLine(_nameError!),
                    ],
                  ],
                ),
              ),
              _field(
                context,
                label: 'Deposit · test $usd',
                helper: 'Each person pays this once to join.',
                child: ChipPicker<int>(
                  key: const Key('round-deposit'),
                  options: NewRoundScreen.depositOptions,
                  selection: _deposit,
                  label: formatCount,
                  semanticLabel: (v) => '${formatCount(v)} test $usd',
                  height: Sizes.touch,
                  minWidth: 56,
                  wrap: true,
                  onChanged: (v) => setState(() => _deposit = v),
                ),
              ),
              _field(
                context,
                label: 'Goal',
                helper:
                    'Check-ins the group needs to launch the token. One per '
                    'person per day.',
                child: ChipPicker<int>(
                  key: const Key('round-goal'),
                  options: NewRoundScreen.goalOptions,
                  selection: _goal,
                  label: (v) => '$v',
                  semanticLabel: (v) => '$v check-ins',
                  height: Sizes.touch,
                  minWidth: 56,
                  wrap: true,
                  onChanged: (v) => setState(() => _goal = v),
                ),
              ),
              _field(
                context,
                label: 'Runs for',
                helper:
                    'If the goal isn\'t reached by then, every deposit goes '
                    'back.',
                child: ChipPicker<int>(
                  key: const Key('round-days'),
                  options: NewRoundScreen.dayOptions,
                  selection: _daysOpen,
                  label: days,
                  height: Sizes.touch,
                  minWidth: 56,
                  wrap: true,
                  onChanged: (v) => setState(() => _daysOpen = v),
                ),
              ),
              GlassCard(
                padding: EdgeInsets.zero,
                radius: Radii.row,
                child: ActionRow(
                  key: const Key('round-more'),
                  title: 'More options',
                  detail:
                      'Token pool ${formatBps(_bps)} · '
                      '${_unlisted ? 'Unlisted' : 'Listed'}',
                  semanticLabel:
                      'More options. Token pool ${formatBps(_bps)}, '
                      '${_unlisted ? 'unlisted' : 'listed'}',
                  expanded: _more,
                  trailingIcon: _more
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  minHeight: 60,
                  onPressed: () => setState(() => _more = !_more),
                ),
              ),
              if (_more) ...[
                const SizedBox(height: Space.s5),
                _field(
                  context,
                  label: 'Token pool',
                  helper:
                      'The part of each deposit that backs the token at '
                      'launch. The rest is the prize.',
                  child: ChipPicker<int>(
                    key: const Key('round-pool'),
                    options: NewRoundScreen.poolOptions,
                    selection: _bps,
                    label: formatBps,
                    semanticLabel: (v) =>
                        '${formatBps(v)} of each deposit to the token pool',
                    height: Sizes.touch,
                    minWidth: 56,
                    wrap: true,
                    onChanged: (v) => setState(() => _bps = v),
                  ),
                ),
                GlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  radius: Radii.row,
                  child: CapsuleToggle(
                    key: const Key('round-unlisted'),
                    title: 'Unlisted',
                    detail: unlistedNote,
                    value: _unlisted,
                    onChanged: (v) => setState(() => _unlisted = v),
                  ),
                ),
              ],
              const SizedBox(height: Space.s6),
              GlassCard(
                key: const Key('round-deal'),
                tint: c.volt.withValues(alpha: 0.3),
                // Read as one thing: the deal, line by line.
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Overline('The deal'),
                      const SizedBox(height: Space.s3),
                      for (final line in lines) _DealLine(line),
                      const SizedBox(height: Space.s1),
                      Text(
                        NewRoundScreen.floorLine(deposit: _deposit, bps: _bps),
                        style: t.body(13).copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _formAction(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    // With the keyboard up the bar is the button alone, so the form keeps
    // the room there is.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return [
      if (_error != null) ...[
        ErrorLine(_error!),
        const SizedBox(height: Space.s3),
      ],
      PillButton(
        icon: _error != null ? Icons.refresh_rounded : Icons.bolt_rounded,
        label: _error != null ? 'Try again' : 'Start round',
        busy: _busy,
        busyLabel: _state.funding
            ? 'Preparing your wallet…'
            : 'Starting your round…',
        onPressed: _start,
      ),
      if (!typing) ...[
        const SizedBox(height: Space.s2),
        Text(
          // About 0.007 test BNB: the Portal's 0.005 fee plus the gas (see
          // AppConfig.startRoundGasWei). The creator is not made a member.
          'Costs about 0.007 test BNB in fees. You join from Home like '
          'everyone else.',
          textAlign: TextAlign.center,
          style: t.body(12).copyWith(color: c.text2),
        ),
      ],
    ];
  }

  // No addresses in this build -------------------------------------------------

  List<Widget> _missingContent(BuildContext context, List<String> missing) {
    final t = context.type;
    final c = context.colors;
    return [
      _backControl(),
      const SizedBox(height: Space.s5),
      _title(context),
      const SizedBox(height: Space.s5),
      GlassCard(
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
      ),
    ];
  }

  // Started --------------------------------------------------------------------

  List<Widget> _doneContent(BuildContext context, String launcher) {
    final t = context.type;
    final c = context.colors;
    final known = _state.knownRound(launcher);
    final saved = known?.registered ?? false;
    final unlisted = known?.unlisted ?? _unlisted;
    final name = _roundAt(launcher)?.name ?? _startedName;
    return [
      const SizedBox(height: Space.s12),
      Align(
        alignment: Alignment.centerLeft,
        child: Icon(Icons.verified_rounded, size: 44, color: c.volt),
      ),
      const SizedBox(height: Space.s3),
      const Overline('Round started'),
      const SizedBox(height: Space.s1),
      Semantics(
        header: true,
        child: Text(
          name,
          key: const Key('round-started-name'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: t.title(40),
        ),
      ),
      const SizedBox(height: Space.s3),
      Text(
        'It\'s on your Home. Invite people to fill the bar.',
        style: t.body(15).copyWith(color: c.text2),
      ),
      const SizedBox(height: Space.s6),
      GlassCard(
        key: const Key('round-listing'),
        radius: Radii.row,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('Public list'),
            const SizedBox(height: Space.s2),
            if (saved)
              Text(
                unlisted
                    ? 'Unlisted. $unlistedNote'
                    : 'Listed: everyone sees it in the list on Home.',
                style: t.body(14),
              )
            else ...[
              ErrorLine(
                known?.registerError ??
                    'The server has not saved whether this round is listed '
                        'yet.',
              ),
              if (unlisted) ...[
                const SizedBox(height: Space.s2),
                Text(
                  'Until it is saved as unlisted, the round can show in the '
                  'public list.',
                  style: t.body(13).copyWith(color: c.text2),
                ),
              ],
              const SizedBox(height: Space.s3),
              PillButton(
                kind: PillKind.glass,
                height: Sizes.buttonSmall,
                icon: Icons.refresh_rounded,
                label: 'Save again',
                busy: _saving,
                busyLabel: 'Saving…',
                onPressed: () => _saveListing(launcher),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: Space.s3),
      LinkRow(
        label: 'View on BscScan testnet',
        url: '${AppConfig.explorerAddress}$launcher',
      ),
    ];
  }

  List<Widget> _doneAction(BuildContext context, String launcher) {
    final round = _roundAt(launcher);
    return [
      PillButton(
        icon: Icons.ios_share_rounded,
        label: 'Invite people',
        // The round is on the slider from the moment it is started; if it
        // has left it since, there is nothing to hand out from here.
        onPressed: round == null
            ? null
            : () => showInviteSheet(context, _state, round),
      ),
      const SizedBox(height: Space.s2),
      PillButton(
        kind: PillKind.glass,
        height: Sizes.buttonSmall,
        label: 'Go to round',
        onPressed: () {
          // Home opens on this round, whatever was read in the meantime.
          if (_state.selected != launcher.toLowerCase()) {
            _state.select(launcher);
          }
          final router = GoRouter.maybeOf(context);
          if (router != null) {
            router.go('/');
          } else {
            Navigator.of(context).maybePop();
          }
        },
      ),
    ];
  }
}

/// A choice's name and the one sentence that says what it does. One node
/// for a screen reader, read just before the control it is about.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.helper});
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Overline(label, color: context.colors.text),
        const SizedBox(height: Space.s1),
        Text(
          helper,
          style: context.type.body(13).copyWith(color: context.colors.text2),
        ),
      ],
    ),
  );
}

/// One line of "The deal": what it is about in white ("Join:"), the rest
/// quieter.
class _DealLine extends StatelessWidget {
  const _DealLine(this.line);
  final String line;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final at = line.indexOf(': ');
    final head = at < 0 ? '' : line.substring(0, at + 1);
    final rest = at < 0 ? line : line.substring(at + 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: head, style: t.body(14, FontWeight.w600)),
            TextSpan(text: rest),
          ],
        ),
        style: t.body(14).copyWith(color: c.text2),
      ),
    );
  }
}
