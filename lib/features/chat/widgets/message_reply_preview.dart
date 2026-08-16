import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

class MessageReplyPreview extends StatelessWidget {
  const MessageReplyPreview({
    super.key,
    required this.reply,
    required this.peerName,
    required this.isMessageMine,
    this.onTap,
  });

  final MessageReply reply;
  final String peerName;
  final bool isMessageMine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final author = reply.isMine ? context.l10n.chatReplyYou : peerName;
    final backgroundColor = isMessageMine
        ? AppColors.incomingBubble
        : context.colorScheme.primary;
    final textColor = isMessageMine
        ? AppColors.incomingText
        : context.scaffoldBackgroundColor;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _previewText(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewText(BuildContext context) {
    return switch (reply.type) {
      MessageType.image => context.l10n.chatReplyPhoto,
      MessageType.audio => context.l10n.chatReplyAudio,
      MessageType.location => context.l10n.chatReplyLocation,
      MessageType.text => reply.text,
    };
  }
}
