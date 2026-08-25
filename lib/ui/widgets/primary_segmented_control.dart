import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/animated_unread_badge.dart';

class PrimarySegmentItem {
  const PrimarySegmentItem({required this.label, this.count});

  final String label;
  final int? count;
}

class PrimarySegmentedControl extends StatelessWidget {
  const PrimarySegmentedControl({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.horizontalPadding = 16,
  });

  final List<PrimarySegmentItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurface;
    final systemPadding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: horizontalPadding + systemPadding.left,
        right: horizontalPadding + systemPadding.right,
      ),
      child: Container(
        height: 50,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final selected = index == selectedIndex;
            final textColor = selected
                ? color
                : context.colorScheme.onSurfaceVariant;
            return Expanded(
              child: Material(
                color: selected
                    ? color.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => onChanged(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style:
                          (context.textTheme.titleMedium ?? const TextStyle())
                              .copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.count != null) ...[
                            const SizedBox(width: 6),
                            AnimatedUnreadBadge(
                              count: item.count!,
                              color: textColor,
                              textColor: context.scaffoldBackgroundColor,
                              size: 22,
                              maintainSize: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
