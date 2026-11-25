import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'glass.dart';

/// What a control is pressed through. A touch, a mouse, the keyboard (Tab
/// to it, then Enter or Space) and a screen reader all end in [onPressed].
///
/// It is one node for a screen reader: [label] with its role and state, and
/// a tap action of its own. What is drawn inside is not read out a second
/// time. Reached from a keyboard it draws a ring in [ink], the colour of
/// the control's own text, just inside its [shape] (outside it when
/// [ringInset] is negative).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
    this.ink,
    this.shape = const StadiumBorder(),
    this.ringInset = 3,
    this.button = true,
    this.link = false,
    this.selected,
    this.toggled,
    this.expanded,
    this.onDown,
  });

  /// What a screen reader says.
  final String label;

  /// Null: the control cannot be pressed or reached, and says so.
  final VoidCallback? onPressed;
  final Widget child;

  /// The focus ring's colour; the theme's text colour when not given.
  final Color? ink;
  final ShapeBorder shape;
  final double ringInset;

  /// Roles and states for screen readers. A switch is not a [button]; it
  /// says [toggled]. A choice says whether it is [selected].
  final bool button;
  final bool link;
  final bool? selected;
  final bool? toggled;

  /// For a control that opens and closes something: whether it is open.
  final bool? expanded;

  /// Told while a finger or the mouse button is down on it.
  final ValueChanged<bool>? onDown;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  /// Reached from the keyboard: the ring is drawn.
  bool _ring = false;

  @override
  Widget build(BuildContext context) {
    final press = widget.onPressed;
    final down = widget.onDown;
    final can = press != null;
    return Semantics(
      container: true,
      button: widget.button ? true : null,
      link: widget.link ? true : null,
      enabled: widget.button ? can : null,
      selected: widget.selected,
      toggled: widget.toggled,
      expanded: widget.expanded,
      label: widget.label,
      // The detector's focus and the gesture's tap action join this node.
      child: FocusableActionDetector(
        enabled: can,
        mouseCursor: can ? SystemMouseCursors.click : MouseCursor.defer,
        actions: {
          // Space, and Enter outside a browser.
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => press?.call(),
          ),
          // Enter in a browser.
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) => press?.call(),
          ),
        },
        onShowFocusHighlight: (show) {
          if (show != _ring) setState(() => _ring = show);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: can && down != null ? (_) => down(true) : null,
          onTapCancel: can && down != null ? () => down(false) : null,
          onTapUp: can && down != null ? (_) => down(false) : null,
          onTap: press,
          child: ExcludeSemantics(
            child: CustomPaint(
              foregroundPainter: _ring
                  ? _FocusRingPainter(
                      shape: widget.shape,
                      inset: widget.ringInset,
                      color: widget.ink ?? context.colors.text,
                    )
                  : null,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A 2px line following [shape], [inset] inside the control's edge.
class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({
    required this.shape,
    required this.inset,
    required this.color,
  });

  final ShapeBorder shape;
  final double inset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(inset);
    if (rect.isEmpty) return;
    canvas.drawPath(
      shape.getOuterPath(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) =>
      old.shape != shape || old.inset != inset || old.color != color;
}

/// The four pills. [primary] is white, [volt] is the accent with a glow (the
/// money actions), [glass] is the quiet one, [danger] is glass with red ink.
enum PillKind { primary, volt, glass, danger }

/// A full-width pill button. While [busy] it shows a spinner beside
/// [busyLabel] and cannot be pressed. Disabled it fades to 45%. Like every
/// control here it is pressed through a [Pressable]: by touch, from the
/// keyboard and by a screen reader.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = PillKind.primary,
    this.icon,
    this.busy = false,
    this.busyLabel,
    this.height = Sizes.button,
    this.shrink,
  });

  final String label;

  /// A part of [label] that gives way when the label is wider than the
  /// button: a round's name in "Join Demo Day · 500 USD". It is cut short
  /// with an ellipsis and the words around it (the action, the amount) stay.
  /// Screen readers always get the whole label.
  final String? shrink;
  final VoidCallback? onPressed;
  final PillKind kind;
  final IconData? icon;
  final bool busy;
  final String? busyLabel;
  final double height;

  /// [label] as it is drawn in [width]: whole when it fits, else with
  /// [shrink] cut to as many characters as fit, followed by an ellipsis.
  /// [widthOf] measures a line of text.
  static String fitLabel(
    String label,
    String? shrink,
    double width,
    double Function(String text) widthOf,
  ) {
    if (shrink == null || shrink.isEmpty) return label;
    final at = label.indexOf(shrink);
    if (at < 0 || widthOf(label) <= width) return label;
    final head = label.substring(0, at);
    final tail = label.substring(at + shrink.length);
    final letters = shrink.characters;
    if (letters.length < 2) return label;
    String cut(int n) => '$head${letters.take(n).toString().trimRight()}…$tail';
    // The most letters of the name that still fit: at least one.
    var low = 1;
    var high = letters.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (widthOf(cut(mid)) <= width) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return cut(low);
  }

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _down = false;

  /// How wide [text] is on one line, as the label draws it.
  static double _widthOf(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null && !widget.busy;
    final ink = switch (widget.kind) {
      PillKind.primary || PillKind.volt => c.onVolt,
      PillKind.glass => c.text,
      PillKind.danger => c.danger,
    };
    final style = context.type.body(16, FontWeight.w600).copyWith(color: ink);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.busy) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: ink),
          ),
          const SizedBox(width: 10),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: ink),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: widget.busy || widget.shrink == null
              ? Text(
                  widget.busy
                      ? (widget.busyLabel ?? widget.label)
                      : widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                )
              : LayoutBuilder(
                  builder: (context, box) => Text(
                    PillButton.fitLabel(
                      widget.label,
                      widget.shrink,
                      box.maxWidth,
                      (text) => _widthOf(context, text, style),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
        ),
      ],
    );
    final face = SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s5),
        child: Center(child: label),
      ),
    );
    final Widget body = switch (widget.kind) {
      PillKind.primary => DecoratedBox(
        decoration: ShapeDecoration(
          color: c.text,
          shape: const StadiumBorder(),
        ),
        child: face,
      ),
      PillKind.volt => DecoratedBox(
        decoration: ShapeDecoration(
          color: c.volt,
          shape: const StadiumBorder(),
          shadows: [
            BoxShadow(
              color: c.volt.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: face,
      ),
      PillKind.glass || PillKind.danger => GlassSurface.pill(child: face),
    };
    return Pressable(
      label: widget.busy ? (widget.busyLabel ?? widget.label) : widget.label,
      ink: ink,
      onDown: (down) => setState(() => _down = down),
      onPressed: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onPressed!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: widget.onPressed == null && !widget.busy ? 0.45 : 1,
          duration: const Duration(milliseconds: 200),
          child: body,
        ),
      ),
    );
  }
}

/// A round glass icon button (back, copy, refresh).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = Sizes.touch,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    // The button says its own name.
    excludeFromSemantics: true,
    child: Pressable(
      label: tooltip,
      shape: const CircleBorder(),
      onPressed: onPressed,
      child: GlassSurface.pill(
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 18, color: context.colors.text),
        ),
      ),
    ),
  );
}

/// A small capsule: a fact ("6 days", "1,000 USD deposit") or, with
/// [selected], the chosen option in a [ChipPicker].
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.text,
    this.icon,
    this.selected = false,
    this.height = 34,
    this.minWidth = 0,
  });

  final String text;
  final IconData? icon;
  final bool selected;
  final double height;

  /// The narrowest the chip gets, so a chip that says "3" is still easy to
  /// press. Its text is centred.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = selected ? c.onVolt : c.text;
    final face = ConstrainedBox(
      constraints: BoxConstraints.tightFor(
        height: height,
      ).copyWith(minWidth: minWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: ink),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type
                    .body(13, FontWeight.w500)
                    .copyWith(color: ink, height: 1),
              ),
            ),
          ],
        ),
      ),
    );
    return selected
        ? DecoratedBox(
            decoration: ShapeDecoration(
              color: c.text,
              shape: const StadiumBorder(),
            ),
            child: face,
          )
        : GlassSurface.pill(blur: false, child: face);
  }
}

/// A row of chips, one of them chosen.
class ChipPicker<T> extends StatelessWidget {
  const ChipPicker({
    super.key,
    required this.options,
    required this.selection,
    required this.label,
    required this.onChanged,
    this.semanticLabel,
    this.height = 34,
    this.minWidth = 0,
    this.wrap = false,
  });

  final List<T> options;
  final T selection;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  /// What a screen reader says for an option when the chip alone ("6") does
  /// not say what it is ("6 check-ins").
  final String Function(T)? semanticLabel;

  /// Each chip's height and smallest width. A form whose chips are its
  /// main controls makes them a full touch target.
  final double height;
  final double minWidth;

  /// False: one row that scrolls sideways when the chips do not fit. True:
  /// the chips that do not fit go on a second row, so every option is on
  /// the screen and can be reached with a mouse or a keyboard-driven
  /// screen reader without scrolling sideways.
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chips = [
      for (final option in options)
        Pressable(
          label: semanticLabel?.call(option) ?? label(option),
          selected: option == selection,
          ink: option == selection ? c.onVolt : c.text,
          onPressed: () {
            HapticFeedback.selectionClick();
            onChanged(option);
          },
          child: AppChip(
            text: label(option),
            selected: option == selection,
            height: height,
            minWidth: minWidth,
          ),
        ),
    ];
    if (wrap) {
      return Wrap(spacing: Space.s2, runSpacing: Space.s2, children: chips);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, chip) in chips.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s2),
            chip,
          ],
        ],
      ),
    );
  }
}

/// The "On / Off" capsule switch, with its label on the left.
class CapsuleToggle extends StatelessWidget {
  const CapsuleToggle({
    super.key,
    required this.title,
    this.detail,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Pressable(
      // A switch, not a button: it says whether it is on, and what that
      // means.
      button: false,
      toggled: value,
      label: detail == null ? title : '$title. $detail',
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.sm)),
      ),
      // Around the whole row, clear of its words.
      ringInset: -8,
      onPressed: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.body(15, FontWeight.w600)),
                if (detail != null)
                  Text(detail!, style: t.body(12).copyWith(color: c.text2)),
              ],
            ),
          ),
          const SizedBox(width: Space.s3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 64,
            height: 34,
            padding: const EdgeInsets.all(4),
            decoration: ShapeDecoration(
              color: value
                  ? c.volt.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.12),
              shape: const StadiumBorder(),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: value
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Text(
                      value ? 'On' : 'Off',
                      style: t
                          .body(11, FontWeight.w600)
                          .copyWith(
                            color: value
                                ? c.onVolt.withValues(alpha: 0.7)
                                : c.text2,
                            height: 1,
                          ),
                    ),
                  ),
                ),
                AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: value ? c.onVolt : c.text,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A text field on glass, 54 high (64 when [large]) with 18px corners.
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.label,
    this.mono = false,
    this.number = false,
    this.onChanged,
    this.suffix,
    this.fieldKey,
    this.focusNode,
    this.large = false,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final TextEditingController controller;

  /// So a form can put the cursor back in the field it needs filled in.
  final FocusNode? focusNode;

  /// The one field a screen is about (a round's name): taller, and set in
  /// the title type the name is shown in everywhere else.
  final bool large;

  /// The room kept around the cursor when the field scrolls itself into
  /// view. A screen with an action pinned over its list keeps more below.
  final EdgeInsets scrollPadding;
  final String placeholder;

  /// Key of the inner text field, so tests can type into it.
  final Key? fieldKey;

  /// The field's name for screen readers; the visible label is an
  /// [Overline] above the field.
  final String? label;
  final bool mono;
  final bool number;
  final ValueChanged<String>? onChanged;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final style = mono
        ? t.mono.copyWith(fontSize: 15)
        : large
        ? t.title(26)
        : t.body(16);
    final field = TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      style: style,
      scrollPadding: scrollPadding,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: placeholder,
        // A placeholder is a sentence to read ("Paste the link"), so at
        // body size it is as strong as the app's other quiet sentences. In
        // the large title type the fainter tone is enough to read, and
        // keeps an example name from looking typed in.
        hintStyle: style.copyWith(color: large ? c.text3 : c.text2),
        suffixText: suffix,
        suffixStyle: t.body(14).copyWith(color: c.text2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    );
    return Semantics(
      label: label,
      child: GlassSurface(
        radius: Radii.md,
        child: SizedBox(
          height: large ? 64 : 54,
          child: Center(child: field),
        ),
      ),
    );
  }
}

/// Small uppercase tracked label: "TODAY", "PRIZE SO FAR".
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: context.type.overline.copyWith(color: color),
  );
}

/// Which round a sheet or a screen is about, above its title: "ROUND" and
/// the round's name as it was written, on one line.
class RoundLabel extends StatelessWidget {
  const RoundLabel(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Round: $name',
    excludeSemantics: true,
    child: Row(
      children: [
        const Overline('Round'),
        const SizedBox(width: Space.s2),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.type
                .body(15, FontWeight.w600)
                .copyWith(color: context.colors.volt),
          ),
        ),
      ],
    ),
  );
}

/// A section title with an optional quiet value on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: context.type.title(22)),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: context.type.body(13).copyWith(color: context.colors.text2),
        ),
    ],
  );
}

/// A label on the left and its value on the right, with a hairline under it
/// unless it is the [last] row of its card.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.last = false});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Text(label, style: t.body(14).copyWith(color: c.text2)),
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                flex: 6,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: t.body(14, FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (!last)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: c.hairline),
          ),
      ],
    );
  }
}

/// An icon in a small circle beside one sentence: a rule, a permission.
class IconRow extends StatelessWidget {
  const IconRow({
    super.key,
    required this.icon,
    required this.text,
    this.title,
    this.last = false,
  });

  final IconData icon;

  /// With a [title] the row has a strong first line and [text] under it.
  final String? title;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: c.text),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: title == null
                    ? Text(text, style: t.body(14).copyWith(color: c.text2))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: t.body(15, FontWeight.w600)),
                          Text(
                            text,
                            style: t.body(13).copyWith(color: c.text2),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        if (!last)
          Padding(
            padding: const EdgeInsets.only(left: 62),
            child: Divider(color: c.hairline),
          ),
      ],
    );
  }
}

/// A row that does something when pressed: an icon (or any [leading]), a
/// title, one quiet sentence under it, and on the right a short [value] and
/// a chevron (or another [trailingIcon]). When the title and the value do
/// not fit on one line the value goes under the title. The whole row is the
/// target, at least [minHeight] high, and it can be reached and pressed
/// from a keyboard. Rows stacked in one card draw a hairline between them
/// unless [last].
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.title,
    required this.onPressed,
    this.detail,
    this.icon,
    this.leading,
    this.value,
    this.trailingIcon = Icons.chevron_right_rounded,
    this.semanticLabel,
    this.expanded,
    this.last = true,
    this.minHeight = 64,
  });

  final String title;
  final String? detail;
  final VoidCallback onPressed;

  /// Drawn in a small circle on the left. [leading] replaces it.
  final IconData? icon;
  final Widget? leading;

  /// A short value on the right, in the address type: "0x1234…abcd".
  final String? value;
  final IconData trailingIcon;

  /// What a screen reader says; the title and the sentence when not given.
  final String? semanticLabel;

  /// For a row that opens and closes what is under it: whether it is open
  /// now. Screen readers say so.
  final bool? expanded;
  final bool last;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    void press() {
      HapticFeedback.selectionClick();
      onPressed();
    }

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: t.body(15, FontWeight.w600)),
        if (detail != null)
          Text(detail!, style: t.body(13).copyWith(color: c.text2)),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: semanticLabel ?? (detail == null ? title : '$title. $detail'),
          onTap: press,
          excludeSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: press,
              focusColor: Colors.white.withValues(alpha: 0.10),
              hoverColor: Colors.white.withValues(alpha: 0.04),
              highlightColor: Colors.white.withValues(alpha: 0.06),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      if (leading != null || icon != null) ...[
                        leading ??
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, size: 16, color: c.text),
                            ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: value == null
                            ? words
                            // The value sits at the right of the title. On
                            // a narrow screen with large text, where the
                            // two do not fit on one line, it goes under
                            // the title and both stay whole.
                            : Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: Space.s3,
                                runSpacing: 2,
                                children: [
                                  words,
                                  Text(
                                    value!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.mono.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(width: Space.s2),
                      Icon(trailingIcon, size: 20, color: c.text2),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!last)
          Padding(
            padding: EdgeInsets.only(
              left: leading != null || icon != null ? 62 : 16,
            ),
            child: Divider(color: c.hairline),
          ),
      ],
    );
  }
}
