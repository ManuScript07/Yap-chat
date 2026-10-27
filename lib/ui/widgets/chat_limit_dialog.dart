import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

import 'confirmation_dialog.dart';

final _activeChatLimitDialogs = Expando<Future<void>>();

/// One dialog per navigator, including concurrent refusals from an attachment
/// sheet. Dismissing it never drops the content retained by the submitter.
Future<void> showChatLimitReachedDialog(
  BuildContext context, {
  required int limit,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final existing = _activeChatLimitDialogs[navigator];
  if (existing != null) return existing;
  final l10n = context.l10n;
  late final Future<void> operation;
  operation =
      showConfirmationDialog(
        context,
        title: l10n.chatsLimitTitle,
        content: l10n.chatsLimitContent(limit),
        confirmLabel: l10n.chatsLimitDismiss,
        showCancelButton: false,
        scrollable: true,
      ).then<void>((_) {}).whenComplete(() {
        if (identical(_activeChatLimitDialogs[navigator], operation)) {
          _activeChatLimitDialogs[navigator] = null;
        }
      });
  _activeChatLimitDialogs[navigator] = operation;
  return operation;
}
