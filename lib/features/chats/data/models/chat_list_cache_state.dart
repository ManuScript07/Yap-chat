import 'chat.dart';
import 'chat_list_page.dart';

/// Persisted server coverage. A missing cursor means end only after a page was
/// confirmed; an old cache without coverage is never treated as a full snapshot.
class ChatListCacheState {
  const ChatListCacheState({
    required this.query,
    this.revision,
    this.hasRemotePage = false,
    this.nextCursor,
    this.checkedAt,
  });

  final String query;
  final String? revision;
  final bool hasRemotePage;
  final ChatListPageCursor? nextCursor;
  final DateTime? checkedAt;
  bool get hasMore => !hasRemotePage || nextCursor != null;
}

class ChatUnreadCacheState {
  const ChatUnreadCacheState({this.total, this.revision = 0, this.checkedAt});
  final int? total;
  final int revision;
  final DateTime? checkedAt;
}

/// An explicit cache cursor cannot accidentally be passed to the remote API.
/// Legacy rows have only second-resolution activity; server boundaries do not.
class ChatListLocalCursor {
  const ChatListLocalCursor({
    required this.query,
    required this.activityMicros,
    required this.chatId,
    required this.serverBacked,
  });
  final String query;
  final int activityMicros;
  final String chatId;
  final bool serverBacked;
}

class ChatListCacheSlice {
  ChatListCacheSlice({
    required List<Chat> chats,
    required this.serverBacked,
    this.nextCursor,
  }) : chats = List.unmodifiable(chats);
  final List<Chat> chats;
  final bool serverBacked;
  final ChatListLocalCursor? nextCursor;
  bool get hasMoreCached => nextCursor != null;
}

/// Capture before starting HTTP. Cache commit is compare-and-swap by query;
/// badge revision is independent because different queries share one total.
class ChatListCacheRequest {
  const ChatListCacheRequest({
    required this.ownerUserId,
    required this.query,
    required this.revision,
    required this.unreadRevision,
    this.after,
  });
  final String ownerUserId;
  final String query;
  final String revision;
  final int unreadRevision;
  final ChatListPageCursor? after;
}
