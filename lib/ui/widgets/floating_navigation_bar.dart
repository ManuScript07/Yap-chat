import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';



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
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    final backgroundColor = context.scaffoldBackgroundColor.withValues(alpha: 0.9);
    final borderColor = context.colorScheme.outline;
    final activeColor = context.colorScheme.onSurface;
    final inactiveColor = context.colorScheme.outline;


    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottomPadding + bottomOffset,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 5),
            child: Container(
              height: 70,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: borderColor,
                  width: 0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(items.length, (index) {
                  final isSelected = activeIndex == index;
                  final item = items[index];

                  final tabWidget = Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: SizedBox(
                      width: itemWidth,
                      height: double.infinity,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onTap(index);
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(
                              isSelected ? item.activeIcon : item.icon,
                              size: 28,
                              color: isSelected ? activeColor : inactiveColor,
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
                    ),
                  );

                  if (index < items.length - 1) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tabWidget,
                        SizedBox(width: itemSpacing),
                      ],
                    );
                  }

                  return tabWidget;
                }),
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
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}