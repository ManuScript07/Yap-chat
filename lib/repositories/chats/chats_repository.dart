import 'dart:async';

import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chats/abstract_chats_repository.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_remote_data_source.dart';

class ChatsRepository implements IChatsRepository {
  ChatsRepository({
    required AppConfig config,
    required ChatsCacheDataSource cache,
    required ChatsRemoteDataSource remote,
  }) : _config = config,
       _cache = cache,
       _remote = remote;

  final AppConfig _config;
  final ChatsCacheDataSource _cache;
  final ChatsRemoteDataSource _remote;
  Future<void>? _activeSync;

  @override
  Stream<List<Chat>> watchChats() {
    late final StreamController<List<Chat>> controller;
    StreamSubscription<List<Chat>>? cacheSubscription;
    StreamSubscription<void>? realtimeSubscription;

    controller = StreamController<List<Chat>>(
      onListen: () {
        cacheSubscription = _cache.watch().listen(
          controller.add,
          onError: controller.addError,
        );
        realtimeSubscription = _remote.watchChanges().listen(
          (_) => unawaited(_synchronizeSafely(controller)),
          onError: (Object error, StackTrace stackTrace) {
            _config.talker.handle(error, stackTrace, 'Chats realtime failed');
          },
        );
        unawaited(_synchronizeSafely(controller));
      },
      onCancel: () async {
        await cacheSubscription?.cancel();
        await realtimeSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<Chat>> getChats() async {
    try {
      await _synchronize();
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Chats synchronization failed');
      final cached = await _cache.read();
      if (cached.isEmpty) rethrow;
      return cached;
    }
    return _cache.read();
  }

  @override
  Future<void> deleteChats(Set<String> ids) async {
    if (ids.isEmpty) return;
    await _cache.remove(ids);
    try {
      await _remote.hideChats(ids);
    } catch (_) {
      await _synchronize();
      rethrow;
    }
  }

  @override
  Future<void> markAsRead(Set<String> ids) async {
    if (ids.isEmpty) return;
    await _cache.markAsRead(ids);
    try {
      await _remote.markAsRead(ids);
    } catch (_) {
      await _synchronize();
      rethrow;
    }
  }

  @override
  Future<void> toggleMute(Set<String> ids) async {
    if (ids.isEmpty) return;
    await _cache.toggleMute(ids);
    try {
      await _remote.toggleMute(ids);
    } catch (_) {
      await _synchronize();
      rethrow;
    }
  }

  Future<void> _synchronize() {
    final activeSync = _activeSync;
    if (activeSync != null) return activeSync;
    final sync = _performSync();
    _activeSync = sync;
    return sync.whenComplete(() {
      if (identical(_activeSync, sync)) _activeSync = null;
    });
  }

  Future<void> _performSync() async {
    final chats = await _remote.fetchChats();
    await _cache.replaceAll(chats);
  }

  Future<void> _synchronizeSafely(
    StreamController<List<Chat>> controller,
  ) async {
    try {
      await _synchronize();
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Chats synchronization failed');
      if ((await _cache.read()).isEmpty && !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }
}
