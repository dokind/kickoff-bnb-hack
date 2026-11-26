import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/card_sharer.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/share_card.dart';

/// Opens "Share this round": a live preview of the round's share card, and
/// Share, Copy link and (in a browser) Save image.
Future<void> showShareSheet(
  BuildContext context,
  AppState state,
  Round round, {
  CardSharer? sharer,
}) => showAppSheet<void>(
  context,
  builder: (_) => ShareSheet(state: state, round: round, sharer: sharer),
);

/// The body of the share sheet. The card is drawn by [ShareCard] inside a
/// [RepaintBoundary] and turned into a PNG at 3x when it is shared or saved.
class ShareSheet extends StatefulWidget {
  const ShareSheet({
    super.key,
    required this.state,
    required this.round,
    this.link,
    this.sharer,
  });
  final AppState state;
  final Round round;

  /// Defaults to the round's invite link; a parameter so tests can set it.
  final String? link;

  /// Defaults to [cardSharer].
  final CardSharer? sharer;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final _card = GlobalKey();
  final _shareButton = GlobalKey();
  bool _busy = false;
  String? _error;

  CardSharer get _sharer => widget.sharer ?? cardSharer;

  /// The card as PNG bytes at 3x (1080 by 1350).
  Future<Uint8List> _png() async {
    final boundary =
        _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('The card is not on screen.');
    var needsPaint = false;
    assert(() {
      needsPaint = boundary.debugNeedsPaint;
      return true;
    }());
    if (needsPaint) await WidgetsBinding.instance.endOfFrame;
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('No image data.');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Where the Share button is, for an iPad's share popover.
  Rect? get _origin {
    final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _copy(ShareCardData data, {String? message}) async {
    await Clipboard.setData(ClipboardData(text: data.shared));
    if (mounted) showMessage(context, message ?? 'Link copied.');
  }

  Future<void> _guard(Future<void> Function() action, String failed) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(ShareCardData data) => _guard(() async {
    final png = await _png();
    final outcome = await _sharer.share(
      png: png,
      fileName: data.fileName,
      text: data.message,
      origin: _origin,
    );
    if (!mounted) return;
    if (outcome == ShareOutcome.downloaded) {
      // A browser that cannot share an image: the card is downloaded, and
      // the link goes on the clipboard to paste beside it.
      try {
        await _copy(
          data,
          message:
              'This browser can\'t share images. The card was downloaded '
              'and the link copied.',
        );
      } catch (_) {
        if (mounted) {
          showMessage(
            context,
            'This browser can\'t share images. The card was downloaded.',
          );
        }
      }
    }
  }, 'Could not share the card. Copy the link instead.');

  Future<void> _save(ShareCardData data) => _guard(() async {
    final png = await _png();
    if (!await _sharer.save(png, data.fileName)) {
      throw StateError('not saved');
    }
    if (mounted) showMessage(context, 'Card image downloaded.');
  }, 'Could not save the image. Try Share or Copy link.');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final t = context.type;
      final c = context.colors;
      final data = ShareCardData.of(
        widget.state,
        widget.round,
        link: widget.link,
      );
      return SheetFrame(
        tall: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Overline('Share'),
            const SizedBox(height: Space.s1),
            Semantics(
              header: true,
              child: Text('Share this round', style: t.title(28)),
            ),
            const SizedBox(height: Space.s4),
            Center(
              child: LayoutBuilder(
                builder: (context, box) {
                  final width = box.maxWidth.clamp(0.0, ShareCard.size.width);
                  return Semantics(
                    image: true,
                    label: data.description,
                    excludeSemantics: true,
                    child: SizedBox(
                      key: const Key('share-preview'),
                      width: width,
                      height: width / ShareCard.size.aspectRatio,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: FittedBox(
                          child: RepaintBoundary(
                            key: _card,
                            child: ShareCard(data: data),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Space.s4),
            if (_error != null) ...[
              ErrorLine(_error!),
              const SizedBox(height: Space.s3),
            ],
            PillButton(
              key: _shareButton,
              kind: PillKind.volt,
              icon: Icons.ios_share_rounded,
              label: 'Share',
              busy: _busy,
              busyLabel: 'Making the card…',
              onPressed: () => _share(data),
            ),
            const SizedBox(height: Space.s3),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    key: const Key('share-copy'),
                    kind: PillKind.glass,
                    height: Sizes.buttonSmall,
                    icon: Icons.link_rounded,
                    label: 'Copy link',
                    onPressed: () => _copy(data).catchError((Object _) {
                      if (mounted) {
                        setState(
                          () => _error =
                              'Could not copy. The link is '
                              '${data.shared}',
                        );
                      }
                    }),
                  ),
                ),
                if (_sharer.canSave) ...[
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: PillButton(
                      key: const Key('share-save'),
                      kind: PillKind.glass,
                      height: Sizes.buttonSmall,
                      icon: Icons.download_rounded,
                      label: 'Save image',
                      onPressed: _busy ? null : () => _save(data),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.s2),
            Text(
              'Test money on BSC testnet. The link opens the round.',
              textAlign: TextAlign.center,
              style: t.body(13).copyWith(color: c.text2),
            ),
          ],
        ),
      );
    },
  );
}
