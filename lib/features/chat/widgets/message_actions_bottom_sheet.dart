import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';

enum MessageAction { copy, reply, delete }

Future<MessageAction?> showMessageActionsBottomSheet(
  BuildContext context, {
  required ChatMessage message,
}) {
  return showModalBottomSheet<MessageAction>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _MessageActionsBottomSheet(message: message),
  );
}

class _MessageActionsBottomSheet extends StatelessWidget {
  const _MessageActionsBottomSheet({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isPending = message.status == MessageStatus.sending ||
        message.status == MessageStatus.error;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colorScheme.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Align(
          alignment: Alignment.topCenter,
          widthFactor: 1,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colorScheme.onSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),
                if (!isPending && message.type == MessageType.text)
                  _ActionTile(
                    icon: Icons.copy_rounded,
                    label: context.l10n.chatActionCopy,
                    onTap: () => Navigator.pop(context, MessageAction.copy),
                  ),
                if (!isPending)
                  _ActionTile(
                    icon: Icons.reply_rounded,
                    label: context.l10n.chatActionReply,
                    onTap: () => Navigator.pop(context, MessageAction.reply),
                  ),
                _ActionTile(
                  icon: Icons.delete_outline_rounded,
                  label: context.l10n.chatActionDelete,
                  onTap: () => Navigator.pop(context, MessageAction.delete),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: context.colorScheme.onSurface),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: context.colorScheme.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
