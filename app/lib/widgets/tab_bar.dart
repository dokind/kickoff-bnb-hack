import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'glass.dart';

/// One place in the [FloatingTabBar].
class TabItem {
  const TabItem({required this.icon, required this.label});
  final IconData icon;

  /// Not drawn: the tooltip and the screen-reader name.
  final String label;
}

/// The floating glass capsule at the bottom: one round button per place.
/// The place you are on is a volt disc with a glow; the others are faint.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.current,
    required this.onSelect,
  });

  final List<TabItem> items;
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
              Tooltip(
                message: item.label,
                child: Semantics(
                  button: true,
                  selected: i == current,
                  label: item.label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i == current) return;
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
                        color: i == current
                            ? c.volt
                            : Colors.white.withValues(alpha: 0.06),
                        boxShadow: [
                          if (i == current)
                            BoxShadow(
                              color: c.volt.withValues(alpha: 0.5),
                              blurRadius: 12,
                            ),
                        ],
                      ),
                      child: Icon(
                        item.icon,
                        size: 22,
                        color: i == current ? c.onVolt : c.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
