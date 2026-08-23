import 'package:flutter/material.dart';
import 'package:yap_chat/features/chat/data/data.dart';

class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({
    super.key,
    required this.status,
    required this.color,
    this.size = 18,
  });

  final MessageStatus status;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      MessageStatus.sending => Icons.access_time_rounded,
      MessageStatus.sent => Icons.done_rounded,
      MessageStatus.read => Icons.done_all_rounded,
      MessageStatus.error => Icons.error_outline_rounded,
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scaleAnimation = Tween<double>(
          begin: 0.78,
          end: 1,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scaleAnimation, child: child),
        );
      },
      child: Icon(key: ValueKey(status), icon, size: size, color: color),
    );
  }
}
