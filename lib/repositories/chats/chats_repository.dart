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
  static const _summarySyncDebounce = Duration(milliseconds: 250);

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
  StreamController<List<Chat>>? _watchController;
  StreamSubscription<List<Chat>>? _cacheSubscription;
  StreamSubscription<ConversationChange>? _realtimeSubscription;
  DiagnosticsLease? _cacheListenerLease;
  DiagnosticsLease? _realtimeListenerLease;
  Timer? _reconciliationTimer;
  Timer? _summarySyncTimer;
  AccountSessionSnapshot? _watchScope;
  List<Chat>? _latestChats;

  @override
  Stream<List<Chat>> watchChats() {
    return Stream.multi((listener) {
      StreamSubscription<List<Chat>>? subscription;
      DiagnosticsLease? listenerLease;
      var cancelled = false;

      Future<void> subscribe() async {
        final controller = _ensureWatchController();
        subscription = controller.stream.listen(
          listener.add,
          onError: listener.addError,
        );
        listenerLease = _config.diagnostics?.trackLocalListener(
          'chats-ui-stream',
        );

        // A broadcast stream does not replay. Give a late consumer the
        // current cache snapshot without starting another remote sync, timer,
        // or Realtime subscription.
        final scope = _accountSessionController.capture();
        final snapshot = _watchScope?.userId == scope.userId
            ? _latestChats
            : await _cache.read(ownerUserId: scope.userId);
        if (!cancelled && snapshot != null) listener.add(snapshot);
      }

      unawaited(subscribe());
      listener.onCancel = () async {
        cancelled = true;
        await subscription?.cancel();
        listenerLease?.dispose();
      };
    });
  }

  StreamController<List<Chat>> _ensureWatchController() {
    final existing = _watchController;
    if (existing != null && !existing.isClosed) return existing;

    late final StreamController<List<Chat>> controller;
    controller = StreamController<List<Chat>>.broadcast(
      onListen: () => unawaited(_startWatching(controller)),
      onCancel: () => unawaited(_stopWatching()),
    );
    _watchController = controller;
    return controller;
  }

  Future<void> _startWatching(StreamController<List<Chat>> controller) async {
    if (_watchScope != null) return;
    final scope = _accountSessionController.capture();
    _watchScope = scope;
    _cacheSubscription = _cache.watch(ownerUserId: scope.userId).listen((
      chats,
    ) {
      if (!_accountSessionController.isCurrent(scope) || controller.isClosed) {
        return;
      }
      _latestChats = chats;
      controller.add(chats);
    }, onError: controller.addError);
    _realtimeSubscription = _remote.watchChanges().listen(
      (change) => _enqueueChange(change, scope),
      onError: (Object error, StackTrace stackTrace) {
        _config.talker.handle(error, stackTrace, 'Chats realtime failed');
      },
    );
    _cacheListenerLease = _config.diagnostics?.trackLocalListener(
      'chats-cache',
    );
    _realtimeListenerLease = _config.diagnostics?.trackLocalListener(
      'chats-realtime-events',
    );
    unawaited(_initialize(scope));
    _reconciliationTimer = Timer.periodic(_reconciliationInterval, (_) {
      if (!_isRealtimePaused) _enqueueReconciliation();
    });
  }

  Future<void> _stopWatching() async {
    _reconciliationTimer?.cancel();
    _reconciliationTimer = null;
    _summarySyncTimer?.cancel();
    _summarySyncTimer = null;

    // Detach fields before awaiting cancellation. A new listener can arrive
    // while a StreamController is finishing its onCancel callback; it must
    // create fresh subscriptions rather than have them cleared by this older
    // teardown operation.
    final cacheSubscription = _cacheSubscription;
    final realtimeSubscription = _realtimeSubscription;
    _cacheSubscription = null;
    _realtimeSubscription = null;
    _watchScope = null;
    _latestChats = null;
    await cacheSubscription?.cancel();
    await realtimeSubscription?.cancel();
    _cacheListenerLease?.dispose();
    _cacheListenerLease = null;
    _realtimeListenerLease?.dispose();
    _realtimeListenerLease = null;
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
      await _synchronize();
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
      await _synchronize();
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
  Future<Chat?> getCachedChatByPeerId(String peerId) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return null;
    final scope = _accountSessionController.capture();
    final cached = await _cache.read(ownerUserId: scope.userId);
    _accountSessionController.ensureCurrent(scope);
    for (final chat in cached) {
      if (chat.peerId == normalizedPeerId) return chat;
    }
    return null;
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

    // A slow first summary request must not prevent navigation. The shared
    // cache sync continues in the background and an open draft is promoted
    // once the existing conversation appears there.
    unawaited(_synchronizeSafely(scope));

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
    // A preceding list refresh may still be in flight. Force a fresh summary
    // after creating/reopening the conversation so the returned id is visible
    // before ChatBloc starts sending the first message.
    await _synchronize();
    _accountSessionController.ensureCurrent(scope);
    final chat = _findChat(
      await _cache.read(ownerUserId: scope.userId),
      chatId,
    );
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
    final pendingIds = <String>[];
    await _accountSessionController.commit(scope, () async {
      for (final chatId in ids) {
        final pendingId = _uuid.v4();
        pendingIds.add(pendingId);
        await _chatCache.putPendingChatDeletion(
          id: pendingId,
          chatId: chatId,
          clearedAt: clearedAt,
          ownerUserId: scope.userId,
        );
      }
    });
    try {
      await _remote.hideChats(ids, clearedAt: clearedAt);
      _accountSessionController.ensureCurrent(scope);
    } catch (_) {
      await _accountSessionController.commit(scope, () async {
        for (final pendingId in pendingIds) {
          await _chatCache.removePendingOperation(
            pendingId,
            ownerUserId: scope.userId,
          );
        }
      });
      rethrow;
    }
    try {
      await _waitForSynchronizationIdle();
    } catch (_) {
      // The server already accepted the hide operation. Pending rows shield
      // this local commit from a stale list synchronization.
    }
    await _accountSessionController.commit(
      scope,
      () => _cache.remove(ids, ownerUserId: scope.userId),
    );
    await _clearLocalConversations(ids, scope);
    await _accountSessionController.commit(scope, () async {
      for (final pendingId in pendingIds) {
        await _chatCache.removePendingOperation(
          pendingId,
          ownerUserId: scope.userId,
        );
      }
    });
  }

  @override
  Future<void> markAsRead(Set<String> ids) async {
    if (ids.isEmpty) return;
    final scope = _accountSessionController.capture();
    await _remote.markAsRead(ids);
    await _accountSessionController.commit(
      scope,
      () => _cache.markAsRead(ids, ownerUserId: scope.userId),
    );
  }

  @override
  Future<void> toggleMute(Set<String> ids) async {
    if (ids.isEmpty) return;
    final scope = _accountSessionController.capture();
    await _remote.toggleMute(ids);
    await _accountSessionController.commit(
      scope,
      () => _cache.toggleMute(ids, ownerUserId: scope.userId),
    );
  }

  @override
  Future<void> pauseRealtime() {
    _isRealtimePaused = true;
    _activeSync = null;
    _activeDeletionRetry = null;
    _summarySyncTimer?.cancel();
    _summarySyncTimer = null;
    return _remote.pauseChanges();
  }

  @override
  Future<void> resumeRealtime() async {
    _isRealtimePaused = false;
    await _restartWatcherForCurrentAccount();
    await _remote.resumeChanges();
    await _retryPendingDeletions(_accountSessionController.capture());
    await _synchronize();
  }

  Future<void> _restartWatcherForCurrentAccount() async {
    final activeScope = _watchScope;
    final currentScope = _accountSessionController.capture();
    if (activeScope == null ||
        activeScope.userId == currentScope.userId &&
            activeScope.generation == currentScope.generation) {
      return;
    }

    await _cacheSubscription?.cancel();
    await _realtimeSubscription?.cancel();
    _cacheSubscription = null;
    _realtimeSubscription = null;
    _cacheListenerLease?.dispose();
    _cacheListenerLease = null;
    _realtimeListenerLease?.dispose();
    _realtimeListenerLease = null;
    _watchScope = null;
    _latestChats = null;
    final controller = _watchController;
    if (controller != null && controller.hasListener && !controller.isClosed) {
      await _startWatching(controller);
    }
  }

  Future<void> _initialize(AccountSessionSnapshot scope) async {
    await _retryPendingDeletions(scope);
    await _synchronizeSafely(scope);
  }

  void _enqueueChange(ConversationChange change, AccountSessionSnapshot scope) {
    _changeQueue = _changeQueue
        .then((_) => _handleChange(change, scope))
        .catchError((Object error, StackTrace stackTrace) {
          _config.talker.handle(
            error,
            stackTrace,
            'Conversation change handling failed',
          );
        });
  }

  void _enqueueReconciliation() {
    if (_reconciliationQueued) return;
    _reconciliationQueued = true;
    _changeQueue = _changeQueue
        .then((_) => _synchronizeSafely(_accountSessionController.capture()))
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
    AccountSessionSnapshot scope,
  ) async {
    _accountSessionController.ensureCurrent(scope);
    await _retryPendingDeletions(scope);
    final conversationId = change.conversationId;
    if (conversationId == null) {
      _scheduleSummarySync(immediately: true);
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
      if (_conversationSync.isConversationOpen(conversationId)) {
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
      _scheduleSummarySync();
    }
  }

  void _scheduleSummarySync({bool immediately = false}) {
    if (_isRealtimePaused) return;
    if (immediately) {
      _summarySyncTimer?.cancel();
      _summarySyncTimer = null;
      _enqueueReconciliation();
      return;
    }
    if (_summarySyncTimer != null) return;
    _summarySyncTimer = Timer(_summarySyncDebounce, () {
      _summarySyncTimer = null;
      _enqueueReconciliation();
    });
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

  Future<void> _synchronize() async {
    final activeSync = _activeSync;
    if (activeSync != null) {
      await activeSync;
      return;
    }
    final sync =
        _config.diagnostics?.measureSync('chats', _performSync) ??
        _performSync();
    _activeSync = sync;
    await sync.whenComplete(() {
      if (identical(_activeSync, sync)) _activeSync = null;
    });
  }

  Future<void> _performSync() async {
    final scope = _accountSessionController.capture();
    // The first request after an OAuth return may need to establish a fresh
    // mobile connection and can legitimately take longer than a UI deadline.
    // This shared startup synchronization must eventually populate the cache;
    // navigation is independently protected by direct drafts.
    final chats = await _remote.fetchChats();
    _accountSessionController.ensureCurrent(scope);
    final pendingChatIds = (await _chatCache.readPendingChatDeletions(
      ownerUserId: scope.userId,
    )).map((item) => item.chatId).toSet();
    final visibleChats = chats
        .where((chat) => !pendingChatIds.contains(chat.id))
        .toList(growable: false);
    final reconciled = await Future.wait(
      visibleChats.map((chat) => _mergeLocalPreview(chat, scope)),
    );
    await _accountSessionController.commit(
      scope,
      () => _cache.replaceAll(reconciled, ownerUserId: scope.userId),
    );
    _config.diagnostics?.recordSyncItems('chats', reconciled.length);
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
    final latest = await _chatCache.readLatestMessage(
      chat.id,
      currentUserId: scope.userId,
    );
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

  Future<void> _synchronizeSafely(AccountSessionSnapshot scope) async {
    try {
      await _synchronize();
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Chats synchronization failed');
      final controller = _watchController;
      if (_accountSessionController.isCurrent(scope) &&
          (await _cache.read(ownerUserId: scope.userId)).isEmpty &&
          controller != null &&
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
