import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/ui/widgets/chat_glass_surface.dart';

class ReplyComposerPreview extends StatelessWidget {
  const ReplyComposerPreview({
    super.key,
    required this.message,
    required this.peerName,
    required this.onClear,
    this.onTap,
  });

  final ChatMessage message;
  final String peerName;
  final VoidCallback onClear;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final author = message.isMine ? context.l10n.chatReplyYou : peerName;

    return ChatGlassSurface(
      borderRadius: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
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
