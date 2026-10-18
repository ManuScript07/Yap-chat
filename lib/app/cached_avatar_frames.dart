import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/painting.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';

/// Prepares only the cached avatars near the top of the initial lists. Knowing
/// a file path is insufficient: FileImage still decodes asynchronously after
/// mounting. This runs during the existing cold-start phase, not in list UI.
/// It never downloads files, performs cache maintenance, or changes metadata.
class CachedAvatarFrames {
  CachedAvatarFrames({
    required this._database,
    required this._mediaCache,
    this.timeBudget = const Duration(milliseconds: 750),
  });

  final AppDatabase _database;
  final MediaCacheService _mediaCache;
  final Duration timeBudget;

  Future<void> prepare({
    required String ownerUserId,
    required double devicePixelRatio,
    required double viewportHeight,
    required bool Function() isCurrent,
  }) async {
    var stopped = false;
    final loads = <_AvatarFrameLoad>{};
    bool canContinue() => !stopped && isCurrent();
    // One viewport and the ListView's nearby cache, never an entire history.
    final height = viewportHeight.isFinite && viewportHeight > 0
        ? viewportHeight
        : 800.0;
    final limit = ((height + 250) / 76).ceil().clamp(1, 12);
    final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    final configuration = ImageConfiguration(devicePixelRatio: ratio);

    Future<void> run() async {
      if (!canContinue()) return;
      final chatQuery = _database.select(_database.cachedChats)
        ..where((row) => row.ownerUserId.equals(ownerUserId))
        ..orderBy([(row) => OrderingTerm.desc(row.lastMessageTime)])
        ..limit(limit);
      final friendQuery = _database.select(_database.cachedFriends)
        ..where((row) => row.ownerUserId.equals(ownerUserId))
        ..orderBy([
          (row) => OrderingTerm.desc(row.friendsSince),
          (row) => OrderingTerm.desc(row.userId),
        ])
        ..limit(limit);
      // Start SQLite and the single OS-directory lookup together.
      late List<CachedChat> chats;
      late List<CachedFriend> friends;
      await Future.wait([
        chatQuery.get().then<void>((rows) {
          chats = rows;
        }),
        friendQuery.get().then<void>((rows) {
          friends = rows;
        }),
        _mediaCache.prepareLocalPaths(),
      ]);
      if (!canContinue()) return;
      final providers = <ResizeImage>{};
      void add(String? storagePath, String? url, double size) {
        final storage = storagePath?.isNotEmpty == true;
        final source = storage ? storagePath : url;
        if (source == null || source.isEmpty) return;
        final location = _mediaCache.localStorageFilePath(
          ownerUserId: ownerUserId,
          bucket: storage ? 'avatars' : MediaCacheService.externalAvatarsBucket,
          storagePath: source,
          mimeType: storage ? 'image/jpeg' : null,
        );
        if (location == null) return;
        providers.add(
          ResizeImage(FileImage(File(location)), width: (size * ratio).ceil()),
        );
      }

      for (final row in chats) {
        if (!row.blockedByPeer && !row.peerIsGloballyBanned) {
          add(row.peerAvatarStoragePath, row.peerAvatarUrl, 56);
        }
      }
      for (final row in friends) {
        add(row.avatarStoragePath, row.avatarUrl, 54);
      }
      if (!canContinue()) return;
      final pending = providers.iterator;
      Future<void> worker() async {
        while (canContinue() && pending.moveNext()) {
          final provider = pending.current;
          final file = (provider.imageProvider as FileImage).file;
          if (!await file.exists() || !canContinue()) continue;
          final load = _AvatarFrameLoad(provider, configuration);
          loads.add(load);
          try {
            await load.ready;
          } finally {
            loads.remove(load);
            load.close();
          }
        }
      }

      await Future.wait(
        List.generate(math.min(4, providers.length), (_) => worker()),
      );
    }

    try {
      await run().timeout(timeBudget);
    } catch (_) {
      // Missing/corrupt cache, a busy database, or slow disk must never prevent
      // startup. The normal lazy avatar loader remains available afterwards.
    } finally {
      stopped = true;
      for (final load in loads.toList()) {
        load.close();
      }
    }
  }
}

class _AvatarFrameLoad {
  _AvatarFrameLoad(ImageProvider provider, ImageConfiguration configuration) {
    _stream = provider.resolve(configuration);
    _listener = ImageStreamListener((info, _) {
      info.dispose();
      close();
    }, onError: (_, _) => close());
    _stream.addListener(_listener);
  }

  final _ready = Completer<void>();
  late final ImageStream _stream;
  late final ImageStreamListener _listener;
  bool _closed = false;
  Future<void> get ready => _ready.future;

  void close() {
    if (_closed) return;
    _closed = true;
    _stream.removeListener(_listener);
    if (!_ready.isCompleted) _ready.complete();
  }
}
