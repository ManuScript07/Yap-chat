import 'package:yap_chat/features/friends/data/models/friend.dart';

/// A bounded server response for the current user's own friend list.
///
/// The cursor is deliberately based on the friendship timestamp and peer id,
/// so it can be persisted alongside the local friend cache without exposing a
/// friendship row identifier to the UI.
class FriendPage {
  const FriendPage({
    required this.friends,
    required this.hasMore,
    required this.totalCount,
  });

  final List<Friend> friends;
  final bool hasMore;
  final int totalCount;

  FriendPageCursor? get nextCursor {
    if (!hasMore || friends.isEmpty) return null;
    final last = friends.last;
    return FriendPageCursor(friendsSince: last.friendsSince, friendId: last.id);
  }
}

class FriendPageCursor {
  const FriendPageCursor({required this.friendsSince, required this.friendId});

  final DateTime friendsSince;
  final String friendId;
}
