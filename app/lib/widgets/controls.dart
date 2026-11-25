import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'glass.dart';

/// The four pills. [primary] is white, [volt] is the accent with a glow (the
/// money actions), [glass] is the quiet one, [danger] is glass with red ink.
enum PillKind { primary, volt, glass, danger }

/// A full-width pill button. While [busy] it shows a spinner beside
/// [busyLabel] and cannot be pressed. Disabled it fades to 45%.
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
  });

  final String label;
  final VoidCallback? onPressed;
  final PillKind kind;
  final IconData? icon;
  final bool busy;
  final String? busyLabel;
  final double height;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null && !widget.busy;
    final ink = switch (widget.kind) {
      PillKind.primary || PillKind.volt => c.onVolt,
      PillKind.glass => c.text,
      PillKind.danger => c.danger,
    };
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
          child: Text(
            widget.busy ? (widget.busyLabel ?? widget.label) : widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.type.body(16, FontWeight.w600).copyWith(color: ink),
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
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.busy ? (widget.busyLabel ?? widget.label) : widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
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
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: GlassSurface.pill(
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 18, color: context.colors.text),
          ),
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
  });

  final String text;
  final IconData? icon;
  final bool selected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = selected ? c.onVolt : c.text;
    final face = SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
  });

  final List<T> options;
  final T selection;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (i, option) in options.indexed) ...[
          if (i > 0) const SizedBox(width: Space.s2),
          Semantics(
            button: true,
            selected: option == selection,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(option);
              },
              child: AppChip(
                text: label(option),
                selected: option == selection,
              ),
            ),
          ),
        ],
      ],
    ),
  );
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
    return Semantics(
      toggled: value,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
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
      ),
    );
  }
}

/// A text field on glass, 54 high with 18px corners.
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
  });

  final TextEditingController controller;
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
    final style = mono ? t.mono.copyWith(fontSize: 15) : t.body(16);
    final field = TextField(
      key: fieldKey,
      controller: controller,
      onChanged: onChanged,
      style: style,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: placeholder,
        hintStyle: style.copyWith(color: c.text3),
        suffixText: suffix,
        suffixStyle: t.body(14).copyWith(color: c.text2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    );
    return Semantics(
      label: label,
      child: GlassSurface(
        radius: Radii.md,
        child: SizedBox(height: 54, child: Center(child: field)),
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
