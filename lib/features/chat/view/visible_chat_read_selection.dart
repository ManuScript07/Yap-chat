import 'dart:math' as math;

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:yap_chat/features/chat/data/data.dart';

/// Select exact on-screen IDs; a created-at cursor would also mark unseen
/// older messages and is therefore unsafe for an open, paginated timeline.
Set<String> visibleUnreadMessageIds(
  Iterable<ItemPosition> positions,
  ChatMessage? Function(int index) messageAt,
  Set<String> acknowledged, {
  int limit = 60,
}) {
  final ids = <String>{};
  for (final position in positions) {
    final message = messageAt(position.index);
    if (message == null ||
        message.isMine ||
        message.isLocalOnly ||
        message.readAt != null ||
        acknowledged.contains(message.id)) {
      continue;
    }
    final visibleExtent =
        math.min(1.0, position.itemTrailingEdge) -
        math.max(0.0, position.itemLeadingEdge);
    final itemExtent = position.itemTrailingEdge - position.itemLeadingEdge;
    if (visibleExtent <= 0 || itemExtent <= 0) continue;
    // Oversized media can never be wholly visible, so use viewport coverage.
    if (visibleExtent / itemExtent >= 0.9 || visibleExtent >= 0.6) {
      ids.add(message.id);
    }
    if (ids.length == limit) break;
  }
  return ids;
}
