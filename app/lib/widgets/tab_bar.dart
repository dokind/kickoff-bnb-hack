import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'controls.dart';
import 'glass.dart';

/// One button in the [FloatingTabBar]: a place, or an action.
class TabItem {
  const TabItem({required this.icon, required this.label, this.action = false});
  final IconData icon;

  /// Not drawn: the tooltip and the screen-reader name.
  final String label;

  /// An action (the "+") and not a place: it is never the selected one, and
  /// every press is passed on.
  final bool action;
}

/// The floating glass capsule at the bottom: one round button per place,
/// and the "+" between them. The place you are on is a volt disc with a
/// glow; the other places are faint. An action is neither: a ringed disc,
/// brighter than a place you are not on, never volt. Each button can be
/// reached and pressed from the keyboard and by a screen reader.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.current,
    required this.onSelect,
  });

  final List<TabItem> items;

  /// The index of the place you are on.
  final int current;
  final ValueChanged<int> onSelect;

  /// The bar's height, for screens that leave room under their content.
  static const double height = 72;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GlassSurface.pill(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              () {
                final here = !item.action && i == current;
                return Tooltip(
                  message: item.label,
                  // The button says its own name.
                  excludeFromSemantics: true,
                  child: Pressable(
                    label: item.label,
                    // A place says whether you are on it; an action has no
                    // such state.
                    selected: item.action ? null : here,
                    shape: const CircleBorder(),
                    ink: here ? c.onVolt : c.text,
                    onPressed: () {
                      if (here) return;
                      HapticFeedback.selectionClick();
                      onSelect(i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: here
                            ? c.volt
                            : Colors.white.withValues(
                                alpha: item.action ? 0.12 : 0.06,
                              ),
                        border: item.action
                            ? Border.all(color: c.text3, width: 1.5)
                            : null,
                        boxShadow: [
                          if (here)
                            BoxShadow(
                              color: c.volt.withValues(alpha: 0.5),
                              blurRadius: 12,
                            ),
                        ],
                      ),
                      child: Icon(
                        item.icon,
                        size: item.action ? 26 : 22,
                        color: here ? c.onVolt : c.text,
                      ),
                    ),
                  ),
                );
              }(),
            ],
          ],
        ),
      ),
    );
  }
}
