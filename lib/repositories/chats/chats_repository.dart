import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/services.dart';
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
    required AccountSessionController accountSessionController,
    Uuid uuid = const Uuid(),
  }) : _config = config,
       _cache = cache,
       _remote = remote,
       _mediaCache = mediaCache,
       _chatCache = chatCache,
       _chatRemote = chatRemote,
       _conversationSync = conversationSync,
       _accountSessionController = accountSessionController,
       _uuid = uuid;

  static const _reconciliationInterval = Duration(seconds: 20);

  final AppConfig _config;
  final ChatsCacheDataSource _cache;
  final ChatsRemoteDataSource _remote;
  final MediaCacheService _mediaCache;
  final ChatCacheDataSource _chatCache;
  final ChatRemoteDataSource _chatRemote;
  final ConversationSyncService _conversationSync;
  final AccountSessionController _accountSessionController;
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
        final scope = _accountSessionController.capture();
        cacheSubscription = _cache
            .watch(ownerUserId: scope.userId)
            .listen(controller.add, onError: controller.addError);
        realtimeSubscription = _remote.watchChanges().listen(
          (change) {
            try {
              _enqueueChange(
                change,
                controller,
                _accountSessionController.capture(),
              );
            } on StaleAccountSessionException {
              return;
            }
          },
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
  Stream<Chat?> watchChat(String chatId) {
    final scope = _accountSessionController.capture();
    return _cache
        .watch(ownerUserId: scope.userId)
        .map((chats) => _findChat(chats, chatId));
  }

  @override
  Future<List<Chat>> getChats() async {
    final scope = _accountSessionController.capture();
    try {
      await _retryPendingDeletions(scope);
      await _synchronize(ensureLatestMessages: true);
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Chats synchronization failed');
      final cached = await _cache.read(ownerUserId: scope.userId);
      if (cached.isEmpty) rethrow;
      return cached;
    }
    return _cache.read(ownerUserId: scope.userId);
  }

  @override
  Future<Chat?> getChatById(String chatId) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) return null;

    final scope = _accountSessionController.capture();
    final cachedChat = _findChat(
      await _cache.read(ownerUserId: scope.userId),
      normalizedChatId,
    );
    if (cachedChat != null) return cachedChat;

    try {
      await _synchronize(ensureLatestMessages: true);
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Chat lookup failed');
      return null;
    }

    return _findChat(
      await _cache.read(ownerUserId: scope.userId),
      normalizedChatId,
    );
  }

  @override
  Future<Chat> prepareDirectChat({
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    String? peerAvatarUrl,
    String? peerAvatarStoragePath,
  }) async {
    final scope = _accountSessionController.capture();
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) {
      throw ArgumentError.value(peerId, 'peerId', 'Peer ID must not be empty');
    }

    final cachedChat = await _cache.readByPeerId(
      normalizedPeerId,
      ownerUserId: scope.userId,
    );
    if (cachedChat != null) return cachedChat;

    try {
      await _synchronize();
      final synchronizedChat = await _cache.readByPeerId(
        normalizedPeerId,
        ownerUserId: scope.userId,
      );
      if (synchronizedChat != null) return synchronizedChat;
    } catch (error, stackTrace) {
      _config.talker.handle(
        error,
        stackTrace,
        'Direct chat lookup failed; opening a local draft',
      );
    }

    return Chat.directDraft(
      peerId: normalizedPeerId,
      peerUsername: peerUsername,
      peerDisplayName: peerDisplayName,
      peerAvatarUrl: peerAvatarUrl,
      peerAvatarStoragePath: peerAvatarStoragePath,
    );
  }

  @override
  Future<Chat> ensureDirectChat(String peerId) async {
    final scope = _accountSessionController.capture();
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) {
      throw ArgumentError.value(peerId, 'peerId', 'Peer ID must not be empty');
    }

    final cachedChat = await _cache.readByPeerId(
      normalizedPeerId,
      ownerUserId: scope.userId,
    );
    if (cachedChat != null) return cachedChat;

    final chatId = await _remote.createDirectConversation(normalizedPeerId);
    _accountSessionController.ensureCurrent(scope);
    await _synchronize();
    final chat = await getChatById(chatId);
    if (chat == null) {
      throw StateError('Created conversation is missing from summaries');
    }
    return chat;
  }

  @override
  Future<void> deleteChats(Set<String> ids) async {
    if (ids.isEmpty) return;
    final scope = _accountSessionController.capture();
    final clearedAt = DateTime.now().toUtc();
    await _accountSessionController.commit(scope, () async {
      for (final chatId in ids) {
        await _chatCache.putPendingChatDeletion(
          id: _uuid.v4(),
          chatId: chatId,
          clearedAt: clearedAt,
          ownerUserId: scope.userId,
        );
      }
    });

    await _waitForSynchronizationIdle();
    await _accountSessionController.commit(
      scope,
      () => _cache.remove(ids, ownerUserId: scope.userId),
    );
    await _clearLocalConversations(ids, scope);
    await _retryPendingDeletions(scope);
    await _synchronize(ensureLatestMessages: true);
  }

  @override
  Future<void> markAsRead(Set<String> ids) async {
    if (ids.isEmpty) return;
    final scope = _accountSessionController.capture();
    await _accountSessionController.commit(
      scope,
      () => _cache.markAsRead(ids, ownerUserId: scope.userId),
    );
    try {
      _accountSessionController.ensureCurrent(scope);
      await _remote.markAsRead(ids);
    } catch (_) {
      await _synchronize();
      rethrow;
    }
  }

  @override
  Future<void> toggleMute(Set<String> ids) async {
    if (ids.isEmpty) return;
    final scope = _accountSessionController.capture();
    await _accountSessionController.commit(
      scope,
      () => _cache.toggleMute(ids, ownerUserId: scope.userId),
    );
    try {
      _accountSessionController.ensureCurrent(scope);
      await _remote.toggleMute(ids);
    } catch (_) {
      await _synchronize();
      rethrow;
    }
  }

  @override
  Future<void> pauseRealtime() {
    _isRealtimePaused = true;
    _activeSync = null;
    _activeDeletionRetry = null;
    return _remote.pauseChanges();
  }

  @override
  Future<void> resumeRealtime() async {
    _isRealtimePaused = false;
    await _remote.resumeChanges();
    await _retryPendingDeletions(_accountSessionController.capture());
    await _synchronize(ensureLatestMessages: true);
  }

  Future<void> _initialize(StreamController<List<Chat>> controller) async {
    await _retryPendingDeletions(_accountSessionController.capture());
    await _synchronizeSafely(controller, ensureLatestMessages: true);
  }

  void _enqueueChange(
    ConversationChange change,
    StreamController<List<Chat>> controller,
    AccountSessionSnapshot scope,
  ) {
    _changeQueue = _changeQueue
        .then((_) => _handleChange(change, controller, scope))
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
    AccountSessionSnapshot scope,
  ) async {
    _accountSessionController.ensureCurrent(scope);
    await _retryPendingDeletions(scope);
    final conversationId = change.conversationId;
    if (conversationId == null) {
      await _synchronizeSafely(controller, ensureLatestMessages: true);
      return;
    }
    final pendingIds = (await _chatCache.readPendingChatDeletions(
      ownerUserId: scope.userId,
    )).map((item) => item.chatId).toSet();
    if (change.reason == 'hidden') {
      await _accountSessionController.commit(
        scope,
        () => _cache.remove({conversationId}, ownerUserId: scope.userId),
      );
      await _clearLocalConversations({conversationId}, scope);
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

  Future<void> _clearLocalConversations(
    Set<String> ids,
    AccountSessionSnapshot scope,
  ) async {
    final files = await _accountSessionController.commit(
      scope,
      () => _chatCache.clearConversations(ids, ownerUserId: scope.userId),
    );
    try {
      await Future.wait([
        _mediaCache.removeStorageFiles(
          ownerUserId: scope.userId,
          bucket: 'chat-images',
          storagePaths: files.imageStoragePaths,
          mimeType: 'image/jpeg',
        ),
        _mediaCache.removeStorageFiles(
          ownerUserId: scope.userId,
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

  Future<void> _retryPendingDeletions(AccountSessionSnapshot scope) async {
    _accountSessionController.ensureCurrent(scope);
    final activeRetry = _activeDeletionRetry;
    if (activeRetry != null) return activeRetry;
    final retry = _performPendingDeletionsRetry(scope);
    _activeDeletionRetry = retry;
    await retry.whenComplete(() {
      if (identical(_activeDeletionRetry, retry)) {
        _activeDeletionRetry = null;
      }
    });
  }

  Future<void> _performPendingDeletionsRetry(
    AccountSessionSnapshot scope,
  ) async {
    final pending = await _chatCache.readPendingChatDeletions(
      ownerUserId: scope.userId,
    );
    for (final deletion in pending) {
      try {
        _accountSessionController.ensureCurrent(scope);
        await _remote.hideChats({
          deletion.chatId,
        }, clearedAt: deletion.clearedAt);
        await _waitForSynchronizationIdle();
        await _accountSessionController.commit(
          scope,
          () => _chatCache.removePendingOperation(
            deletion.id,
            ownerUserId: scope.userId,
          ),
        );
      } on StaleAccountSessionException {
        return;
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
    final scope = _accountSessionController.capture();
    final chats = await _remote.fetchChats();
    _accountSessionController.ensureCurrent(scope);
    final pendingChatIds = (await _chatCache.readPendingChatDeletions(
      ownerUserId: scope.userId,
    )).map((item) => item.chatId).toSet();
    final visibleChats = chats
        .where((chat) => !pendingChatIds.contains(chat.id))
        .toList(growable: false);
    if (ensureLatestMessages) {
      for (final chat in visibleChats) {
        final lastMessageId = chat.lastMessageId;
        if (lastMessageId == null) continue;
        final cached = await _chatCache.readMessage(
          lastMessageId,
          currentUserId: scope.userId,
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
    final reconciled = await Future.wait(
      visibleChats.map((chat) => _mergeLocalPreview(chat, scope)),
    );
    await _accountSessionController.commit(
      scope,
      () => _cache.replaceAll(reconciled, ownerUserId: scope.userId),
    );
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

  Future<Chat> _mergeLocalPreview(
    Chat chat,
    AccountSessionSnapshot scope,
  ) async {
    final messages = await _chatCache.readMessages(
      chat.id,
      currentUserId: scope.userId,
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

  @override
  Future<String?> resolveAvatar(Chat chat) async {
    final scope = _accountSessionController.capture();
    final storagePath = chat.avatarStoragePath;
    final remoteUrl = chat.avatarUrl;
    try {
      final localPath = storagePath != null && storagePath.isNotEmpty
          ? await _mediaCache.cacheStorageFile(
              ownerUserId: scope.userId,
              bucket: 'avatars',
              storagePath: storagePath,
              mimeType: 'image/jpeg',
            )
          : remoteUrl != null && remoteUrl.isNotEmpty
          ? await _mediaCache.cacheNetworkFile(
              ownerUserId: scope.userId,
              url: remoteUrl,
            )
          : null;
      _accountSessionController.ensureCurrent(scope);
      return localPath;
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Avatar caching failed');
      return null;
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
      final ownerUserId = _accountSessionController.userId;
      if (ownerUserId != null &&
          (await _cache.read(ownerUserId: ownerUserId)).isEmpty &&
          !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }

  Chat? _findChat(List<Chat> chats, String chatId) {
    for (final chat in chats) {
      if (chat.id == chatId) return chat;
    }
    return null;
  }
}
