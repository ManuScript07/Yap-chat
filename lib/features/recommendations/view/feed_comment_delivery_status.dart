import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

class FeedCommentDeliveryStatus extends StatelessWidget {
  const FeedCommentDeliveryStatus({
    super.key,
    required this.entry,
    required this.actions,
    this.showText = false,
  });

  final FeedCommentOutboxEntry entry;
  final FeedActionsCubit actions;
  final bool showText;

  Future<void> _discard(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmationDialog(
      context,
      title: l10n.feedCommentDiscardLocal,
      content: l10n.feedCommentDiscardConfirmation,
      confirmLabel: l10n.feedCommentDiscardLocal,
      cancelLabel: l10n.cancel.toLowerCase(),
    );
    if (confirmed != true || !context.mounted || !actions.active) return;
    try {
      await actions.outbox?.discardFailed(actions.account, entry.id);
    } catch (_) {
      if (context.mounted && actions.active) {
        showAppSnackBar(
          context,
          message: l10n.feedActionFailed,
          type: SnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = entry.failure;
    final status = switch (failure) {
      null => l10n.feedCommentQueued,
      FeedCommentFailure.postUnavailable => l10n.feedCommentPostUnavailable,
      FeedCommentFailure.replyUnavailable => l10n.feedCommentReplyUnavailable,
      _ => l10n.feedCommentSendFailed,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showText) Text(entry.text, style: context.textTheme.bodyMedium),
        Semantics(
          liveRegion: failure != null,
          child: Text(
            status,
            style: context.textTheme.bodySmall?.copyWith(
              color: failure == null
                  ? context.colorScheme.outline
                  : context.colorScheme.error,
            ),
          ),
        ),
        if (failure != null)
          Row(
            children: [
              IconButton(
                tooltip: l10n.feedCommentCopyText,
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () async {
                  if (actions.active) {
                    await Clipboard.setData(ClipboardData(text: entry.text));
                  }
                },
              ),
              IconButton(
                tooltip: l10n.feedCommentDiscardLocal,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _discard(context),
              ),
            ],
          ),
      ],
    );
  }
}
