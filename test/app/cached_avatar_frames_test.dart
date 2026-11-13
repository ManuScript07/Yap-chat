import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/app/cached_avatar_frames.dart';
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

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('yap-avatar-frames-');
    media = MediaCacheService(
      database: database,
      cacheDirectoryProvider: () async => directory,
      supportDirectoryProvider: () async => directory,
    );
    chats = ChatsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    friends = FriendsCacheDataSource(
      database: database,
      userIdProvider: () => 'owner',
    );
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDown(() async {
    media.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<String> photo(String name, {String owner = 'owner'}) async =>
      media.storeBytes(
        ownerUserId: owner,
        bucket: 'avatars',
        storagePath: name,
        bytes: await File('assets/logo/logo_yap_chat.png').readAsBytes(),
      );

  Future<void> prepare({
    bool Function()? isCurrent,
    MediaCacheService? cache,
    Duration budget = const Duration(milliseconds: 750),
  }) =>
      CachedAvatarFrames(
        database: database,
        mediaCache: cache ?? media,
        timeBudget: budget,
      ).prepare(
        ownerUserId: 'owner',
        devicePixelRatio: 3,
        viewportHeight: 800,
        isCurrent: isCurrent ?? () => true,
      );

  Future<bool> ready(String path, int logicalSize) async {
    final key = await ResizeImage(
      FileImage(File(path)),
      width: logicalSize * 3,
    ).obtainKey(const ImageConfiguration(devicePixelRatio: 3));
    return PaintingBinding.instance.imageCache.statusForKey(key).keepAlive;
  }

  testWidgets('only prepares the initial bounded heads of both lists', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final top = await photo('peer/top.png');
      final tail = await photo('peer/tail.png');
      await chats.replaceAll(
        List.generate(
          100,
          (i) =>
              _chat('$i', i < 12 ? 'peer/top.png' : 'peer/tail.png', order: i),
        ),
      );
      await friends.replaceAll(
        friends: List.generate(
          100,
          (i) => _friend(
            '$i',
            i < 12 ? 'peer/top.png' : 'peer/tail.png',
            order: i,
          ),
        ),
        requests: const [],
      );
      final marker = File('${File(top).parent.path}/unrelated.tmp');
      await marker.writeAsString('do not scan the media cache');

      await prepare();

      expect(await ready(top, 56), isTrue);
      expect(await ready(top, 54), isTrue);
      expect(await ready(tail, 56), isFalse);
      expect(await ready(tail, 54), isFalse);
      expect(await marker.exists(), isTrue);
      expect((await chats.read()).length, 100);
      expect((await friends.readFriends()).length, 100);
      expect(PaintingBinding.instance.imageCache.currentSize, 2);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'does not prepare blocked, banned, removed or another owner avatars',
    (tester) async {
      await tester.runAsync(() async {
        final blocked = await photo('peer/blocked.png');
        final banned = await photo('peer/banned.png');
        final removed = await photo('peer/removed.png');
        final other = await photo('peer/other.png', owner: 'other');
        await chats.replaceAll([
          _chat('blocked', 'peer/blocked.png').copyWith(blockedByPeer: true),
          _chat(
            'banned',
            'peer/banned.png',
          ).copyWith(peerIsGloballyBanned: true),
          _chat('removed', null),
        ]);
        await chats.replaceAll([
          _chat('other', 'peer/other.png'),
        ], ownerUserId: 'other');
        await friends.replaceAll(
          friends: [_friend('removed', null)],
          requests: const [],
        );

        await prepare();

        for (final path in [blocked, banned, removed, other]) {
          expect(await ready(path, 56), isFalse);
          expect(await ready(path, 54), isFalse);
        }
        expect(PaintingBinding.instance.imageCache.currentSize, 0);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing/corrupt files never trigger network or prevent startup',
    (tester) async {
      await tester.runAsync(() async {
        await chats.replaceAll([
          _chat('missing', 'peer/missing.png'),
          _chat('corrupt', 'peer/corrupt.png'),
          _chat(
            'url',
            null,
          ).copyWith(avatarUrl: 'https://example.invalid/avatar'),
        ]);
        await media.prepareLocalPaths();
        final corrupt = File(
          media.localStorageFilePath(
            ownerUserId: 'owner',
            bucket: 'avatars',
            storagePath: 'peer/corrupt.png',
          )!,
        );
        await corrupt.parent.create(recursive: true);
        await corrupt.writeAsString('not an image');
        var networkAttempts = 0;
        await HttpOverrides.runZoned(
          prepare,
          createHttpClient: (_) {
            networkAttempts++;
            throw StateError('Offline preparation may not use the network');
          },
        );
        expect(networkAttempts, 0);
        expect(PaintingBinding.instance.imageCache.currentSize, 0);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('directory failure leaves startup and cached metadata usable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await chats.replaceAll([_chat('cached', 'peer/photo.png')]);
      final unavailable = MediaCacheService(
        database: database,
        cacheDirectoryProvider: () async =>
            throw const FileSystemException('no cache directory'),
      );
      try {
        await prepare(cache: unavailable);
        expect((await chats.read()).single.id, 'cached');
      } finally {
        unavailable.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deadline prevents a stuck directory from holding startup; no late decode',
    (tester) async {
      await tester.runAsync(() async {
        final path = await photo('peer/photo.png');
        await chats.replaceAll([_chat('cached', 'peer/photo.png')]);
        final directoryReady = Completer<Directory>();
        final slow = MediaCacheService(
          database: database,
          cacheDirectoryProvider: () => directoryReady.future,
        );
        try {
          await prepare(cache: slow, budget: const Duration(milliseconds: 20));
          expect(directoryReady.isCompleted, isFalse);
          directoryReady.complete(directory);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(await ready(path, 56), isFalse);
          expect(PaintingBinding.instance.imageCache.pendingImageCount, 0);
        } finally {
          slow.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account changes stop obsolete startup preparation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final path = await photo('peer/photo.png');
      await chats.replaceAll([_chat('cached', 'peer/photo.png')]);
      var current = true;
      final directoryReady = Completer<Directory>();
      final slow = MediaCacheService(
        database: database,
        cacheDirectoryProvider: () => directoryReady.future,
      );
      try {
        final operation = prepare(cache: slow, isCurrent: () => current);
        current = false;
        directoryReady.complete(directory);
        await operation;
        expect(await ready(path, 56), isFalse);
      } finally {
        slow.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });
}

Chat _chat(String id, String? storage, {int order = 0}) => Chat(
  id: id,
  peerId: id,
  userName: 'Peer',
  avatarStoragePath: storage,
  lastMessage: '',
  lastMessageTime: DateTime.utc(
    2026,
    10,
    18,
  ).subtract(Duration(seconds: order)),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);

Friend _friend(String id, String? storage, {int order = 0}) => Friend(
  id: id,
  username: id,
  displayName: 'Peer',
  avatarStoragePath: storage,
  friendsSince: DateTime.utc(2026, 10, 18).subtract(Duration(seconds: order)),
);
