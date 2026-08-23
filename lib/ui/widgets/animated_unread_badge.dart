import 'package:flutter/material.dart';
import 'package:yap_chat/ui/widgets/animated_status_switcher.dart';

class AnimatedUnreadBadge extends StatelessWidget {
  const AnimatedUnreadBadge({
    super.key,
    required this.count,
    required this.color,
    required this.textColor,
    this.size = 25,
    this.borderColor,
    this.borderWidth = 0,
  });

  final int count;
  final Color color;
  final Color textColor;
  final double size;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final isVisible = count > 0;
    final label = count > 99 ? '99+' : '$count';

    return AnimatedStatusSwitcher(
      child: isVisible
          ? Container(
              key: const ValueKey('unread-badge'),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: borderColor == null
                    ? null
                    : Border.all(color: borderColor!, width: borderWidth),
              ),
              alignment: Alignment.center,
              child: AnimatedStatusSwitcher(
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: TextStyle(
                    color: textColor,
                    fontSize: size <= 22 ? 10 : 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : SizedBox(key: const ValueKey('unread-badge-hidden')),
    );
  }
}
