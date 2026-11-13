import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/profile/bloc/user_friends_state.dart';
import 'package:yap_chat/features/profile/data/data.dart';

void main() {
  const anna = ViewedProfileFriend(
    id: 'anna-id',
    username: 'anna',
    displayName: 'Анна',
  );
  const boris = ViewedProfileFriend(
    id: 'boris-id',
    username: 'boris',
    displayName: 'Борис',
  );

  group('UserFriendsState', () {
    test('filters the locally cached list by name and username', () {
      const state = UserFriendsState(friends: [anna, boris]);

      expect(state.copyWith(query: 'нн').visibleFriends, [anna]);
      expect(state.copyWith(query: '@bor').visibleFriends, [boris]);
    });

    test('derives friend-request actions from the cached friends data', () {
      final state = UserFriendsState(
        ownFriends: [
          Friend(
            id: 'anna-id',
            username: 'anna',
            displayName: 'Анна',
            friendsSince: DateTime.utc(2026),
          ),
        ],
        requests: [
          FriendRequest(
            id: 'request-id',
            peerId: 'boris-id',
            peerUsername: 'boris',
            peerDisplayName: 'Борис',
            direction: FriendRequestDirection.incoming,
            requestedAt: DateTime.utc(2026),
          ),
        ],
      );

      expect(
        state.relationFor(anna.id).relationship,
        FriendRelationship.friend,
      );
      expect(state.relationFor(boris.id), (
        relationship: FriendRelationship.incoming,
        requestId: 'request-id',
      ));
    });
  });
}
