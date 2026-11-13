import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/friends/friends.dart';

void main() {
  test('keeps independent search queries for friends and requests', () {
    final state = FriendsState(
      activeTab: FriendsTab.requests,
      friendsQuery: 'masha',
      requestsQuery: 'lena',
      friends: [_friend('friend-1', 'masha', 'Маша')],
      requests: [_request('request-1', 'lena', 'Лена')],
    );

    expect(state.activeQuery, 'lena');
    expect(state.filteredFriends.single.id, 'friend-1');
    expect(state.filteredRequests.single.id, 'request-1');
  });

  test('filters names and usernames without case sensitivity', () {
    final state = FriendsState(
      friendsQuery: 'MAS',
      requestsQuery: 'ЛЕН',
      friends: [
        _friend('friend-1', 'masha', 'Мария'),
        _friend('friend-2', 'sasha', 'Александр'),
      ],
      requests: [
        _request('request-1', 'user', 'Лена'),
        _request('request-2', 'other', 'Катя'),
      ],
    );

    expect(state.filteredFriends.map((item) => item.id), ['friend-1']);
    expect(state.filteredRequests.map((item) => item.id), ['request-1']);
  });

  test('searches local usernames with an at-sign at any length', () {
    final state = FriendsState(
      friendsQuery: '@ma',
      requestsQuery: '@le',
      friends: [
        _friend('friend-1', 'masha', 'Мария'),
        _friend('friend-2', 'sasha', 'Александр'),
      ],
      requests: [
        _request('request-1', 'lena', 'Лена'),
        _request('request-2', 'other', 'Катя'),
      ],
    );

    expect(state.filteredFriends.map((item) => item.id), ['friend-1']);
    expect(state.filteredRequests.map((item) => item.id), ['request-1']);
  });
}

Friend _friend(String id, String username, String name) => Friend(
  id: id,
  username: username,
  displayName: name,
  friendsSince: DateTime.utc(2026, 8, 24),
);

FriendRequest _request(String id, String username, String name) =>
    FriendRequest(
      id: id,
      peerId: 'peer-$id',
      peerUsername: username,
      peerDisplayName: name,
      direction: FriendRequestDirection.incoming,
      requestedAt: DateTime.utc(2026, 8, 24),
    );
