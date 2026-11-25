import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'controls.dart';
import 'gauges.dart';
import 'glass.dart';
import 'identicon.dart';

/// What one round's card shows. The numbers of the selected round come from
/// its contract when the chain could be read; the others are the server's.
class RoundCardInfo {
  const RoundCardInfo({
    required this.round,
    required this.totalCheckIns,
    required this.launched,
    required this.joined,
  });

  final Round round;
  final int totalCheckIns;
  final bool launched;

  /// This wallet has paid the round's deposit: "You're in".
  final bool joined;

  RoundPhase phaseAt(DateTime now) =>
      launched ? RoundPhase.launched : round.phaseAt(now);

  bool get barFull =>
      round.checkInGoal > 0 && totalCheckIns >= round.checkInGoal;

  /// 0 to 1: how full the bar is.
  double get progress => round.checkInGoal <= 0
      ? 0
      : (totalCheckIns / round.checkInGoal).clamp(0.0, 1.0);
}

/// The round cards at the top of Home: one card per round, swiped sideways,
/// with page dots under them. The card in view is the selected round.
///
/// The cards move on by themselves every [interval], but only until the
/// person first touches them (or the screen around them, [touched]), scrolls
/// the page they are on (by any means: a finger, a wheel, the keyboard, a
/// scroll bar), or opens anything over that page (a sheet, a dialog,
/// another screen, however it was opened). From then on they stay where the
/// person leaves them, for good, so the round under the screen's one action
/// never changes by itself once somebody is using the screen. A move that
/// had just begun when that happened is taken back. [onStopped] is told
/// once, when they stop.
/// They also do not move by themselves when [autoAdvance] is off, when the
/// system or the browser asks for reduced motion, when a screen reader is
/// on, while a mouse rests on them, or while [canAdvance] says no (and for
/// [hold] after it says yes again).
///
/// One round is a plain card: nothing to swipe, no dots.
class RoundSlider extends StatefulWidget {
  const RoundSlider({
    super.key,
    required this.cards,
    required this.index,
    required this.now,
    required this.onSelect,
    required this.onInvite,
    this.canAdvance,
    this.autoAdvance = true,
    this.onStopped,
    this.gutter = Space.gutter,
    this.interval = AppConfig.sliderInterval,
    this.hold = AppConfig.sliderHold,
  });

  final List<RoundCardInfo> cards;

  /// The selected card.
  final int index;
  final DateTime now;

  /// The card in view changed. [byPerson] is false when the cards moved by
  /// themselves.
  final void Function(int index, {required bool byPerson}) onSelect;
  final ValueChanged<Round> onInvite;

  /// Asked before each move the cards make by themselves.
  final bool Function()? canAdvance;

  /// False: the cards never move by themselves (the person has already
  /// touched the screen in this session, or came by a round's link).
  final bool autoAdvance;

  /// Told once, after the frame, when the cards stop moving by themselves
  /// for good, whatever stopped them. Home passes the app state's
  /// `stopAutoAdvance`, so a new slider (Home built again) stays still too.
  final VoidCallback? onStopped;

  /// The screen's side margin. The slider itself is as wide as the screen,
  /// so a card being swiped leaves at the screen's edge, not at the margin.
  final double gutter;
  final Duration interval;
  final Duration hold;

  /// A card's height at the normal text size.
  static const double cardHeight = 246;

  @override
  State<RoundSlider> createState() => RoundSliderState();
}

class RoundSliderState extends State<RoundSlider> {
  late final PageController _pages = PageController(initialPage: widget.index);
  Timer? _timer;

  /// Fingers (or a hovering mouse) on the screen right now.
  int _touches = 0;
  bool _hovered = false;

  /// The page the cards are being moved to (by themselves, or by a tap on
  /// a dot), while they move.
  int? _target;
  bool _targetByPerson = false;

  /// The last time the cards were due to move, [RoundSlider.canAdvance]
  /// said no (a sheet was open, something was being sent).
  bool _blocked = false;

  /// True while the slider is put on the selected card from outside.
  bool _syncing = false;

  /// Reduced motion or a screen reader: the cards never move by themselves.
  bool _still = false;

  /// The person has touched the cards or the screen around them: they never
  /// move by themselves again.
  bool _touched = false;

  bool get _many => widget.cards.length > 1;

  /// Whether the cards may move by themselves at all.
  bool get _auto => widget.autoAdvance && !_touched && !_still && _many;

  /// Whether a timer for the next move is running. For tests.
  @visibleForTesting
  bool get waiting => _timer != null;

  /// The page the slider is on scrolls: a person is using the screen.
  ScrollPosition? _page;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchPage(Scrollable.maybeOf(context)?.position);
    // Something was opened over the screen (a sheet, a dialog, another
    // screen), by a touch, the keyboard or the app itself.
    if (ModalRoute.isCurrentOf(context) == false) {
      touched();
      return;
    }
    final still = !context.motion || MediaQuery.accessibleNavigationOf(context);
    if (still != _still || _timer == null) {
      _still = still;
      _arm();
    }
  }

  void _watchPage(ScrollPosition? position) {
    if (identical(position, _page)) return;
    _page?.isScrollingNotifier.removeListener(_pageScrolled);
    _page = position;
    _page?.isScrollingNotifier.addListener(_pageScrolled);
  }

  void _pageScrolled() {
    if (_page?.isScrollingNotifier.value ?? false) touched();
  }

  @override
  void didUpdateWidget(RoundSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cards.length != widget.cards.length ||
        oldWidget.autoAdvance != widget.autoAdvance) {
      _arm();
    }
    // Selected from outside (a link, a new round, a new order): show it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted || !_many || !_pages.hasClients) return;
    if (_target != null || _touches > 0) return;
    final position = _pages.position;
    if (position.isScrollingNotifier.value) return;
    if (_pages.page?.round() == widget.index) return;
    _syncing = true;
    _pages.jumpToPage(widget.index);
    _syncing = false;
  }

  /// Starts the wait for the next move: [after], or the usual interval.
  void _arm([Duration? after]) {
    _timer?.cancel();
    _timer = null;
    if (!_auto || _touches > 0 || _hovered) return;
    _timer = Timer(after ?? widget.interval, _tick);
  }

  void _tick() {
    _timer = null;
    if (!mounted) return;
    if (!_auto) return;
    final allowed = _pages.hasClients && (widget.canAdvance?.call() ?? true);
    if (!allowed) {
      _blocked = true;
      _arm();
      return;
    }
    if (_blocked) {
      // Whatever was in the way has just gone (a sheet closed): the card
      // the person was dealing with stays a while longer.
      _blocked = false;
      _arm(widget.hold);
      return;
    }
    _moveTo(
      (widget.index + 1) % widget.cards.length,
      byPerson: false,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
    _arm();
  }

  /// Counts the moves, so a move that was replaced by a newer one does not
  /// clear the newer one's target when it ends.
  int _moves = 0;

  void _moveTo(
    int page, {
    required bool byPerson,
    required Duration duration,
    required Curve curve,
  }) {
    final move = ++_moves;
    _target = page;
    _targetByPerson = byPerson;
    _pages.animateToPage(page, duration: duration, curve: curve).whenComplete(
      () {
        if (_moves == move) _target = null;
      },
    );
  }

  /// The person touched the screen (a finger or a mouse button went down,
  /// or a wheel or trackpad scrolled): the cards never move by themselves
  /// again. If they had just begun to, they go back, so the selected round
  /// is still the one the person was looking at when they reached for it.
  void touched() {
    if (!_touched) {
      _touched = true;
      final told = widget.onStopped;
      // Never during a build: the state it tells may rebuild the screen.
      if (told != null) scheduleMicrotask(() => mounted ? told() : null);
    }
    _timer?.cancel();
    _timer = null;
    if (_target != null && !_targetByPerson && _pages.hasClients) {
      _moveTo(
        widget.index,
        byPerson: false,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// A finger went down somewhere on the screen.
  void touchDown() {
    _touches++;
    touched();
  }

  /// The finger lifted.
  void touchUp() {
    if (_touches > 0) _touches--;
  }

  void _hover(bool over) {
    if (_hovered == over) return;
    _hovered = over;
    if (over) {
      _timer?.cancel();
      _timer = null;
    } else {
      _arm(widget.hold);
    }
  }

  void _pageChanged(int page) {
    if (_syncing) return;
    final target = _target;
    // A move over several cards passes the ones in between.
    if (target != null && page != target) return;
    widget.onSelect(page, byPerson: target == null || _targetByPerson);
  }

  void _goTo(int page) {
    if (page == widget.index || !_pages.hasClients) return;
    HapticFeedback.selectionClick();
    if (context.motion) {
      _moveTo(
        page,
        byPerson: true,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pages.jumpToPage(page);
    }
  }

  @override
  void dispose() {
    _watchPage(null);
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.isEmpty) return const SizedBox.shrink();
    // Larger text makes the card taller, so nothing is cut.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final height = RoundSlider.cardHeight + 130 * (scale - 1).clamp(0.0, 1.0);

    Widget card(RoundCardInfo info) => RoundCard(
      key: ValueKey(info.round.id),
      info: info,
      now: widget.now,
      onInvite: () => widget.onInvite(info.round),
    );

    if (!_many) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.gutter),
        child: SizedBox(height: height, child: card(cards.single)),
      );
    }

    return Listener(
      onPointerDown: (_) => touchDown(),
      onPointerUp: (_) => touchUp(),
      onPointerCancel: (_) => touchUp(),
      child: MouseRegion(
        onEnter: (_) => _hover(true),
        onExit: (_) => _hover(false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              // A mouse can drag the cards too, as a finger does.
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: PointerDeviceKind.values.toSet(),
                  scrollbars: false,
                ),
                child: PageView.builder(
                  controller: _pages,
                  itemCount: cards.length,
                  onPageChanged: _pageChanged,
                  itemBuilder: (context, i) => Padding(
                    padding: EdgeInsets.symmetric(horizontal: widget.gutter),
                    child: card(cards[i]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.s2),
            _Dots(count: cards.length, index: widget.index, onTap: _goTo),
          ],
        ),
      ),
    );
  }
}

/// One dot per card; the selected one is a short volt bar.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.onTap});
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      key: const Key('round-dots'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == index,
            label: 'Round ${i + 1} of $count',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                child: AnimatedContainer(
                  key: Key('round-dot-$i'),
                  duration: context.motion
                      ? const Duration(milliseconds: 250)
                      : Duration.zero,
                  curve: Curves.easeOut,
                  width: i == index ? 20 : 7,
                  height: 7,
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: i == index
                        ? c.volt
                        : Colors.white.withValues(alpha: 0.22),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One round on glass: its name, where it stands, the bar, the prize so
/// far, the members, the deadline, and "Invite".
class RoundCard extends StatelessWidget {
  const RoundCard({
    super.key,
    required this.info,
    required this.now,
    required this.onInvite,
  });

  final RoundCardInfo info;
  final DateTime now;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final round = info.round;
    final phase = info.phaseAt(now);
    final (state, colour) = switch (phase) {
      RoundPhase.launched => ('Launched', c.success),
      RoundPhase.expired => ('Ended', c.danger),
      RoundPhase.open => info.barFull ? ('Bar full', c.volt) : ('Open', c.volt),
    };
    final when = switch (phase) {
      RoundPhase.launched => 'Live on Flap',
      RoundPhase.expired => 'Closed ${formatDate(round.deadline)}',
      RoundPhase.open => 'Closes ${formatDate(round.deadline)}',
    };
    final total = formatCount(info.totalCheckIns);
    final goal = formatCount(round.checkInGoal);
    final members = round.memberCount == 1
        ? '1 member'
        : '${formatCount(round.memberCount)} members';
    final quiet = t.body(13, FontWeight.w500).copyWith(color: c.text2);

    return Semantics(
      container: true,
      label:
          '${round.name}. $state. $total of $goal check-ins. $when. '
          '${info.joined ? 'You\'re in. ' : ''}'
          '${round.unlisted ? 'Unlisted. ' : ''}',
      child: GlassCard(
        // The top edge is 6 closer than the others: the "Invite" row is a
        // full touch target, 6 taller above and below the chip it draws.
        padding: const EdgeInsets.fromLTRB(18, 8, 14, 16),
        tint: info.joined ? c.volt.withValues(alpha: 0.28) : null,
        // Never an overflow stripe, however large the text is set.
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Overline(
                      round.featured ? 'Featured round' : 'Round',
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Invite to ${round.name}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const Key('round-invite'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onInvite,
                      // A 32-high chip in a touch target of [Sizes.touch].
                      child: const SizedBox(
                        height: Sizes.touch,
                        child: Center(
                          child: AppChip(
                            text: 'Invite',
                            icon: Icons.ios_share_rounded,
                            height: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  round.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.title(28),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: StatusBadge(text: state, color: colour),
                  ),
                  if (info.joined) ...[
                    const SizedBox(width: 6),
                    const Flexible(
                      flex: 4,
                      child: AppChip(
                        text: 'You\'re in',
                        icon: Icons.check_rounded,
                        height: 28,
                      ),
                    ),
                  ],
                  if (round.unlisted) ...[
                    const SizedBox(width: 6),
                    const Flexible(
                      flex: 4,
                      child: AppChip(
                        text: 'Unlisted',
                        icon: Icons.link_rounded,
                        height: 28,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              const Overline('The bar'),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TickGauge(
                  progress: info.progress,
                  height: 20,
                  label: '$total of $goal check-ins',
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$total / $goal check-ins',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t
                            .body(13, FontWeight.w600)
                            .copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                    const SizedBox(width: Space.s2),
                    Flexible(
                      child: Text(
                        when,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: quiet,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Prize so far '
                        '${formatMoney(round.prizeNow, AppConfig.quoteSymbol, maxFraction: 0)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: quiet.copyWith(color: c.text),
                      ),
                    ),
                    const SizedBox(width: Space.s2),
                    Flexible(
                      child: Text(
                        members,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: quiet,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
