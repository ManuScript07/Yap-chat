import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/router/router.gr.dart';

/// Shares the same stack policy for list, profile and notification chat opens.
/// Keep the pages below the original chat, not the profiles opened above it.
Future<void> openChatRoute(StackRouter router, Chat chat) async {
  final stack = router.stackData;
  final chatIndex = stack.indexWhere((route) => route.name == ChatRoute.name);
  if (chatIndex >= 0) {
    final existing = stack[chatIndex].argsAs<ChatRouteArgs>().chat;
    final isSameConversation =
        existing.id == chat.id ||
        (chat.peerId.isNotEmpty && existing.peerId == chat.peerId);
    // Peer identity also covers a draft whose server ID has since resolved.
    final removeFrom = isSameConversation ? chatIndex + 1 : chatIndex;
    for (final route in stack.skip(removeFrom).toList().reversed) {
      router.removeRoute(route, notify: false);
    }
    if (isSameConversation) {
      router.notifyAll(forceUrlRebuild: true);
      await WidgetsBinding.instance.endOfFrame;
      return;
    }
  }

  // One router notification, without rendering the old chat between removals.
  // The push future completes when the route is popped, not when it opens.
  unawaited(
    router.push<Object?>(
      ChatRoute(key: ValueKey('chat:${chat.id}'), chat: chat),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
}
