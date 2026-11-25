import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'aurora.dart';
import 'controls.dart';
import 'glass.dart';

export 'aurora.dart';
export 'controls.dart';
export 'glass.dart';

/// Keeps the phone layout on wide screens (the web build on a laptop, a
/// tablet): the app sits in a centred column of at most [maxWidth]. Narrower
/// screens are not changed.
class CenteredColumn extends StatelessWidget {
  const CenteredColumn({super.key, required this.child});
  final Widget child;

  static const double maxWidth = Sizes.column;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// What sits behind and above every screen: the aurora across the whole
/// window, the app in its centred column, and the message banner on top.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: AuroraBackground(
      child: CenteredColumn(
        child: Stack(
          children: [
            child,
            const Positioned(top: 0, left: 0, right: 0, child: BannerHost()),
          ],
        ),
      ),
    ),
  );
}

// Messages --------------------------------------------------------------------

enum BannerKind { success, error, info }

/// One message for the banner at the top of the app.
class BannerNote {
  BannerNote(this.kind, this.text);
  final BannerKind kind;
  final String text;
}

/// The message being shown, or null. [showMessage] sets it; [BannerHost]
/// draws it and clears it after a few seconds.
final ValueNotifier<BannerNote?> bannerNote = ValueNotifier(null);

/// Shows one sentence in the banner at the top of the app.
void showMessage(
  BuildContext context,
  String text, {
  BannerKind kind = BannerKind.info,
}) => bannerNote.value = BannerNote(kind, text);

/// Shows what went wrong as one sentence, never a raw exception.
void showError(BuildContext context, Object error) =>
    showMessage(context, friendlyError(error), kind: BannerKind.error);

/// The glass capsule that drops in from the top with a message. Tap it to
/// dismiss; it leaves by itself after five seconds.
class BannerHost extends StatefulWidget {
  const BannerHost({super.key});

  @override
  State<BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends State<BannerHost>
    with SingleTickerProviderStateMixin {
  /// Runs from 0 to 1 over the banner's whole life: in, stay, out.
  late final _life = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  BannerNote? _shown;

  @override
  void initState() {
    super.initState();
    bannerNote.addListener(_changed);
    _life.addStatusListener((status) {
      if (status == AnimationStatus.completed) bannerNote.value = null;
    });
  }

  void _changed() {
    final note = bannerNote.value;
    if (note == null) {
      _life.stop();
      setState(() => _shown = null);
      return;
    }
    setState(() => _shown = note);
    _life.forward(from: 0);
  }

  @override
  void dispose() {
    bannerNote.removeListener(_changed);
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = _shown;
    if (note == null) return const SizedBox.shrink();
    final c = context.colors;
    final (icon, colour) = switch (note.kind) {
      BannerKind.success => (Icons.check_circle_rounded, c.volt),
      BannerKind.error => (Icons.warning_amber_rounded, c.danger),
      BannerKind.info => (Icons.info_rounded, c.text),
    };
    // In over the first 6%, out over the last 6%.
    final shown = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 6),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 88),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 6),
    ]).animate(_life);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 6, Space.gutter, 0),
        child: FadeTransition(
          opacity: shown,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -0.4),
              end: Offset.zero,
            ).animate(shown),
            child: Semantics(
              liveRegion: true,
              child: GestureDetector(
                onTap: () => bannerNote.value = null,
                child: GlassSurface(
                  radius: 26,
                  tint: c.ink.withValues(alpha: 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: colour),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            note.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.type.body(14, FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Sheets ----------------------------------------------------------------------

/// Opens a sheet from the bottom with its own aurora, 40px top corners and a
/// grab handle. [tall] sheets take most of the screen; the others wrap what
/// they hold.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  isDismissible: dismissible,
  enableDrag: dismissible,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: 0.55),
  builder: builder,
);

/// The body of a sheet opened with [showAppSheet].
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.child,
    this.palette = AuroraPalette.steel,
    this.tall = true,
  });

  final Widget child;
  final AuroraPalette palette;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final content = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          Space.s3,
          Space.gutter,
          Space.s4 + media.viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: tall ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: ShapeDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(height: Space.s5),
            if (tall)
              Expanded(child: child)
            else
              Flexible(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: Sizes.column,
        maxHeight: media.size.height * 0.92,
        minHeight: tall ? media.size.height * 0.92 : 0,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: AuroraBackground(palette: palette)),
            content,
          ],
        ),
      ),
    );
  }
}

// Small pieces ----------------------------------------------------------------

/// The scrim behind an action pinned to the bottom of a screen. It rises
/// from clear to the background colour over its first [rise] pixels and is
/// opaque below that, so nothing scrolling under the action shows through
/// its text. The action leaves [rise] of padding above itself.
class BottomFade extends StatelessWidget {
  const BottomFade({super.key, required this.child, this.rise = defaultRise});
  final Widget child;

  /// Height of the clear-to-opaque part at the top.
  final double rise;

  static const double defaultRise = 48;

  /// How opaque the scrim is [dy] pixels below its top edge: 0 at the edge,
  /// 1 from [rise] down.
  static double opacityAt(double dy, {double rise = defaultRise}) {
    if (dy <= 0) return 0;
    if (dy >= rise) return 1;
    final t = dy / rise;
    // The gradient's middle stop: 72% at 55% of the way.
    return t < 0.55 ? 0.72 * t / 0.55 : 0.72 + 0.28 * (t - 0.55) / 0.45;
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.ink;
    Widget scrim = LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight;
        final end = height <= 0 ? 1.0 : (rise / height).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ink.withValues(alpha: 0),
                ink.withValues(alpha: 0.72),
                ink,
                ink,
              ],
              stops: [0, end * 0.55, end, 1],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
    // In the centred column of a wide window the scrim would end in two
    // hard vertical edges, so it thins out inside the side margins. It is
    // whole again before the content starts.
    final width = MediaQuery.sizeOf(context).width;
    if (width > Sizes.column) {
      const soft = Space.gutter / Sizes.column;
      scrim = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, soft, 1 - soft, 1],
        ).createShader(rect),
        child: scrim,
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: IgnorePointer(child: scrim)),
        child,
      ],
    );
  }
}

/// Tells [onSize] how large its child was laid out, after the frame. Home
/// uses it to leave room under its scrolling content for the floating
/// action, whatever that holds.
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) => (renderObject as _RenderSizeReporter).onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);
  ValueChanged<Size> onSize;
  Size? _told;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _told) return;
    _told = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(size);
    });
  }
}

/// Something could not be loaded: one sentence and a way to try again.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: c.danger),
              const SizedBox(width: Space.s2),
              Expanded(child: Text(text, style: context.type.body(15))),
            ],
          ),
          const SizedBox(height: Space.s4),
          PillButton(
            kind: PillKind.glass,
            height: Sizes.buttonSmall,
            icon: Icons.refresh_rounded,
            label: 'Retry',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// A sentence that went wrong inside a flow, with its icon. The flow's own
/// button becomes "Retry".
class ErrorLine extends StatelessWidget {
  const ErrorLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: context.colors.danger,
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Text(text, style: context.type.body(14, FontWeight.w500)),
        ),
      ],
    ),
  );
}

/// A line that opens a web page (a transaction or an address on BscScan
/// testnet, a token on Flap): what it is, a short value and an "open" icon.
/// If the page cannot be opened its address is copied instead.
class LinkRow extends StatelessWidget {
  const LinkRow({
    super.key,
    required this.label,
    required this.url,
    this.value,
  });

  final String label;
  final String url;

  /// A hash or an address, shown shortened.
  final String? value;

  Future<void> _open(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) showMessage(context, 'Link copied.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Semantics(
      link: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.touch),
          child: Row(
            children: [
              Expanded(child: Text(label, style: t.body(15, FontWeight.w500))),
              if (value != null) ...[
                const SizedBox(width: Space.s2),
                Text(shortAddress(value!), style: t.mono),
              ],
              const SizedBox(width: Space.s2),
              Icon(Icons.open_in_new_rounded, size: 18, color: c.text2),
            ],
          ),
        ),
      ),
    );
  }
}
