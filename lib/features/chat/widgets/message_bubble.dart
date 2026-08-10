import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isNew,
  });

  final ChatMessage message;
  final bool isNew;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    if (widget.isNew && !_hasAnimated) {
      _hasAnimated = true;
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasAnimated || !widget.isNew) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;

    final bubbleColor = message.isMine
        ? context.colorScheme.primary
        : AppColors.incomingBubble;

    final textColor = message.isMine
        ? context.scaffoldBackgroundColor
        : context.colorScheme.onSecondaryContainer;

    final timeColor = message.isMine
        ? context.scaffoldBackgroundColor
        : AppColors.incomingTime;

    final iconColor = message.isMine
        ? context.scaffoldBackgroundColor
        : AppColors.incomingTime;

    final timeStatusWidth = message.isMine ? 66.0 : 44.0;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Align(
          alignment:
          message.isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Stack(
              children: [
                Text.rich(
                  TextSpan(
                    text: message.text,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      letterSpacing: 0.5,
                    ),
                    children: [
                      WidgetSpan(
                        child: SizedBox(
                          width: timeStatusWidth,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(message.timestamp),
                        style: TextStyle(
                          color: timeColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (message.isMine) ...[
                        const SizedBox(width: 4),
                        _buildStatusIcon(iconColor),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Color color) {
    switch (widget.message.status) {
      case MessageStatus.sending:
        return Icon(
          Icons.access_time_rounded,
          size: 18,
          color: color,
        );
      case MessageStatus.sent:
        return Icon(
          Icons.done_rounded,
          size: 18,
          color: color,
        );
      case MessageStatus.read:
        return Icon(
          Icons.done_all_rounded,
          size: 18,
          color: color,
        );
      case MessageStatus.error:
        return Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: color,
        );
    }
  }
}