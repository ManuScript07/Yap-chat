import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

void main() {
  test(
    'a cancelled request cannot leave an optimistic friend after acceptance fails',
    () async {
      final (repository, cache) = await _setup(_CancelledRequestRemote());
      await cache.replaceAll(friends: const [], requests: [_incomingRequest]);

      await expectLater(
        repository.respondToRequest(_incomingRequest.id, accept: true),
        throwsStateError,
      );

      expect(await cache.readFriends(), isEmpty);
      expect(await cache.readRequests(), isEmpty);
    },
  );

  test(
    'access events distinguish removal, identity changes and reconnect',
    () async {
      final remote = _ChangesRemote();
      addTearDown(remote.changes.close);
      final (repository, _) = await _setup(remote);
      addTearDown(repository.pauseRealtime);
      final events = <FriendAccessChange>[];
      final access = repository.watchFriendAccessChanges().listen(events.add);
      addTearDown(access.cancel);
      final profiles = <String>[];
      final identities = repository.watchProfileChanges().listen(profiles.add);
      addTearDown(identities.cancel);
      remote.changes.add(const FriendChange()); // Initial connection.
      remote.changes.add(
        const FriendChange(profileId: 'identity', reason: 'profile_updated'),
      );
      remote.changes.add(
        const FriendChange(
          profileId: 'peer',
          table: 'friend_requests',
          operation: 'DELETE',
        ),
      );
      remote.changes.add(
        const FriendChange(
          profileId: 'remote peer',
          table: 'friendships',
          operation: 'DELETE',
        ),
      );
      remote.changes.add(
        const FriendChange(
          profileId: 'blocked peer',
          reason: 'block',
          action: 'blocked',
        ),
      );
      remote.changes.add(const FriendChange()); // Reconnection.
      await repository.removeFriend('local peer');

      expect(profiles, ['identity', 'peer', 'remote peer', 'blocked peer']);
      expect(events, [
        (kind: FriendAccessChangeKind.removed, peerId: 'remote peer'),
        (kind: FriendAccessChangeKind.blocked, peerId: 'blocked peer'),
        (kind: FriendAccessChangeKind.reconnected, peerId: null),
        (kind: FriendAccessChangeKind.removed, peerId: 'local peer'),
      ]);
    },
  );
}

Future<(FriendsRepository, FriendsCacheDataSource)> _setup(
  FriendsRemoteDataSource remote,
) async {
  SharedPreferences.setMockInitialValues({});
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  final accounts = AccountSessionController(initialUserId: 'owner');
  final cache = FriendsCacheDataSource(
    database: database,
    userIdProvider: () => 'owner',
  );
  final repository = FriendsRepository(
    config: AppConfig(
      environment: AppEnvironment.prod,
      preferences: await SharedPreferences.getInstance(),
      talker: Talker(),
      env: const {},
      database: database,
      accountSessionController: accounts,
    ),
    cache: cache,
    contactMatchCache: ContactMatchCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
      keyService: const _TestKeyService(),
    ),
    remote: remote,
    mediaCache: MediaCacheService(database: database),
    accountSessionController: accounts,
  );
  return (repository, cache);
}

final _incomingRequest = FriendRequest(
  id: 'request',
  peerId: 'peer',
  peerUsername: 'peer',
  peerDisplayName: 'Peer',
  direction: FriendRequestDirection.incoming,
  requestedAt: DateTime.utc(2026, 9, 8),
);

class _CancelledRequestRemote extends FriendsRemoteDataSource {
  _CancelledRequestRemote()
    : super(
        client: SupabaseClient('http://localhost', 'test-key'),
        talker: Talker(),
      );

  @override
  Future<void> respond(String requestId, {required bool accept}) =>
      Future<void>.error(StateError('friend_request_not_found'));

  @override
  Future<FriendPage> fetchFriendsPage({
    FriendPageCursor? after,
    int pageSize = 50,
  }) async => const FriendPage(friends: [], hasMore: false, totalCount: 0);

  @override
  Future<List<FriendRequest>> fetchRequests() async => const [];
}

class _ChangesRemote extends _CancelledRequestRemote {
  final changes = StreamController<FriendChange>.broadcast();

  @override
  Stream<FriendChange> watchChanges() => changes.stream;

  @override
  Future<void> removeFriend(String friendId) async {}
}

class _TestKeyService implements IContactCacheKeyService {
  const _TestKeyService();

  @override
  Future<String> createKey(String normalizedPhone) async => normalizedPhone;
}
