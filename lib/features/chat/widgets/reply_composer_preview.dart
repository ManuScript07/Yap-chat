import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';

class ReplyComposerPreview extends StatelessWidget {
  const ReplyComposerPreview({
    super.key,
    required this.message,
    required this.peerName,
    required this.onClear,
  });

  final ChatMessage message;
  final String peerName;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final author = message.isMine ? context.l10n.chatReplyYou : peerName;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.colorScheme.onSurface.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18.5),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            color: context.colorScheme.onSurface.withValues(alpha: 0.15),
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.chatReplyingTo(author),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colorScheme.onSurface,
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
                          color: context.colorScheme.onSurface.withValues(
                            alpha: 0.8,
                          ),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClear,
                  icon: Icon(
                    Icons.close_rounded,
                    color: context.colorScheme.onSurface,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _previewText(BuildContext context) {
    return switch (message.type) {
      MessageType.image => context.l10n.chatReplyPhoto,
      MessageType.audio => context.l10n.chatReplyAudio,
      MessageType.location => context.l10n.chatReplyLocation,
      MessageType.text => message.text,
    };
  }
}
