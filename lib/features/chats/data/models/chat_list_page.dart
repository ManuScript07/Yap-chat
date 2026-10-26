import 'chat.dart';

/// The server's exact per-member order; do not round it to cache seconds.
class ChatListPageCursor {
  const ChatListPageCursor({
    required this.activityAt,
    required this.conversationId,
    this.query = '',
  });

  final DateTime activityAt;
  final String conversationId;
  final String query;
}

class ChatListPageItem {
  const ChatListPageItem({required this.chat, required this.activityAt});

  final Chat chat;
  final DateTime activityAt;
}

/// A partial response: its absence of other IDs never means deleting the cache.
/// An empty items page can have a cursor if rows were hidden during the request.
class ChatListPage {
  ChatListPage({
    required List<ChatListPageItem> items,
    required this.query,
    required this.nextCursor,
    this.unreadTotal,
  }) : items = List.unmodifiable(items);

  final List<ChatListPageItem> items;
  final String query;
  final ChatListPageCursor? nextCursor;

  /// Null only while talking to a server without the unread projection migration.
  /// This is the whole-account total, also for a filtered search page.
  final int? unreadTotal;
  bool get hasMore => nextCursor != null;
}
