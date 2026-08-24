import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/abstract_friends_repository.dart';

class MockFriendsRepository implements IFriendsRepository {
  MockFriendsRepository()
    : _friends = [
        Friend(
          id: 'friend-1',
          username: 'masha',
          displayName: 'Маша',
          friendsSince: DateTime.now().subtract(const Duration(days: 2)),
        ),
        Friend(
          id: 'friend-2',
          username: 'sasha',
          displayName: 'Саша',
          friendsSince: DateTime.now().subtract(const Duration(days: 7)),
        ),
      ],
      _requests = [
        FriendRequest(
          id: 'request-incoming',
          peerId: 'candidate-1',
          peerUsername: 'lena',
          peerDisplayName: 'Лена',
          peerFriendCount: 12,
          direction: FriendRequestDirection.incoming,
          requestedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
        FriendRequest(
          id: 'request-outgoing',
          peerId: 'candidate-2',
          peerUsername: 'dima',
          peerDisplayName: 'Дима',
          peerFriendCount: 4,
          direction: FriendRequestDirection.outgoing,
          requestedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ];

  final List<Friend> _friends;
  final List<FriendRequest> _requests;
  final Uuid _uuid = const Uuid();
  final StreamController<List<Friend>> _friendsController =
      StreamController.broadcast(sync: true);
  final StreamController<List<FriendRequest>> _requestsController =
      StreamController.broadcast(sync: true);

  List<Friend> get _friendsSnapshot => List.unmodifiable(_friends);

  List<FriendRequest> get _requestsSnapshot => List.unmodifiable(_requests);

  @override
  Stream<List<Friend>> watchFriends() async* {
    yield _friendsSnapshot;
    yield* _friendsController.stream;
  }

  @override
  Stream<List<FriendRequest>> watchRequests() async* {
    yield _requestsSnapshot;
    yield* _requestsController.stream;
  }

  @override
  Future<List<Friend>> getFriends() async => _friendsSnapshot;

  @override
  Future<List<FriendRequest>> getRequests() async => _requestsSnapshot;

  @override
  Future<List<FriendCandidate>> searchUsers(String query) async {
    final normalized = query.trim().toLowerCase();
    final usernameSearch = normalized.startsWith('@');
    final searchValue = usernameSearch ? normalized.substring(1) : normalized;
    if (searchValue.length < 3) return const [];
    final candidates = <FriendCandidate>[
      const FriendCandidate(
        id: 'candidate-3',
        username: 'max',
        displayName: 'Максим',
        friendCount: 21,
        relationship: FriendRelationship.none,
      ),

      const FriendCandidate(
        id: 'candidate-4',
        username: 'katya',
        displayName: 'Катя',
        friendCount: 8,
        relationship: FriendRelationship.none,
      ),
      ..._requests.map(
        (request) => FriendCandidate(
          id: request.peerId,
          requestId: request.id,
          username: request.peerUsername,
          displayName: request.peerDisplayName,
          avatarUrl: request.peerAvatarUrl,
          avatarStoragePath: request.peerAvatarStoragePath,
          friendCount: request.peerFriendCount,
          relationship: request.direction == FriendRequestDirection.incoming
              ? FriendRelationship.incoming
              : FriendRelationship.outgoing,
        ),
      ),
    ];
    return candidates
        .where(
          (item) => usernameSearch
              ? item.username.toLowerCase() == searchValue
              : item.displayName
                    .toLowerCase()
                    .split(RegExp(r'[^a-zа-яё0-9_]+'))
                    .any((word) => word.startsWith(searchValue)),
        )
        .take(10)
        .toList(growable: false);
  }

  @override
  Future<Map<String, FriendCandidate>> matchContactPhones(
    List<String> phoneNumbers,
  ) async => {
    if (phoneNumbers.contains('+79990000001'))
      '+79990000001': const FriendCandidate(
        id: 'candidate-3',
        username: 'max',
        displayName: 'Максим',
        friendCount: 21,
        relationship: FriendRelationship.none,
      ),
  };

  @override
  Future<String?> resolveFriendAvatar(Friend friend) async => friend.avatarUrl;

  @override
  Future<String?> resolveRequestAvatar(FriendRequest request) async =>
      request.peerAvatarUrl;

  @override
  Future<String?> resolveCandidateAvatar(FriendCandidate candidate) async =>
      candidate.avatarUrl;

  @override
  Future<void> sendRequest(FriendCandidate candidate) async {
    _requests.insert(
      0,
      FriendRequest(
        id: _uuid.v4(),
        peerId: candidate.id,
        peerUsername: candidate.username,
        peerDisplayName: candidate.displayName,
        peerAvatarUrl: candidate.avatarUrl,
        peerAvatarStoragePath: candidate.avatarStoragePath,
        peerFriendCount: candidate.friendCount,
        direction: FriendRequestDirection.outgoing,
        requestedAt: DateTime.now(),
      ),
    );
    _requestsController.add(_requestsSnapshot);
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    _requests.removeWhere((request) => request.id == requestId);
    _requestsController.add(_requestsSnapshot);
  }

  @override
  Future<void> respondToRequest(
    String requestId, {
    required bool accept,
  }) async {
    final request = _requests.where((item) => item.id == requestId).firstOrNull;
    _requests.removeWhere((item) => item.id == requestId);
    if (accept && request != null) {
      _friends.insert(
        0,
        Friend(
          id: request.peerId,
          username: request.peerUsername,
          displayName: request.peerDisplayName,
          avatarUrl: request.peerAvatarUrl,
          avatarStoragePath: request.peerAvatarStoragePath,
          friendsSince: DateTime.now(),
        ),
      );
      _friendsController.add(_friendsSnapshot);
    }
    _requestsController.add(_requestsSnapshot);
  }

  @override
  Future<FriendLocation?> getFriendLocation(String friendId) async =>
      FriendLocation(
        latitude: 55.751244,
        longitude: 37.618423,
        updatedAt: DateTime.now(),
      );

  @override
  Future<void> pauseRealtime() async {}

  @override
  Future<void> resumeRealtime() async {}
}
