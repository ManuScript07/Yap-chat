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
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final accountSessionController = AccountSessionController(
        initialUserId: 'owner',
      );
      final cache = FriendsCacheDataSource(
        database: database,
        userIdProvider: () => 'owner',
      );
      await cache.replaceAll(friends: const [], requests: [_incomingRequest]);
      final repository = FriendsRepository(
        config: AppConfig(
          environment: AppEnvironment.prod,
          preferences: await SharedPreferences.getInstance(),
          talker: Talker(),
          env: const {},
          database: database,
          accountSessionController: accountSessionController,
        ),
        cache: cache,
        contactMatchCache: ContactMatchCacheDataSource(
          database: database,
          userIdProvider: () => 'owner',
          keyService: const _TestKeyService(),
        ),
        remote: _CancelledRequestRemote(),
        mediaCache: MediaCacheService(database: database),
        accountSessionController: accountSessionController,
      );

      await expectLater(
        repository.respondToRequest(_incomingRequest.id, accept: true),
        throwsStateError,
      );

      expect(await cache.readFriends(), isEmpty);
      expect(await cache.readRequests(), isEmpty);
    },
  );
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

class _TestKeyService implements IContactCacheKeyService {
  const _TestKeyService();

  @override
  Future<String> createKey(String normalizedPhone) async => normalizedPhone;
}
