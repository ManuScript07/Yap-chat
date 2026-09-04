import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final contentHorizontalPadding = isLandscape ? 0.0 : horizontalPadding;
    final useCompactItemLayout = items.length > 3;
    const compactItemSpacing = 12.0;
    final itemGapCount = math.max(0, items.length - 1);
    final availableWidth = math.max(
      0.0,
      screenWidth - contentHorizontalPadding * 2,
    );
    final threeItemWidth = math.min(screenWidth * 0.75, 380.0);
    final compactNavWidth =
        items.length * itemWidth +
        itemGapCount * compactItemSpacing +
        horizontalPadding * 2;
    final navBarWidth = math.min(
      availableWidth,
      useCompactItemLayout ? compactNavWidth : threeItemWidth,
    );
    final compactLayoutScale = useCompactItemLayout
        ? navBarWidth / compactNavWidth
        : 1.0;
    final bottomPadding = isLandscape ? 0.0 : mediaQuery.padding.bottom;

    final backgroundColor = context.scaffoldBackgroundColor.withValues(
      alpha: 0.9,
    );
    final borderColor = context.colorScheme.outline;
    final activeColor = context.colorScheme.onSurface;
    final inactiveColor = context.colorScheme.outline;

    return Padding(
      padding: EdgeInsets.only(
        left: contentHorizontalPadding,
        right: contentHorizontalPadding,
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
                padding: useCompactItemLayout
                    ? EdgeInsets.symmetric(
                        horizontal: horizontalPadding * compactLayoutScale,
                      )
                    : null,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: borderColor, width: 0),
                ),
                child: Row(
                  mainAxisAlignment: useCompactItemLayout
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: List.generate(items.length, (index) {
                    final isSelected = activeIndex == index;
                    final item = items[index];

                    final navigationItem = GestureDetector(
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
                              if (item.iconAsset case final iconAsset?)
                                SvgPicture.asset(
                                  isSelected
                                      ? item.activeIconAsset!
                                      : iconAsset,
                                  width: 28,
                                  height: 28,
                                  colorFilter: ColorFilter.mode(
                                    isSelected ? activeColor : inactiveColor,
                                    BlendMode.srcIn,
                                  ),
                                )
                              else
                                Icon(
                                  isSelected ? item.activeIcon! : item.icon!,
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
                              fontWeight: FontWeight.w900,
                              color: isSelected ? activeColor : inactiveColor,
                            ),
                          ),
                        ],
                      ),
                    );

                    if (!useCompactItemLayout) {
                      return Expanded(child: navigationItem);
                    }

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: itemWidth * compactLayoutScale,
                          child: navigationItem,
                        ),
                        if (index < items.length - 1)
                          SizedBox(
                            width: compactItemSpacing * compactLayoutScale,
                          ),
                      ],
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
  }) : iconAsset = null,
       activeIconAsset = null;

  const FloatingNavigationBarItem.asset({
    required this.iconAsset,
    required this.activeIconAsset,
    required this.label,
    this.unreadCount = 0,
  }) : icon = null,
       activeIcon = null;

  final IconData? icon;
  final IconData? activeIcon;
  final String? iconAsset;
  final String? activeIconAsset;
  final String label;
  final int unreadCount;
}
