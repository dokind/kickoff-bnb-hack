import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'common.dart';

/// What a round's share card says, worked out once from the app state so
/// the card itself only draws.
@immutable
class ShareCardData {
  const ShareCardData({
    required this.name,
    required this.badge,
    required this.season,
    required this.deposit,
    required this.total,
    required this.goal,
    required this.members,
    required this.everyDepositIsPrize,
    required this.endings,
    required this.link,
    required this.launcher,
  });

  /// The round as the app shows it now: the chain's count when this round
  /// is the selected one, else the server's.
  factory ShareCardData.of(AppState state, Round round, {String? link}) {
    final selected = state.selected == round.id;
    final total = selected ? state.totalCheckIns : round.totalCheckIns;
    final launched = selected ? state.launched : round.launched;
    final now = state.now;
    final ended = !launched && now.isAfter(round.deadline);
    final full = round.checkInGoal > 0 && total >= round.checkInGoal;
    final season = round.season;
    final String badge;
    var fromSeason = false;
    if (launched) {
      badge = 'Launched on Flap';
    } else if (ended) {
      badge = 'Ended · 100% back';
    } else if (season != null && !season.checkInsOver(now)) {
      fromSeason = true;
      badge = season.notStarted(now)
          ? '${season.name} · starts '
                '${formatWeekdayDayMonth(season.startsAt)}'
          : '${season.name} · day ${season.dayNumber(now)} of '
                '${season.dayCount}';
    } else {
      badge = full ? 'Bar full · ready to launch' : 'Open · join now';
    }
    return ShareCardData(
      name: round.name.trim().isEmpty ? 'A round' : round.name.trim(),
      badge: badge,
      season: fromSeason,
      deposit: formatTestUsd(state.depositOf(round.id)),
      total: total,
      goal: round.checkInGoal,
      members: round.memberCount,
      everyDepositIsPrize: round.liquidityBps == 0,
      endings: launched
          ? 'The bar filled: launched on Flap, split by days'
          : ended
          ? 'Fell short: everyone gets 100% back'
          : 'Fall short: 100% back · Fill it: launch on Flap, split by days',
      link: link ?? AppConfig.inviteLink(round.launcher),
      launcher: round.id,
    );
  }

  final String name;

  /// "Season 1 · starts Tue 1 Dec", or the round's state.
  final String badge;

  /// [badge] is about the Season.
  final bool season;

  /// "100 test USD".
  final String deposit;
  final int total;
  final int goal;
  final int members;

  /// None of the deposits goes to the shop (a sponsor fills it).
  final bool everyDepositIsPrize;

  /// The two endings in one line.
  final String endings;

  /// The round's link; empty in a build with no web address.
  final String link;
  final String launcher;

  /// What is shared and copied: the link, else the round's address.
  String get shared => link.isEmpty ? launcher : link;

  /// "3 / 12 check-ins".
  String get barText =>
      '${formatCount(total)} / ${formatCount(goal)} check-ins';

  double get progress => goal <= 0 ? 0 : (total / goal).clamp(0.0, 1.0);

  String get membersText =>
      members == 1 ? '1 member' : '${formatCount(members)} members';

  /// The link on short lines, the address cut in the middle:
  /// "dokind.github.io", "/kickoff-bnb-hack" and "#/r/0xcf79…5876".
  List<String> get shortLink {
    if (link.isEmpty) return [shortAddress(launcher)];
    final uri = Uri.tryParse(link);
    if (uri == null) return [link];
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final fragment = uri.fragment.replaceAllMapped(
      RegExp(r'0x[0-9a-fA-F]{40}'),
      (m) => shortAddress(m.group(0)!),
    );
    return [
      uri.host,
      if (path.isNotEmpty) path,
      if (fragment.isNotEmpty) '#$fragment',
    ];
  }

  /// The words that go with the image.
  String get message =>
      'Join "$name" on ${AppConfig.productName}: $deposit deposit, '
      '$barText so far. BSC testnet, test money. $shared';

  /// One sentence for screen readers: the card is drawn as a picture.
  String get description =>
      'Share card. $name. $badge. $deposit deposit. $barText. $membersText.'
      '${everyDepositIsPrize ? ' Every deposit is prize.' : ''} $endings. '
      'QR code of the round link. BSC testnet, test money.';

  /// "cypher-run-morning-movers.png".
  String get fileName {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'cypher-run-${slug.isEmpty ? 'round' : slug}.png';
  }
}

/// A round as a picture to post: portrait 4:5 at [ShareCard.size] logical
/// pixels, so it saves at 1080 by 1350 at 3x. Dark ink, one volt accent,
/// nothing smaller than 12. It ignores the text size setting: it is an
/// image, the same for everyone who sees it.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data});
  final ShareCardData data;

  static const size = Size(360, 450);

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox.fromSize(
        size: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.slate, c.ink, c.inkDeep],
              stops: const [0, 0.55, 1],
            ),
          ),
          child: Stack(
            children: [
              // Two soft lights: volt top right, steel bottom left.
              Positioned(
                right: -120,
                top: -140,
                child: _Glow(color: c.volt.withValues(alpha: 0.30), size: 340),
              ),
              Positioned(
                left: -140,
                bottom: -150,
                child: _Glow(color: c.steel.withValues(alpha: 0.9), size: 360),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Logomark(size: 16),
                        const SizedBox(width: 8),
                        Text(
                          AppConfig.productName.toUpperCase(),
                          style: t
                              .body(14, FontWeight.w800)
                              .copyWith(letterSpacing: 3, height: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      data.name,
                      key: const Key('share-card-name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.title(28).copyWith(height: 1.08),
                    ),
                    const SizedBox(height: 8),
                    _Badge(text: data.badge, strong: data.season),
                    const SizedBox(height: 10),
                    // The rest sits at the bottom. With a very wide font it
                    // is scaled down a little rather than cut off.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: SizedBox(
                            width: box.maxWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Panel(data: data),
                                const SizedBox(height: 10),
                                Text(
                                  data.endings,
                                  key: const Key('share-card-endings'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t
                                      .body(13, FontWeight.w500)
                                      .copyWith(color: c.text2, height: 1.3),
                                ),
                                const SizedBox(height: 12),
                                _Footer(data: data),
                              ],
                            ),
                          ),
                        ),
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

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.strong});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const Key('share-card-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: strong ? c.volt : Colors.white.withValues(alpha: 0.10),
        shape: StadiumBorder(
          side: strong ? BorderSide.none : BorderSide(color: c.hairline),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.type
            .body(13, FontWeight.w700)
            .copyWith(color: strong ? c.onVolt : c.text, height: 1.1),
      ),
    );
  }
}

/// The bar, the deposit and the members, on a pane of glass.
class _Panel extends StatelessWidget {
  const _Panel({required this.data});
  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.barText,
            key: const Key('share-card-bar'),
            style: t.body(20, FontWeight.w700).copyWith(height: 1.1),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: data.progress == 0 ? 0.012 : data.progress,
                    heightFactor: 1,
                    child: ColoredBox(color: c.volt),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Fact(
                  label: 'Deposit',
                  value: data.deposit,
                  valueKey: const Key('share-card-deposit'),
                ),
              ),
              const SizedBox(width: 12),
              _Fact(
                label: 'Members',
                value: '${data.members}',
                valueKey: const Key('share-card-members'),
              ),
            ],
          ),
          if (data.everyDepositIsPrize) ...[
            const SizedBox(height: 10),
            Row(
              key: const Key('share-card-prize'),
              children: [
                Icon(Icons.shield_outlined, size: 16, color: c.volt),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Every deposit is prize',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body(14, FontWeight.w700).copyWith(color: c.volt),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.valueKey});
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: t
              .body(12, FontWeight.w600)
              .copyWith(color: context.colors.text2, letterSpacing: 1.2),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          key: valueKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.body(16, FontWeight.w600),
        ),
      ],
    );
  }
}

/// The QR code of the link, the link in short and "BSC testnet · test
/// money".
class _Footer extends StatelessWidget {
  const _Footer({required this.data});
  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: QrImageView(
            key: const Key('share-card-qr'),
            data: data.shared,
            size: 84,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan to join',
                style: t.body(15, FontWeight.w700).copyWith(height: 1.1),
              ),
              const SizedBox(height: 4),
              for (final line in data.shortLink)
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.mono.copyWith(
                    fontSize: 12,
                    color: c.text2,
                    height: 1.3,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'BSC testnet · test money',
                key: const Key('share-card-footer'),
                style: t.body(12, FontWeight.w600).copyWith(color: c.text2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
