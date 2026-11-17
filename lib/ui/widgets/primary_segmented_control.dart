import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/animated_unread_badge.dart';
import 'package:yap_chat/ui/widgets/primary_app_bar.dart';

import 'swipe_tab_view.dart';

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
    this.horizontalPadding = PrimaryHeaderGeometry.horizontalPadding,
    this.compact = false,
    this.pages,
    this.applySafeArea = true,
  });

  final List<PrimarySegmentItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double horizontalPadding;
  final bool compact;
  final SwipeTabController? pages;
  final bool applySafeArea;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurface;
    final systemPadding = applySafeArea
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    return Padding(
      padding: EdgeInsets.only(
        left: horizontalPadding + systemPadding.left,
        right: horizontalPadding + systemPadding.right,
      ),
      child: Container(
        height: compact ? 44 : 50,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          // Keep labels readable as rows pass below the compact tab strip.
          color: compact
              ? context.scaffoldBackgroundColor.withValues(alpha: .65)
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (pages case final controller?)
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: controller,
                  child: FractionallySizedBox(
                    widthFactor: 1 / items.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  builder: (context, child) => Align(
                    alignment: AlignmentDirectional(
                      items.length < 2
                          ? 0
                          : 2 *
                                    controller.progress.clamp(
                                      0,
                                      items.length - 1,
                                    ) /
                                    (items.length - 1) -
                                1,
                      0,
                    ),
                    child: child,
                  ),
                ),
              ),
            Row(
              children: List.generate(items.length, (index) {
                final item = items[index];
                final selected = index == selectedIndex;
                final textColor = selected
                    ? color
                    : context.colorScheme.onSurfaceVariant;
                return Expanded(
                  child: Material(
                    color: selected && pages == null
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
                              (context.textTheme.titleMedium ??
                                      const TextStyle())
                                  .copyWith(
                                    color: textColor,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    fontSize: compact ? 16 : null,
                                  ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
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
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
