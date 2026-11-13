import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chats/data/models/chat.dart';
import 'package:yap_chat/features/friends/data/models/friend.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:yap_chat/repositories/friends/friends_cache_data_source.dart';

void main() {
  late AppDatabase database;
  late Directory directory;
  late MediaCacheService media;
  late ChatsCacheDataSource chats;
  late FriendsCacheDataSource friends;
  var owner = 'first';
  var directoryCalls = 0;

  setUp(() async {
    owner = 'first';
    directoryCalls = 0;
    database = AppDatabase.forTesting(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('yap-row-avatars-');
    media = MediaCacheService(
      database: database,
      cacheDirectoryProvider: () async {
        directoryCalls++;
        return directory;
      },
      supportDirectoryProvider: () async => directory,
    );
    chats = ChatsCacheDataSource(
      database: database,
      mediaCache: media,
      userIdProvider: () => owner,
    );
    friends = FriendsCacheDataSource(
      database: database,
      mediaCache: media,
      userIdProvider: () => owner,
    );
  });

  tearDown(() async {
    media.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'read and stream restore the same file without changing SQLite rows',
    () async {
      final photo = await media.storeBytes(
        ownerUserId: owner,
        bucket: 'avatars',
        storagePath: 'peer/photo.jpg',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      final chat = _chat(storage: 'peer/photo.jpg');
      final friend = _friend(storage: 'peer/photo.jpg');
      await chats.replaceAll([chat]);
      await friends.replaceAll(friends: [friend], requests: const []);
      expect((await chats.read()).single.cachedAvatarPath, photo);
      expect((await friends.readFriends()).single.cachedAvatarPath, photo);
      expect((await chats.watch().first).single.cachedAvatarPath, photo);
      expect(
        (await friends.watchFriends().first).single.cachedAvatarPath,
        photo,
      );
      expect((await chats.readByPeerId('peer'))?.cachedAvatarPath, photo);
      expect(await chats.replaceAll([chat]), isFalse);
      expect(
        await friends.replaceAll(friends: [friend], requests: const []),
        isFalse,
      );
      expect(directoryCalls, 1);
    },
  );

  test(
    'metadata updates change the path; removal cannot restore the old photo',
    () async {
      await chats.replaceAll([_chat(storage: 'peer/old.jpg')]);
      await friends.replaceAll(
        friends: [_friend(storage: 'peer/old.jpg')],
        requests: const [],
      );
      final previous = (await chats.read()).single.cachedAvatarPath;
      await chats.replaceAll([_chat(storage: 'peer/new.jpg')]);
      await friends.replaceAll(
        friends: [_friend(storage: 'peer/new.jpg')],
        requests: const [],
      );
      final updated = (await chats.read()).single;
      expect(updated.cachedAvatarPath, isNot(previous));
      expect(
        (await friends.readFriends()).single.cachedAvatarPath,
        updated.cachedAvatarPath,
      );
      expect(
        updated.copyWith(unreadCount: 3).cachedAvatarPath,
        updated.cachedAvatarPath,
      );
      expect(
        updated.copyWith(avatarStoragePath: 'peer/other.jpg').cachedAvatarPath,
        isNull,
      );
      await chats.replaceAll([_chat()]);
      await friends.replaceAll(friends: [_friend()], requests: const []);
      expect((await chats.read()).single.cachedAvatarPath, isNull);
      expect((await friends.readFriends()).single.cachedAvatarPath, isNull);
    },
  );

  test(
    'cached avatars stay owner-scoped and obey blocked/banned metadata',
    () async {
      await chats.replaceAll([_chat(storage: 'peer/photo.jpg')]);
      await friends.replaceAll(
        friends: [_friend(storage: 'peer/photo.jpg')],
        requests: const [],
      );
      final firstPath = (await chats.read()).single.cachedAvatarPath;
      owner = 'second';
      await chats.replaceAll([_chat(storage: 'peer/photo.jpg')]);
      await friends.replaceAll(
        friends: [_friend(storage: 'peer/photo.jpg')],
        requests: const [],
      );
      final secondPath = (await chats.read()).single.cachedAvatarPath;
      expect(secondPath, isNot(firstPath));
      expect((await friends.readFriends()).single.cachedAvatarPath, secondPath);
      expect(
        (await chats.read(ownerUserId: 'first')).single.cachedAvatarPath,
        firstPath,
      );
      await chats.replaceAll([
        _chat(storage: 'peer/photo.jpg').copyWith(blockedByPeer: true),
      ]);
      expect((await chats.read()).single.cachedAvatarPath, isNull);
      await chats.replaceAll([
        _chat(storage: 'peer/photo.jpg').copyWith(peerIsGloballyBanned: true),
      ]);
      expect((await chats.read()).single.cachedAvatarPath, isNull);
    },
  );

  test(
    'external avatars retain their original deterministic file name',
    () async {
      const url = 'https://example.invalid/avatar';
      final file = await media.storeBytes(
        ownerUserId: owner,
        bucket: MediaCacheService.externalAvatarsBucket,
        storagePath: url,
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1]),
      );
      await chats.replaceAll([_chat(url: url)]);
      await friends.replaceAll(
        friends: [_friend(url: url)],
        requests: const [],
      );
      expect((await chats.read()).single.cachedAvatarPath, file);
      expect((await friends.readFriends()).single.cachedAvatarPath, file);
      expect(
        (await friends.readFriends()).single
            .copyWith(avatarUrl: 'https://other.invalid')
            .cachedAvatarPath,
        isNull,
      );
    },
  );

  test(
    'one directory lookup serves large metadata-only lists without scanning files',
    () async {
      final marker = File(
        '${directory.path}/media_cache/prod/first/avatars/orphan.tmp',
      );
      await marker.parent.create(recursive: true);
      await marker.writeAsString('not to be scanned while restoring rows');
      final rows = List.generate(
        300,
        (i) => _chat(storage: 'peer/$i.jpg').copyWith(id: '$i', peerId: '$i'),
      );
      await chats.replaceAll(rows);
      expect((await chats.read()).length, 300);
      expect(
        (await chats.watch().first).every(
          (row) => row.cachedAvatarPath != null,
        ),
        isTrue,
      );
      expect(directoryCalls, 1);
      expect(await marker.exists(), isTrue);
    },
  );

  test(
    'directory errors leave metadata usable and permit a later retry',
    () async {
      await chats.replaceAll([_chat(storage: 'peer/photo.jpg')]);
      var fail = true;
      final unavailable = MediaCacheService(
        database: database,
        cacheDirectoryProvider: () async {
          if (fail) throw const FileSystemException('temporarily unavailable');
          return directory;
        },
      );
      addTearDown(unavailable.dispose);
      final cache = ChatsCacheDataSource(
        database: database,
        mediaCache: unavailable,
        userIdProvider: () => owner,
      );
      final cached = (await cache.watch().first).single;
      expect(cached.userName, 'Peer');
      expect(cached.cachedAvatarPath, isNull);
      fail = false;
      expect((await cache.read()).single.cachedAvatarPath, isNotNull);
    },
  );
}

Chat _chat({String? storage, String? url}) => Chat(
  id: 'chat',
  peerId: 'peer',
  userName: 'Peer',
  avatarUrl: url,
  avatarStoragePath: storage,
  lastMessage: '',
  lastMessageTime: DateTime.utc(2026, 10, 18),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);

Friend _friend({String? storage, String? url}) => Friend(
  id: 'peer',
  username: 'peer',
  displayName: 'Peer',
  avatarUrl: url,
  avatarStoragePath: storage,
  friendsSince: DateTime.utc(2026, 10, 18),
);
