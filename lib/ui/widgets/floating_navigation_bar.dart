import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/animated_unread_badge.dart';

class FloatingNavigationBar extends StatelessWidget {
  const FloatingNavigationBar({
    super.key,
    required this.activeIndex,
    required this.onTap,
    required this.items,
    this.itemWidth = 52.0,
    this.horizontalPadding = 16.0,
    this.itemSpacing = 24.0,
    this.iconTextSpacing = 4.0,
    this.bottomOffset = 16.0,
  });

  final int activeIndex;
  final ValueChanged<int> onTap;
  final List<FloatingNavigationBarItem> items;

  final double itemWidth;
  final double itemSpacing;
  final double horizontalPadding;
  final double iconTextSpacing;
  final double bottomOffset;

  @override
  Widget build(BuildContext context) {
    debugPrint('''
════════ NAV LAYOUT ════════
padding.bottom: ${MediaQuery.paddingOf(context).bottom}
viewPadding.bottom: ${MediaQuery.viewPaddingOf(context).bottom}
viewInsets.bottom: ${MediaQuery.viewInsetsOf(context).bottom}
═══════════════════════════
''');

    final screenWidth = MediaQuery.of(context).size.width;

    final navBarWidth = math.min(screenWidth * 0.7, 380.0);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    final backgroundColor = context.scaffoldBackgroundColor.withValues(
      alpha: 0.9,
    );
    final borderColor = context.colorScheme.outline;
    final activeColor = context.colorScheme.onSurface;
    final inactiveColor = context.colorScheme.outline;

    return Padding(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        bottom: bottomPadding + bottomOffset,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: SizedBox(
          width: navBarWidth,
          height: 70,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 5),
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: borderColor, width: 0),
                ),
                child: Row(
                  children: List.generate(items.length, (index) {
                    final isSelected = activeIndex == index;
                    final item = items[index];

                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onTap(index);
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  isSelected ? item.activeIcon : item.icon,
                                  size: 28,
                                  color: isSelected
                                      ? activeColor
                                      : inactiveColor,
                                ),
                                Positioned(
                                  right: -12,
                                  top: -9,
                                  child: AnimatedUnreadBadge(
                                    count: item.unreadCount,
                                    color: context.colorScheme.primary,
                                    textColor: context.scaffoldBackgroundColor,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: iconTextSpacing),
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? activeColor : inactiveColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Модель элемента для FloatingNavigationBar
class FloatingNavigationBarItem {
  const FloatingNavigationBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.unreadCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int unreadCount;
}
