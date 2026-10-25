import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
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
    required ConversationSyncService conversationSync,
    required AccountSessionController accountSessionController,
    Uuid uuid = const Uuid(),
  }) : _config = config,
       _cache = cache,
       _remote = remote,
       _mediaCache = mediaCache,
       _chatCache = chatCache,
       _conversationSync = conversationSync,
       _accountSessionController = accountSessionController,
       _uuid = uuid;

  static const _reconciliationInterval = Duration(seconds: 20);
  static const _summarySyncDebounce = Duration(milliseconds: 250);
  static const _summaryMinimumInterval = Duration(seconds: 1);

  final AppConfig _config;
  final ChatsCacheDataSource _cache;
  final ChatsRemoteDataSource _remote;
  final MediaCacheService _mediaCache;
  final ChatCacheDataSource _chatCache;
  final ConversationSyncService _conversationSync;
  final AccountSessionController _accountSessionController;
  final Uuid _uuid;
  Future<void>? _activeSync;
  Future<void>? _activeFullSync;
  AccountSessionSnapshot? _activeFullScope;
  Future<void> _summaryQueue = Future<void>.value();
  Future<void>? _activeDeletionRetry;
  Future<void> _changeQueue = Future<void>.value();
  Future<void> _muteQueue = Future<void>.value();
  final _activeReadOperations = <String, Future<void>>{};
  Object? _reconciliationToken;
  Object? _summaryBatchToken;
  final _dirtyChatIds = <String>{};
  final _summaryVersions = <String, int>{};
  final _summaryClock = Stopwatch()..start();
  int _summaryEpoch = 0;
  int _summaryVersion = 0;
  int _nextSummaryAttemptMicros = 0;
  int _summaryFailures = 0;
  bool _targetedSummariesSupported = true;
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
    _resetSummaryScheduling();
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
    ChatBulkSelection.validate(ids);
    if (ids.isEmpty) return;
    ids = Set<String>.unmodifiable(ids);
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
    ChatBulkSelection.validate(ids);
    if (ids.isEmpty) return;
    final scope = _accountSessionController.capture();
    final selected = Set<String>.unmodifiable(ids);
    final key =
        '${scope.generation}:${scope.userId}:${(ids.toList()..sort()).join(',')}';
    final active = _activeReadOperations[key];
    if (active != null) return active;
    final operation = _markAsRead(selected, scope);
    _activeReadOperations[key] = operation;
    await operation.whenComplete(() {
      if (identical(_activeReadOperations[key], operation)) {
        _activeReadOperations.remove(key);
      }
    });
  }

  Future<void> _markAsRead(
    Set<String> ids,
    AccountSessionSnapshot scope,
  ) async {
    final snapshot = await _cache.readForAction(ids, ownerUserId: scope.userId);
    _accountSessionController.ensureCurrent(scope);
    await _remote.markAsRead(ids);
    try {
      await _waitForSynchronizationIdle();
    } catch (_) {
      // A failed pre-existing list read does not undo the accepted write.
    }
    await _accountSessionController.commit(
      scope,
      () => _cache.markAsReadIfUnchanged(snapshot, ownerUserId: scope.userId),
    );
  }

  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {
    ChatBulkSelection.validate(ids);
    if (ids.isEmpty) return Future<void>.value();
    final scope = _accountSessionController.capture();
    final selectedIds = Set<String>.unmodifiable(ids);
    final operation = _muteQueue.then(
      (_) => _setMuted(selectedIds, isMuted, scope),
    );
    // Serialize writes from the list and profile. A repeated identical command
    // sees the committed cache and becomes a no-op; a failed write cannot poison
    // the queue. Each operation retains its original account generation.
    _muteQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _setMuted(
    Set<String> ids,
    bool isMuted,
    AccountSessionSnapshot scope,
  ) async {
    _accountSessionController.ensureCurrent(scope);
    final matching = await _cache.readIdsWithMuteState(
      ids,
      isMuted: isMuted,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    final changedIds = ids.difference(matching);
    if (changedIds.isEmpty) return;
    await _remote.setMuted(changedIds, isMuted: isMuted);
    try {
      // Do not let an already-running pre-write snapshot overwrite this commit.
      // No additional fetch: only wait for existing synchronization to finish.
      await _waitForSynchronizationIdle();
    } catch (_) {
      // An unrelated failed read does not undo a successfully accepted write.
    }
    await _accountSessionController.commit(
      scope,
      () => _cache.setMuted(
        changedIds,
        isMuted: isMuted,
        ownerUserId: scope.userId,
      ),
    );
  }

  @override
  Future<void> pauseRealtime() {
    _isRealtimePaused = true;
    _activeDeletionRetry = null;
    // The SDK may keep an old HTTP future alive after the transport is lost.
    // Detach that epoch so recovery never waits for it; its commit is invalid.
    _resetSummaryScheduling(clearIds: false);
    return _remote.pauseChanges();
  }

  @override
  Future<void> resumeRealtime() async {
    _isRealtimePaused = false;
    await _restartWatcherForCurrentAccount();
    await _remote.resumeChanges();
    await _retryPendingDeletions(_accountSessionController.capture());
    await _synchronize();
    _scheduleSummarySync();
  }

  Future<void> _restartWatcherForCurrentAccount() async {
    final activeScope = _watchScope;
    final currentScope = _accountSessionController.capture();
    if (activeScope == null ||
        activeScope.userId == currentScope.userId &&
            activeScope.generation == currentScope.generation) {
      return;
    }

    _resetSummaryScheduling();

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
    final epoch = _summaryEpoch;
    try {
      await _retryPendingDeletions(scope);
      if (_summaryScopeIsCurrent(scope, epoch)) await _synchronizeSafely(scope);
    } on StaleAccountSessionException {
      // Initialization can outlive logout or a foreground transition.
    }
  }

  void _enqueueChange(ConversationChange change, AccountSessionSnapshot scope) {
    if (!_accountSessionController.isCurrent(scope) || _isRealtimePaused) {
      return;
    }
    // Record at receipt time, before the serialized handler can wait on HTTP.
    // A response started earlier must not restore a subsequently hidden row.
    if (change.conversationId != null && change.reason != 'reaction_changed') {
      _summaryVersions[change.conversationId!] = ++_summaryVersion;
    }
    final epoch = _summaryEpoch;
    _changeQueue = _changeQueue
        .then((_) async {
          if (_summaryScopeIsCurrent(scope, epoch)) {
            await _handleChange(change, scope, epoch);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (error is StaleAccountSessionException) return;
          _config.talker.handle(
            error,
            stackTrace,
            'Conversation change handling failed',
          );
        });
  }

  void _enqueueReconciliation() {
    if (_reconciliationToken != null || _isRealtimePaused) return;
    final scope = _watchScope;
    if (scope == null || !_accountSessionController.isCurrent(scope)) return;
    final token = Object();
    _reconciliationToken = token;
    final epoch = _summaryEpoch;
    _changeQueue = _changeQueue
        .then((_) async {
          if (_summaryScopeIsCurrent(scope, epoch)) {
            await _synchronizeSafely(scope);
          }
        })
        .whenComplete(() {
          if (identical(_reconciliationToken, token)) {
            _reconciliationToken = null;
          }
        })
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
    int epoch,
  ) async {
    _accountSessionController.ensureCurrent(scope);
    if (_isRealtimePaused) return;
    if (change.reason == 'reaction_changed' &&
        change.conversationId != null &&
        change.messageId != null &&
        change.reactionState != null) {
      await _conversationSync.reactions.accept(
        change.conversationId!,
        change.messageId!,
        change.reactionState!,
        session: scope,
      );
      return;
    }
    await _retryPendingDeletions(scope);
    if (!_summaryScopeIsCurrent(scope, epoch)) return;
    final conversationId = change.conversationId;
    if (conversationId == null) {
      _scheduleSummarySync(immediately: true);
      return;
    }
    final pendingIds = (await _chatCache.readPendingChatDeletions(
      ownerUserId: scope.userId,
    )).map((item) => item.chatId).toSet();
    if (!_summaryScopeIsCurrent(scope, epoch)) return;
    if (change.reason == 'hidden') {
      _dirtyChatIds.remove(conversationId);
      await _accountSessionController.commit(scope, () {
        _ensureSummaryScope(scope, epoch);
        return _cache.remove({conversationId}, ownerUserId: scope.userId);
      });
      await _clearLocalConversations(
        {conversationId},
        scope,
        summaryEpoch: epoch,
      );
    } else if (!pendingIds.contains(conversationId)) {
      // Mute changes only member metadata, never message history.
      if (change.reason != 'muted' &&
          _conversationSync.isConversationOpen(conversationId)) {
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
      if (!_summaryScopeIsCurrent(scope, epoch)) return;
      _dirtyChatIds.add(conversationId);
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
    if (_dirtyChatIds.isEmpty ||
        _summarySyncTimer != null ||
        _summaryBatchToken != null) {
      return;
    }
    final remaining =
        _nextSummaryAttemptMicros - _summaryClock.elapsedMicroseconds;
    final delay = Duration(
      microseconds: remaining > _summarySyncDebounce.inMicroseconds
          ? remaining
          : _summarySyncDebounce.inMicroseconds,
    );
    final scope = _watchScope;
    if (scope == null || !_accountSessionController.isCurrent(scope)) return;
    final epoch = _summaryEpoch;
    _summarySyncTimer = Timer(delay, () {
      _summarySyncTimer = null;
      if (!_summaryScopeIsCurrent(scope, epoch)) return;
      final token = Object();
      _summaryBatchToken = token;
      _changeQueue = _changeQueue
          .then((_) async {
            if (!_summaryScopeIsCurrent(scope, epoch) ||
                _dirtyChatIds.isEmpty) {
              return;
            }
            final ids = _dirtyChatIds
                .take(ChatsRemoteDataSource.summaryBatchSize)
                .toSet();
            _dirtyChatIds.removeAll(ids);
            _nextSummaryAttemptMicros =
                _summaryClock.elapsedMicroseconds +
                _summaryMinimumInterval.inMicroseconds;
            try {
              await _enqueueSummaryOperation(
                () => _performSummaryBatch(ids, scope, epoch),
              );
              if (_summaryScopeIsCurrent(scope, epoch)) _summaryFailures = 0;
            } catch (error, stackTrace) {
              if (_summaryScopeIsCurrent(scope, epoch)) {
                _dirtyChatIds.addAll(ids);
                _summaryFailures = (_summaryFailures + 1).clamp(1, 5);
                final quotaLimited =
                    error is PostgrestException &&
                    (error.code == 'PT429' || error.code == '42901');
                final seconds = quotaLimited ? 60 : (1 << _summaryFailures);
                _nextSummaryAttemptMicros =
                    _summaryClock.elapsedMicroseconds +
                    Duration(seconds: seconds).inMicroseconds;
                _config.talker.handle(
                  error,
                  stackTrace,
                  'Chat summary batch failed; retry deferred',
                );
              }
            }
          })
          .whenComplete(() {
            if (identical(_summaryBatchToken, token)) {
              _summaryBatchToken = null;
              _scheduleSummarySync();
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            _config.talker.handle(
              error,
              stackTrace,
              'Chat summary scheduling failed',
            );
          });
    });
  }

  void _resetSummaryScheduling({bool clearIds = true}) {
    _remote.cancelSummaryRequests();
    _summaryEpoch++;
    _activeFullSync = null;
    _activeSync = null;
    _summaryQueue = Future<void>.value();
    _changeQueue = Future<void>.value();
    _reconciliationToken = null;
    _summaryBatchToken = null;
    _summarySyncTimer?.cancel();
    _summarySyncTimer = null;
    if (clearIds) {
      _dirtyChatIds.clear();
      _summaryVersions.clear();
      _summaryFailures = 0;
      _nextSummaryAttemptMicros = 0;
    }
  }

  bool _summaryScopeIsCurrent(AccountSessionSnapshot scope, int epoch) =>
      _summaryEpoch == epoch &&
      !_isRealtimePaused &&
      _accountSessionController.isCurrent(scope);

  Future<void> _clearLocalConversations(
    Set<String> ids,
    AccountSessionSnapshot scope, {
    int? summaryEpoch,
  }) async {
    final files = await _accountSessionController.commit(scope, () {
      if (summaryEpoch != null) _ensureSummaryScope(scope, summaryEpoch);
      return _chatCache.clearConversations(ids, ownerUserId: scope.userId);
    });
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
    final activeSync = _activeFullSync;
    final activeScope = _activeFullScope;
    if (activeSync != null &&
        activeScope != null &&
        _accountSessionController.isCurrent(activeScope)) {
      await activeSync;
      return;
    }
    final scope = _accountSessionController.capture();
    final epoch = _summaryEpoch;
    final sync = _enqueueSummaryOperation(
      () =>
          _config.diagnostics?.measureSync(
            'chats',
            () => _performSync(scope, epoch),
          ) ??
          _performSync(scope, epoch),
    );
    _activeFullSync = sync;
    _activeFullScope = scope;
    await sync.whenComplete(() {
      if (identical(_activeFullSync, sync)) _activeFullSync = null;
    });
  }

  Future<void> _enqueueSummaryOperation(Future<void> Function() operation) {
    final next = _summaryQueue.then((_) => operation());
    _activeSync = next;
    _summaryQueue = next.then<void>(
      (_) {
        if (identical(_activeSync, next)) _activeSync = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_activeSync, next)) _activeSync = null;
      },
    );
    return next;
  }

  void _ensureSummaryScope(AccountSessionSnapshot scope, int epoch) {
    if (!_summaryScopeIsCurrent(scope, epoch)) {
      throw const StaleAccountSessionException();
    }
  }

  Future<void> _performSync(AccountSessionSnapshot scope, int epoch) async {
    _ensureSummaryScope(scope, epoch);
    final version = _summaryVersion;
    // The first request after an OAuth return may need to establish a fresh
    // mobile connection and can legitimately take longer than a UI deadline.
    // This shared startup synchronization must eventually populate the cache;
    // navigation is independently protected by direct drafts.
    final chats = await _remote.fetchChats();
    _ensureSummaryScope(scope, epoch);
    final pendingChatIds = (await _chatCache.readPendingChatDeletions(
      ownerUserId: scope.userId,
    )).map((item) => item.chatId).toSet();
    final visibleChats = chats
        .where((chat) => !pendingChatIds.contains(chat.id))
        .toList(growable: false);
    final reconciled = await Future.wait(
      visibleChats.map((chat) => _mergeLocalPreview(chat, scope)),
    );
    await _accountSessionController.commit(scope, () async {
      _ensureSummaryScope(scope, epoch);
      final newerIds = _summaryVersions.entries
          .where((entry) => entry.value > version)
          .map((entry) => entry.key)
          .toSet();
      final preserved = await _cache.readForAction(
        newerIds,
        ownerUserId: scope.userId,
      );
      _ensureSummaryScope(scope, epoch);
      await _cache.replaceAll([
        ...reconciled.where((chat) => !newerIds.contains(chat.id)),
        ...preserved,
      ], ownerUserId: scope.userId);
      // Only returned, current rows are satisfied by a whole-list snapshot.
      // A row absent due to the legacy API cap still needs its targeted query.
      _dirtyChatIds.removeAll(
        reconciled
            .where((chat) => !newerIds.contains(chat.id))
            .map((chat) => chat.id),
      );
      if (_dirtyChatIds.isEmpty) {
        _summarySyncTimer?.cancel();
        _summarySyncTimer = null;
      }
    });
    _config.diagnostics?.recordSyncItems('chats', reconciled.length);
  }

  Future<void> _performSummaryBatch(
    Set<String> ids,
    AccountSessionSnapshot scope,
    int epoch,
  ) async {
    _ensureSummaryScope(scope, epoch);
    if (!_targetedSummariesSupported) {
      await _performSync(scope, epoch);
      return;
    }
    final version = _summaryVersion;
    late final List<Chat> chats;
    try {
      chats = await _remote.fetchChatsByIds(ids);
    } on PostgrestException catch (error) {
      // Safe rollout: an app updated before its migration retains legacy sync.
      // Other errors must retain/retry dirty IDs, never masquerade as emptiness.
      if (error.code != 'PGRST202') rethrow;
      _targetedSummariesSupported = false;
      _ensureSummaryScope(scope, epoch);
      await _performSync(scope, epoch);
      return;
    }
    _ensureSummaryScope(scope, epoch);
    if (chats.any((chat) => !ids.contains(chat.id)) ||
        chats.map((chat) => chat.id).toSet().length != chats.length) {
      throw StateError('Invalid targeted chat summary response');
    }
    final pending = (await _chatCache.readPendingChatDeletions(
      ownerUserId: scope.userId,
    )).map((item) => item.chatId).toSet();
    final reconciled = await Future.wait(
      chats
          .where((chat) => !pending.contains(chat.id))
          .map((chat) => _mergeLocalPreview(chat, scope)),
    );
    await _accountSessionController.commit(scope, () async {
      _ensureSummaryScope(scope, epoch);
      final newer = ids
          .where((id) => (_summaryVersions[id] ?? 0) > version)
          .toSet();
      _dirtyChatIds.addAll(newer);
      final currentIds = ids.difference(newer).difference(pending);
      await _cache.applySummaryBatch(
        currentIds,
        reconciled
            .where((chat) => currentIds.contains(chat.id))
            .toList(growable: false),
        ownerUserId: scope.userId,
      );
    });
    _config.diagnostics?.recordSyncItems(
      'chat_summary_batch',
      reconciled.length,
    );
  }

  Future<void> _synchronizeConversation(String chatId) async {
    await _conversationSync.synchronizeRecent(chatId, refreshAfterActive: true);
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
    final epoch = _summaryEpoch;
    try {
      await _synchronize();
    } catch (error, stackTrace) {
      if (error is StaleAccountSessionException ||
          !_summaryScopeIsCurrent(scope, epoch)) {
        return;
      }
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
