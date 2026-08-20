import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chat/conversation_sync_service.dart';
import 'package:yap_chat/repositories/chats/abstract_chats_repository.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_remote_data_source.dart';

class ChatsRepository implements IChatsRepository {
  ChatsRepository({
    required AppConfig config,
    required ChatsCacheDataSource cache,
    required ChatsRemoteDataSource remote,
    required MediaCacheService mediaCache,
    required ChatCacheDataSource chatCache,
    required ChatRemoteDataSource chatRemote,
    required ConversationSyncService conversationSync,
    Uuid uuid = const Uuid(),
  }) : _config = config,
       _cache = cache,
       _remote = remote,
       _mediaCache = mediaCache,
       _chatCache = chatCache,
       _chatRemote = chatRemote,
       _conversationSync = conversationSync,
       _uuid = uuid;

  static const _reconciliationInterval = Duration(seconds: 20);

  final AppConfig _config;
  final ChatsCacheDataSource _cache;
  final ChatsRemoteDataSource _remote;
  final MediaCacheService _mediaCache;
  final ChatCacheDataSource _chatCache;
  final ChatRemoteDataSource _chatRemote;
  final ConversationSyncService _conversationSync;
  final Uuid _uuid;
  Future<void>? _activeSync;
  Future<void>? _activeDeletionRetry;
  Future<void> _changeQueue = Future<void>.value();
  bool _reconciliationQueued = false;
  bool _isRealtimePaused = false;

  @override
  Stream<List<Chat>> watchChats() {
    late final StreamController<List<Chat>> controller;
    StreamSubscription<List<Chat>>? cacheSubscription;
    StreamSubscription<ConversationChange>? realtimeSubscription;
    Timer? reconciliationTimer;

    controller = StreamController<List<Chat>>(
      onListen: () {
        cacheSubscription = _cache.watch().listen(
          controller.add,
          onError: controller.addError,
        );
        realtimeSubscription = _remote.watchChanges().listen(
          (change) => _enqueueChange(change, controller),
          onError: (Object error, StackTrace stackTrace) {
            _config.talker.handle(error, stackTrace, 'Chats realtime failed');
          },
        );
        unawaited(_initialize(controller));
        reconciliationTimer = Timer.periodic(_reconciliationInterval, (_) {
          if (!_isRealtimePaused) _enqueueReconciliation(controller);
        });
      },
      onCancel: () async {
        reconciliationTimer?.cancel();
        await cacheSubscription?.cancel();
        await realtimeSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<Chat>> getChats() async {
    try {
      await _retryPendingDeletions();
      await _synchronize(ensureLatestMessages: true);
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
    final clearedAt = DateTime.now().toUtc();
    for (final chatId in ids) {
      await _chatCache.putPendingChatDeletion(
        id: _uuid.v4(),
        chatId: chatId,
        clearedAt: clearedAt,
      );
    }

    await _waitForSynchronizationIdle();
    await _cache.remove(ids);
    await _clearLocalConversations(ids);
    await _retryPendingDeletions();
    await _synchronize(ensureLatestMessages: true);
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

  @override
  Future<void> pauseRealtime() {
    _isRealtimePaused = true;
    return _remote.pauseChanges();
  }

  @override
  Future<void> resumeRealtime() async {
    _isRealtimePaused = false;
    await _remote.resumeChanges();
    await _retryPendingDeletions();
    await _synchronize(ensureLatestMessages: true);
  }

  Future<void> _initialize(StreamController<List<Chat>> controller) async {
    await _retryPendingDeletions();
    await _synchronizeSafely(controller, ensureLatestMessages: true);
  }

  void _enqueueChange(
    ConversationChange change,
    StreamController<List<Chat>> controller,
  ) {
    _changeQueue = _changeQueue
        .then((_) => _handleChange(change, controller))
        .catchError((Object error, StackTrace stackTrace) {
          _config.talker.handle(
            error,
            stackTrace,
            'Conversation change handling failed',
          );
        });
  }

  void _enqueueReconciliation(StreamController<List<Chat>> controller) {
    if (_reconciliationQueued) return;
    _reconciliationQueued = true;
    _changeQueue = _changeQueue
        .then((_) => _synchronizeSafely(controller, ensureLatestMessages: true))
        .whenComplete(() => _reconciliationQueued = false)
        .catchError((Object error, StackTrace stackTrace) {
          _config.talker.handle(
            error,
            stackTrace,
            'Periodic chats reconciliation failed',
          );
        });
  }

  Future<void> _handleChange(
    ConversationChange change,
    StreamController<List<Chat>> controller,
  ) async {
    await _retryPendingDeletions();
    final conversationId = change.conversationId;
    if (conversationId == null) {
      await _synchronizeSafely(controller, ensureLatestMessages: true);
      return;
    }
    final pendingIds = (await _chatCache.readPendingChatDeletions())
        .map((item) => item.chatId)
        .toSet();
    if (change.reason == 'hidden') {
      await _cache.remove({conversationId});
      await _clearLocalConversations({conversationId});
    } else if (!pendingIds.contains(conversationId)) {
      try {
        await _synchronizeConversation(conversationId);
      } catch (error, stackTrace) {
        _config.talker.handle(
          error,
          stackTrace,
          'Background conversation synchronization failed',
        );
      }
    }
    await _synchronizeSafely(controller);
  }

  Future<void> _clearLocalConversations(Set<String> ids) async {
    final files = await _chatCache.clearConversations(ids);
    try {
      await Future.wait([
        _mediaCache.removeStorageFiles(
          ownerUserId: _remote.currentUserId,
          bucket: 'chat-images',
          storagePaths: files.imageStoragePaths,
          mimeType: 'image/jpeg',
        ),
        _mediaCache.removeStorageFiles(
          ownerUserId: _remote.currentUserId,
          bucket: 'chat-audio',
          storagePaths: files.audioStoragePaths,
        ),
        _mediaCache.removeLocalFiles(files.outboxAudioPaths),
      ]);
    } catch (error, stackTrace) {
      _config.talker.handle(
        error,
        stackTrace,
        'Conversation media cleanup failed',
      );
    }
  }

  Future<void> _retryPendingDeletions() async {
    final activeRetry = _activeDeletionRetry;
    if (activeRetry != null) return activeRetry;
    final retry = _performPendingDeletionsRetry();
    _activeDeletionRetry = retry;
    await retry.whenComplete(() {
      if (identical(_activeDeletionRetry, retry)) {
        _activeDeletionRetry = null;
      }
    });
  }

  Future<void> _performPendingDeletionsRetry() async {
    final pending = await _chatCache.readPendingChatDeletions();
    for (final deletion in pending) {
      try {
        await _remote.hideChats({
          deletion.chatId,
        }, clearedAt: deletion.clearedAt);
        await _waitForSynchronizationIdle();
        await _chatCache.removePendingOperation(deletion.id);
      } catch (error, stackTrace) {
        _config.talker.handle(
          error,
          stackTrace,
          'Pending chat deletion failed',
        );
        break;
      }
    }
  }

  Future<void> _synchronize({bool ensureLatestMessages = false}) async {
    final activeSync = _activeSync;
    if (activeSync != null) {
      await activeSync;
      if (!ensureLatestMessages) return;
      final newerSync = _activeSync;
      if (newerSync != null && !identical(newerSync, activeSync)) {
        await newerSync;
        return;
      }
    }
    final sync = _performSync(ensureLatestMessages: ensureLatestMessages);
    _activeSync = sync;
    await sync.whenComplete(() {
      if (identical(_activeSync, sync)) _activeSync = null;
    });
  }

  Future<void> _performSync({required bool ensureLatestMessages}) async {
    final chats = await _remote.fetchChats();
    final pendingChatIds = (await _chatCache.readPendingChatDeletions())
        .map((item) => item.chatId)
        .toSet();
    final visibleChats = chats
        .where((chat) => !pendingChatIds.contains(chat.id))
        .toList(growable: false);
    final hydrated = await Future.wait(visibleChats.map(_hydrateAvatar));
    if (ensureLatestMessages) {
      for (final chat in hydrated) {
        final lastMessageId = chat.lastMessageId;
        if (lastMessageId == null) continue;
        final cached = await _chatCache.readMessage(
          lastMessageId,
          currentUserId: _chatRemote.currentUserId,
        );
        if (cached == null || _conversationSync.isConversationOpen(chat.id)) {
          try {
            await _synchronizeConversation(chat.id);
          } catch (error, stackTrace) {
            _config.talker.handle(
              error,
              stackTrace,
              'Conversation reconciliation failed',
            );
          }
        }
      }
    }
    final reconciled = await Future.wait(hydrated.map(_mergeLocalPreview));
    await _cache.replaceAll(reconciled);
  }

  Future<void> _synchronizeConversation(String chatId) async {
    final messages = await _conversationSync.synchronizeRecent(
      chatId,
      refreshAfterActive: true,
    );
    if (!_conversationSync.isConversationOpen(chatId)) return;
    final hasUnreadIncoming = messages.any(
      (message) => !message.isMine && message.readAt == null,
    );
    if (hasUnreadIncoming) await _chatRemote.markAsRead(chatId);
  }

  Future<void> _waitForSynchronizationIdle() async {
    while (true) {
      final active = _activeSync;
      if (active == null) return;
      await active;
    }
  }

  Future<Chat> _mergeLocalPreview(Chat chat) async {
    final messages = await _chatCache.readMessages(
      chat.id,
      currentUserId: _chatRemote.currentUserId,
    );
    final latest = messages.firstOrNull;
    if (latest == null) return chat;
    final isPending =
        latest.status == MessageStatus.sending ||
        latest.status == MessageStatus.error;
    final matchesServer = latest.id == chat.lastMessageId;
    final isNewerPending =
        isPending && !latest.timestamp.isBefore(chat.lastMessageTime);
    if (!matchesServer && !isNewerPending) return chat;

    return chat.copyWith(
      lastMessageId: latest.id,
      lastMessage: latest.text,
      lastMessageType: switch (latest.type) {
        MessageType.image => ChatPreviewType.image,
        MessageType.audio => ChatPreviewType.audio,
        MessageType.location => ChatPreviewType.location,
        MessageType.text => ChatPreviewType.text,
      },
      lastMessageTime: latest.timestamp,
      isLastMessageFromMe: latest.isMine,
    );
  }

  Future<Chat> _hydrateAvatar(Chat chat) async {
    final storagePath = chat.avatarStoragePath;
    final remoteUrl = chat.avatarUrl;
    try {
      final localPath = storagePath != null && storagePath.isNotEmpty
          ? await _mediaCache.cacheStorageFile(
              ownerUserId: _remote.currentUserId,
              bucket: 'avatars',
              storagePath: storagePath,
              mimeType: 'image/jpeg',
            )
          : remoteUrl != null && remoteUrl.isNotEmpty
          ? await _mediaCache.cacheNetworkFile(
              ownerUserId: _remote.currentUserId,
              url: remoteUrl,
            )
          : null;
      return localPath == null ? chat : chat.copyWith(avatarUrl: localPath);
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Avatar caching failed');
      return chat;
    }
  }

  Future<void> _synchronizeSafely(
    StreamController<List<Chat>> controller, {
    bool ensureLatestMessages = false,
  }) async {
    try {
      await _synchronize(ensureLatestMessages: ensureLatestMessages);
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Chats synchronization failed');
      if ((await _cache.read()).isEmpty && !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }
}
