import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';

void main() {
  late Directory temporary;
  late Directory cache;
  late Directory support;
  late AppDatabase database;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('yap-media-cache-test');
    cache = Directory('${temporary.path}/cache');
    support = Directory('${temporary.path}/support');
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  MediaCacheService service({int maxBytes = 8, int maxFileBytes = 16}) {
    return MediaCacheService(
      database: database,
      environment: 'test',
      maxCacheBytes: maxBytes,
      maxSingleFileBytes: maxFileBytes,
      trimDelay: Duration.zero,
      cacheDirectoryProvider: () async => cache,
      supportDirectoryProvider: () async => support,
    );
  }

  test('stores reconstructible media in the Android cache directory', () async {
    final mediaCache = service();
    addTearDown(mediaCache.dispose);
    final stored = await mediaCache.storeBytes(
      ownerUserId: 'user',
      bucket: 'chat-images',
      storagePath: 'chat/image.jpg',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(stored, startsWith(cache.path));
    expect(await File(stored).exists(), isTrue);
  });

  test(
    'trims least recently used files and honors memory fast-path touches',
    () async {
      final mediaCache = service();
      addTearDown(mediaCache.dispose);
      final first = await mediaCache.storeBytes(
        ownerUserId: 'user',
        bucket: 'chat-images',
        storagePath: 'first.jpg',
        bytes: Uint8List(4),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = await mediaCache.storeBytes(
        ownerUserId: 'user',
        bucket: 'chat-images',
        storagePath: 'second.jpg',
        bytes: Uint8List(4),
      );
      await mediaCache.cacheStorageFile(
        ownerUserId: 'user',
        bucket: 'chat-images',
        storagePath: 'first.jpg',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await mediaCache.cacheStorageFile(
        ownerUserId: 'user',
        bucket: 'chat-images',
        storagePath: 'first.jpg',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final third = await mediaCache.storeBytes(
        ownerUserId: 'user',
        bucket: 'chat-images',
        storagePath: 'third.jpg',
        bytes: Uint8List(4),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await File(first).exists(), isTrue);
      expect(await File(second).exists(), isFalse);
      expect(await File(third).exists(), isTrue);
    },
  );

  test('cleans stale temporary files during first maintenance', () async {
    final stale = File(
      '${cache.path}/media_cache/test/user/chat-images/orphan.tmp',
    );
    await stale.parent.create(recursive: true);
    await stale.writeAsBytes([1, 2, 3]);
    final mediaCache = service();
    addTearDown(mediaCache.dispose);

    await mediaCache.findStorageFile(
      ownerUserId: 'user',
      bucket: 'chat-images',
      storagePath: 'missing.jpg',
    );
    expect(await stale.exists(), isFalse);
  });

  test(
    'cached file locations are restored without downloads or cache-wide maintenance',
    () async {
      final writer = service();
      final stored = await writer.storeBytes(
        ownerUserId: 'user',
        bucket: 'avatars',
        storagePath: 'avatar.jpg',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      writer.dispose();
      final orphan = File(
        '${cache.path}/media_cache/test/user/avatars/orphan.tmp',
      );
      await orphan.writeAsBytes([1]);
      final restarted = service();
      addTearDown(restarted.dispose);
      await restarted.prepareLocalPaths();
      expect(
        restarted.localStorageFilePath(
          ownerUserId: 'user',
          bucket: 'avatars',
          storagePath: 'avatar.jpg',
        ),
        stored,
      );
      expect(
        await File(
          restarted.localStorageFilePath(
            ownerUserId: 'user',
            bucket: 'avatars',
            storagePath: 'not-downloaded.jpg',
          )!,
        ).exists(),
        isFalse,
      );
      expect(
        await orphan.exists(),
        isTrue,
        reason: 'Path restoration must not enumerate/clean the whole cache.',
      );
      await restarted.findStorageFile(
        ownerUserId: 'user',
        bucket: 'avatars',
        storagePath: 'avatar.jpg',
      );
      expect(
        await orphan.exists(),
        isFalse,
        reason: 'Normal maintenance must still work.',
      );
    },
  );

  test('enforces the limit during first maintenance after restart', () async {
    final old = File('${cache.path}/media_cache/test/user/chat-images/old.jpg');
    final recent = File(
      '${cache.path}/media_cache/test/user/chat-images/recent.jpg',
    );
    await old.parent.create(recursive: true);
    await old.writeAsBytes(List.filled(6, 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await recent.writeAsBytes(List.filled(6, 2));
    final mediaCache = service();
    addTearDown(mediaCache.dispose);

    await mediaCache.findStorageFile(
      ownerUserId: 'user',
      bucket: 'chat-images',
      storagePath: 'missing.jpg',
    );
    expect(await old.exists(), isFalse);
    expect(await recent.exists(), isTrue);
  });

  test(
    'rejects a single file before it can exceed the configured limit',
    () async {
      final mediaCache = service(maxFileBytes: 3);
      addTearDown(mediaCache.dispose);
      await expectLater(
        mediaCache.storeBytes(
          ownerUserId: 'user',
          bucket: 'chat-images',
          storagePath: 'large.jpg',
          bytes: Uint8List(4),
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('logout removes current and legacy cache directories', () async {
    final mediaCache = service();
    addTearDown(mediaCache.dispose);
    final current = await mediaCache.storeBytes(
      ownerUserId: 'user',
      bucket: 'chat-images',
      storagePath: 'current.jpg',
      bytes: Uint8List(2),
    );
    final legacy = File('${support.path}/media_cache/user/chat-images/old.jpg');
    await legacy.parent.create(recursive: true);
    await legacy.writeAsBytes([1]);

    await mediaCache.clearUser('user');
    expect(await File(current).exists(), isFalse);
    expect(await legacy.exists(), isFalse);
  });
}
