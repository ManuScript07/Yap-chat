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

part 'chats_pagination.dart';

class ChatsRepository
    implements
        IChatsRepository,
        IChatsPeerRepository,
        IChatsUnreadRepository,
        IChatsListRepository {
  ChatsRepository({
    required AppConfig config,
    required ChatsCacheDataSource cache,
    required ChatsRemoteDataSource remote,
    required MediaCacheService mediaCache,
    required ChatCacheDataSource chatCache,
    required ConversationSyncService conversationSync,
    required AccountSessionController accountSessionController,
    Uuid uuid = const Uuid(),
    this.enableListPagination = false,
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
  final bool enableListPagination;
  bool _pagesSupported = true;
  bool _headHasConfirmedTotal = false;
  int _listRecoveryVersion = 0;
  bool _pageFollowup = false;
  bool _resetRemoteContinuation = true;
  final _listCheckedAt = <String, int>{};
  Set<String> _verifiedHeadIds = {};

  void _markListVerified(Iterable<String> ids) {
    for (final id in ids) {
      _listCheckedAt.remove(id);
      _listCheckedAt[id] = _summaryClock.elapsedMicroseconds;
    }
    while (_listCheckedAt.length > 512) {
      _listCheckedAt.remove(_listCheckedAt.keys.first);
    }
  }

  final _initializedQueries = <String>{};
  final _listRows = <String, ChatListLocalItem>{};
  Map<String, ChatListLocalItem>? _mainListRows;
  ChatListLocalCursor? _mainListAfter;
  final _selectedRows = <String, Chat>{};
  Set<String> _visibleListIds = {},
      _selectedListIds = {},
      _missingSelectedIds = {};
  String _activeListQuery = '';
  int _listGeneration = 0, _observedGeneration = 0, _listConsumers = 0;
  AccountSessionSnapshot? _listScope;
  ChatListCacheSlice? _availableHead;
  ChatListLocalCursor? _localListAfter;
  bool _cacheListReady = false, _hasMoreLocal = false, _hasMoreRemote = true;
  bool _loadingLocal = false, _loadingRemote = false, _refreshingList = false;
  Object? _listError;
  Future<void>? _cacheAppend;
  final _pageReads = <(String, int, int, String, bool, int), Future<void>>{};
  StreamController<ChatListViewState>? _listController;
  StreamSubscription<ChatListCacheSlice>? _searchHeadSubscription,
      _tailSubscription;
  StreamSubscription<List<ChatListLocalItem>>? _observedListSubscription;
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
  bool _directLookupSupported = true;
  bool _unreadStateSupported = true;
  bool _needsUnreadRefresh = false;
  int _unreadConsumers = 0;
  int _unreadVersion = 0;
  final _unreadMutations = <Object, AccountSessionSnapshot>{};
  final _lookups = <(String, int, int, bool, String), Future<Chat?>>{};
  final _lookupQueues = <bool, Future<void>>{};
  (String, int, int)? _lookupQueueScope;
  final _directCreations = <(String, int, String), Future<Chat>>{};
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
  Stream<ChatListViewState> watchChatList() {
    final scope = _accountSessionController.capture();
    return Stream.multi((listener) {
      if (!_accountSessionController.isCurrent(scope)) {
        listener.close();
        return;
      }
      final first = _listConsumers++ == 0;
      _listController ??= StreamController<ChatListViewState>.broadcast();
      if (first) {
        _listScope = scope;
        if (_watchScope?.userId != scope.userId) _availableHead = null;
      }
      final subscription = _listController!.stream.listen(
        listener.add,
        onError: listener.addError,
      );
      final lease = _ensureWatchController().stream.listen(
        (_) {},
        onError: (Object _) {},
      );
      if (first) {
        unawaited(() async {
          try {
            await _restartWatcherForCurrentAccount();
            if (_listCurrent && identical(_listScope, scope)) {
              await _startListQuery('');
            }
          } catch (error, stack) {
            if (_accountSessionController.isCurrent(scope) &&
                identical(_listScope, scope)) {
              _listError = error;
              _refreshingList = false;
              _cacheListReady = true;
              _emitList();
              _config.talker.handle(
                error,
                stack,
                'Chat list initialization failed',
              );
            }
          }
        }());
      } else {
        _emitList();
      }
      listener.onCancel = () async {
        if (--_listConsumers == 0) {
          _listGeneration++;
          _observedGeneration++;
          _listScope = null;
          _remote.cancelListSearchRequests();
          final search = _searchHeadSubscription,
              tail = _tailSubscription,
              observed = _observedListSubscription;
          _searchHeadSubscription = null;
          _tailSubscription = null;
          _observedListSubscription = null;
          _listRows.clear();
          _mainListRows = null;
          _mainListAfter = null;
          _localListAfter = null;
          _selectedListIds = {};
          _visibleListIds = {};
          _selectedRows.clear();
          _missingSelectedIds = {};
          _activeListQuery = '';
          await Future.wait([
            if (search != null) search.cancel(),
            if (tail != null) tail.cancel(),
            if (observed != null) observed.cancel(),
          ]);
        }
        await Future.wait([subscription.cancel(), lease.cancel()]);
      };
    });
  }

  @override
  Future<void> setChatListQuery(String query) async {
    query = query.trim().toLowerCase();
    if (query.runes.length > 100) {
      query = String.fromCharCodes(query.runes.take(100));
    }
    if (!_listCurrent || query == _activeListQuery) return;
    if (_activeListQuery.isEmpty) {
      _mainListRows = Map.of(_listRows);
      _mainListAfter = _localListAfter;
    }
    await _startListQuery(query, restoreMain: query.isEmpty);
  }

  @override
  void setChatListObservedIds(Set<String> visibleIds, Set<String> selectedIds) {
    if (!_listCurrent) return;
    final visible = visibleIds.take(50).toSet(),
        selected = selectedIds.take(50).toSet();
    if (visible.length == _visibleListIds.length &&
        visible.containsAll(_visibleListIds) &&
        selected.length == _selectedListIds.length &&
        selected.containsAll(_selectedListIds)) {
      return;
    }
    _visibleListIds = visible;
    _selectedListIds = selected;
    _watchObservedListIds();
    if (enableListPagination && !_isRealtimePaused) {
      final now = _summaryClock.elapsedMicroseconds;
      _dirtyChatIds.addAll(
        {...visible, ...selected}.where(
          (id) =>
              !_listCheckedAt.containsKey(id) ||
              now - _listCheckedAt[id]! >
                  _reconciliationInterval.inMicroseconds,
        ),
      );
      _scheduleSummarySync();
    }
  }

  @override
  Future<void> loadMoreChatList({bool retry = false}) async {
    if (!_listCurrent) return;
    final active = _cacheAppend;
    if (active != null) return active;
    final scope = _listScope!,
        generation = _listGeneration,
        query = _activeListQuery;
    late final Future<void> operation;
    operation =
        () async {
          _loadingLocal = true;
          _emitList();
          try {
            final slice = await _cache.readAvailableSlice(
              query: query,
              after: _localListAfter,
              ownerUserId: scope.userId,
            );
            if (!_accountSessionController.isCurrent(scope) ||
                generation != _listGeneration) {
              return;
            }
            _mergeListItems(_sliceItems(slice));
            if (slice.chats.isNotEmpty) {
              final last = slice.chats.last;
              _localListAfter = ChatListLocalCursor(
                query: query,
                activityMicros: slice.orderByChatId[last.id]!,
                chatId: last.id,
                serverBacked: false,
              );
            }
            _hasMoreLocal = slice.hasMoreCached;
            _watchListTail();
            if (!_loadingRemote &&
                !_isRealtimePaused &&
                _pagesSupported &&
                (_listError == null || retry)) {
              final state = await _cache.readListState(
                query: query,
                ownerUserId: scope.userId,
              );
              if (generation != _listGeneration ||
                  !_accountSessionController.isCurrent(scope)) {
                return;
              }
              if (state.hasMore) {
                _loadingRemote = true;
                _listError = null;
                unawaited(
                  _requestPage(
                    query,
                    !state.hasRemotePage,
                    generation,
                  ).catchError((Object _, StackTrace _) {}).whenComplete(() {
                    if (_listCurrent && generation == _listGeneration) {
                      _loadingRemote = false;
                      _emitList();
                    }
                  }),
                );
              }
            }
          } finally {
            if (_listCurrent && generation == _listGeneration) {
              _loadingLocal = false;
              _emitList();
            }
          }
        }().whenComplete(() {
          if (identical(_cacheAppend, operation)) _cacheAppend = null;
        });
    _cacheAppend = operation;
    return operation;
  }

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
            : enableListPagination
            ? (await _cache.readAvailableSlice(ownerUserId: scope.userId)).chats
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
    final stream = enableListPagination
        ? _cache.watchAvailableSlice(ownerUserId: scope.userId).map((slice) {
            if (_accountSessionController.isCurrent(scope)) {
              _availableHead = slice;
              _acceptListHead(slice, '', _listGeneration);
            }
            return slice.chats;
          })
        : _cache.watch(ownerUserId: scope.userId);
    _cacheSubscription = stream.listen((chats) {
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
    final cacheListenerLease = _cacheListenerLease;
    final realtimeListenerLease = _realtimeListenerLease;
    _cacheSubscription = null;
    _realtimeSubscription = null;
    _cacheListenerLease = null;
    _realtimeListenerLease = null;
    _watchScope = null;
    _latestChats = null;
    await cacheSubscription?.cancel();
    await realtimeSubscription?.cancel();
    cacheListenerLease?.dispose();
    realtimeListenerLease?.dispose();
  }

  @override
  Stream<Chat?> watchChat(String chatId) {
    final scope = _accountSessionController.capture();
    return _cache
        .watchById(chatId, ownerUserId: scope.userId)
        .map(
          (chat) => _accountSessionController.isCurrent(scope) ? chat : null,
        );
  }

  @override
  Stream<Chat?> watchChatByPeerId(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) return Stream.value(null);
    final scope = _accountSessionController.capture();
    return Stream.multi((listener) {
      if (!_accountSessionController.isCurrent(scope)) {
        listener.add(null);
        listener.close();
        return;
      }
      // Keep the existing shared synchronization alive, just as watchChats
      // did for profile/draft consumers. No per-peer remote subscription or
      // initialization request is introduced. This lease does not inspect lists.
      final lease = _ensureWatchController().stream.listen(
        (_) {},
        onError: (Object _) {},
      );
      final diagnostics = _config.diagnostics?.trackLocalListener(
        'chats-peer-cache',
      );
      final subscription = _cache
          .watchByPeerId(normalized, ownerUserId: scope.userId)
          .listen(
            (chat) => listener.add(
              _accountSessionController.isCurrent(scope) ? chat : null,
            ),
            onError: listener.addError,
          );
      listener.onCancel = () async {
        try {
          await Future.wait([subscription.cancel(), lease.cancel()]);
        } finally {
          diagnostics?.dispose();
        }
      };
    });
  }

  @override
  Stream<int?> watchUnreadCount() {
    final scope = _accountSessionController.capture();
    return Stream.multi((listener) {
      if (!_accountSessionController.isCurrent(scope)) {
        listener.add(null);
        listener.close();
        return;
      }
      _unreadConsumers++;
      final lease = _ensureWatchController().stream.listen(
        (_) {},
        onError: (Object _) {},
      );
      final diagnostics = _config.diagnostics?.trackLocalListener(
        'chats-unread-cache',
      );
      final subscription = _cache
          .watchUnreadState(ownerUserId: scope.userId)
          .map(
            (state) =>
                _accountSessionController.isCurrent(scope) ? state.total : null,
          )
          .distinct()
          .listen(listener.add, onError: listener.addError);
      if (_unreadConsumers == 1 &&
          !(enableListPagination &&
              _pagesSupported &&
              _headHasConfirmedTotal)) {
        _requestUnreadRefresh();
      }
      listener.onCancel = () async {
        _unreadConsumers--;
        try {
          await Future.wait([subscription.cancel(), lease.cancel()]);
        } finally {
          diagnostics?.dispose();
        }
      };
    });
  }

  void _requestUnreadRefresh() {
    if (_unreadConsumers == 0 || !_unreadStateSupported) return;
    _needsUnreadRefresh = true;
    _scheduleSummarySync();
  }

  bool _hasUnreadMutation(AccountSessionSnapshot scope) =>
      _unreadMutations.values.any(
        (pending) =>
            pending.userId == scope.userId &&
            pending.generation == scope.generation,
      );

  Future<T> _withUnreadMutation<T>(
    AccountSessionSnapshot scope,
    Future<T> Function() operation,
  ) async {
    _accountSessionController.ensureCurrent(scope);
    final token = Object();
    _unreadMutations[token] = scope;
    _unreadVersion++;
    var accepted = false;
    try {
      final result = await operation();
      accepted = true;
      return result;
    } finally {
      _unreadMutations.remove(token);
      if (_accountSessionController.isCurrent(scope)) {
        _unreadVersion++;
        if (accepted && _unreadConsumers > 0 && _unreadStateSupported) {
          // Join the existing queue even when no Realtime event arrives.
          // Metadata was already committed locally: only outstanding dirty IDs
          // need another read. Never derive a total from possibly stale rows.
          _requestUnreadRefresh();
        }
      }
    }
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
    final cachedChat = await _cache.readById(
      normalizedChatId,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    if (cachedChat != null) return cachedChat;

    try {
      return await _lookupChat(normalizedChatId, byPeer: false, scope: scope);
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Chat lookup failed');
      return null;
    }
  }

  @override
  Future<Chat?> getCachedChatByPeerId(String peerId) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return null;
    final scope = _accountSessionController.capture();
    final cached = await _cache.readByPeerId(
      normalizedPeerId,
      ownerUserId: scope.userId,
    );
    _accountSessionController.ensureCurrent(scope);
    return cached;
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
    _accountSessionController.ensureCurrent(scope);
    if (cachedChat != null) return cachedChat;

    // Navigation remains immediate. A single-peer read promotes a draft when
    // the conversation exists outside the loaded list; it never creates one.
    unawaited(_lookupPeerSafely(normalizedPeerId, scope));

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
    _accountSessionController.ensureCurrent(scope);
    if (cachedChat != null) return cachedChat;

    final key = (scope.userId, scope.generation, normalizedPeerId);
    final existing = _directCreations[key];
    if (existing != null) return existing;
    late final Future<Chat> operation;
    operation = _createDirectChat(normalizedPeerId, scope).whenComplete(() {
      if (identical(_directCreations[key], operation)) {
        _directCreations.remove(key);
      }
    });
    _directCreations[key] = operation;
    return operation;
  }

  Future<Chat> _createDirectChat(
    String peerId,
    AccountSessionSnapshot scope,
  ) async {
    final chatId = await _remote.createDirectConversation(peerId);
    _accountSessionController.ensureCurrent(scope);
    final chat = await _lookupChat(chatId, byPeer: false, scope: scope);
    if (chat == null) {
      throw StateError('Created conversation is missing from summaries');
    }
    return chat;
  }

  Future<void> _lookupPeerSafely(
    String peerId,
    AccountSessionSnapshot scope,
  ) async {
    try {
      await _lookupChat(peerId, byPeer: true, scope: scope);
    } catch (error, stackTrace) {
      if (error is StaleAccountSessionException ||
          !_accountSessionController.isCurrent(scope)) {
        return;
      }
      _config.talker.handle(error, stackTrace, 'Direct chat lookup failed');
    }
  }

  Future<Chat?> _lookupChat(
    String value, {
    required bool byPeer,
    required AccountSessionSnapshot scope,
  }) {
    final epoch = _summaryEpoch;
    final identity = (scope.userId, scope.generation, epoch);
    if (_lookupQueueScope != identity) {
      _lookupQueueScope = identity;
      _lookupQueues.clear();
    }
    final key = (scope.userId, scope.generation, epoch, byPeer, value);
    final existing = _lookups[key];
    if (existing != null) return existing;
    // Two bounded read lanes: an optional peer lookup cannot delay opening a
    // known conversation after an accepted first-send creation. Each lane is
    // serial; all requests reuse the same SDK client and cancellation scope.
    late final Future<Chat?> operation;
    operation = (_lookupQueues[byPeer] ?? Future<void>.value())
        .then((_) async {
          _ensureSummaryScope(scope, epoch);
          // An event can invalidate the first response before the row has ever
          // entered the cache. Retry once rather than silently losing a push
          // navigation; a busy conversation cannot create an unbounded loop.
          for (var attempt = 0; attempt < 2; attempt++) {
            final version = _summaryVersion;
            List<Chat> chats;
            try {
              if (byPeer && _directLookupSupported) {
                final chat = await _remote.fetchChatByPeerId(value);
                chats = chat == null ? const [] : [chat];
              } else if (!byPeer && _targetedSummariesSupported) {
                chats = await _remote.fetchChatsByIds({value});
              } else {
                await _synchronize();
                _ensureSummaryScope(scope, epoch);
                return await _readLookupCache(value, byPeer, scope, epoch);
              }
            } on PostgrestException catch (error) {
              if (error.code != 'PGRST202') rethrow;
              _ensureSummaryScope(scope, epoch);
              if (byPeer) {
                _directLookupSupported = false;
              } else {
                _targetedSummariesSupported = false;
              }
              await _synchronize();
              _ensureSummaryScope(scope, epoch);
              return _readLookupCache(value, byPeer, scope, epoch);
            }
            _ensureSummaryScope(scope, epoch);
            if (byPeer &&
                (chats.length > 1 ||
                    chats.any(
                      (chat) => chat.peerId != value || chat.id.isEmpty,
                    ))) {
              throw const FormatException('Invalid direct chat summary');
            }
            final ids = byPeer ? chats.map((chat) => chat.id).toSet() : {value};
            await _applySummaryResult(
              ids,
              chats,
              scope,
              epoch,
              version,
              protectAgainstSnapshot: true,
            );
            _ensureSummaryScope(scope, epoch);
            final cached = await _readLookupCache(value, byPeer, scope, epoch);
            if (cached != null ||
                chats.isEmpty ||
                attempt == 1 ||
                !ids.any((id) => (_summaryVersions[id] ?? 0) > version)) {
              return cached;
            }
          }
          return null;
        })
        .whenComplete(() {
          if (identical(_lookups[key], operation)) _lookups.remove(key);
        });
    _lookups[key] = operation;
    _lookupQueues[byPeer] = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<Chat?> _readLookupCache(
    String value,
    bool byPeer,
    AccountSessionSnapshot scope,
    int epoch,
  ) async {
    final chat = byPeer
        ? await _cache.readByPeerId(value, ownerUserId: scope.userId)
        : await _cache.readById(value, ownerUserId: scope.userId);
    _ensureSummaryScope(scope, epoch);
    return chat;
  }

  @override
  Future<void> deleteChats(Set<String> ids) async {
    ChatBulkSelection.validate(ids);
    if (ids.isEmpty) return;
    ids = Set<String>.unmodifiable(ids);
    final scope = _accountSessionController.capture();
    return _withUnreadMutation(scope, () => _deleteChats(ids, scope));
  }

  Future<void> _deleteChats(
    Set<String> ids,
    AccountSessionSnapshot scope,
  ) async {
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
    if (_accountSessionController.isCurrent(scope)) _removePresentedIds(ids);
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
    final operation = _withUnreadMutation(
      scope,
      () => _markAsRead(selected, scope),
    );
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
    return _withUnreadMutation(
      scope,
      () => _commitMuted(changedIds, isMuted, scope),
    );
  }

  Future<void> _commitMuted(
    Set<String> changedIds,
    bool isMuted,
    AccountSessionSnapshot scope,
  ) async {
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
    _resetRemoteContinuation = true;
    _initializedQueries.clear();
    _isRealtimePaused = true;
    _emitList();
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
    _availableHead = null;
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
    if (change.reason != 'reaction_changed') _unreadVersion++;
    if (change.conversationId == null) {
      _listRecoveryVersion++;
      _resetRemoteContinuation = true;
      _initializedQueries.clear();
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
            if (_pageFollowup) {
              _pageFollowup = false;
              _enqueueReconciliation();
            }
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
      if (_summaryScopeIsCurrent(scope, epoch)) {
        _removePresentedIds({conversationId});
      }
      await _clearLocalConversations(
        {conversationId},
        scope,
        summaryEpoch: epoch,
      );
      _requestUnreadRefresh();
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
    final needsUnread =
        _needsUnreadRefresh && _unreadConsumers > 0 && _unreadStateSupported;
    if ((_dirtyChatIds.isEmpty && !needsUnread) ||
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
                (_dirtyChatIds.isEmpty && !_needsUnreadRefresh)) {
              return;
            }
            final ids = _dirtyChatIds
                .take(ChatsRemoteDataSource.summaryBatchSize)
                .toSet();
            _dirtyChatIds.removeAll(ids);
            _needsUnreadRefresh = false;
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
                if (_unreadConsumers > 0 && _unreadStateSupported) {
                  _needsUnreadRefresh = true;
                }
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
    _pageFollowup = false;
    _headHasConfirmedTotal = false;
    _listCheckedAt.clear();
    _verifiedHeadIds = {};
    _initializedQueries.clear();
    _resetRemoteContinuation = true;
    _remote.cancelSummaryRequests();
    _summaryEpoch++;
    _lookupQueues.clear();
    _lookupQueueScope = null;
    _activeFullSync = null;
    _activeSync = null;
    _summaryQueue = Future<void>.value();
    _changeQueue = Future<void>.value();
    _reconciliationToken = null;
    _summaryBatchToken = null;
    _summarySyncTimer?.cancel();
    _summarySyncTimer = null;
    if (clearIds) {
      _needsUnreadRefresh = false;
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
      if (_pageFollowup && _reconciliationToken == null) {
        _pageFollowup = false;
        _enqueueReconciliation();
      }
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
    if (enableListPagination && _pagesSupported) {
      try {
        await _performPagedSync(scope, epoch);
        return;
      } on PostgrestException catch (error) {
        if (error.code != 'PGRST202') rethrow;
        _ensureSummaryScope(scope, epoch);
        _pagesSupported = false;
        _hasMoreRemote = false;
      }
    }
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
      // An open conversation can be outside a capped legacy snapshot (and,
      // later, outside loaded pages). Verify its absence by an addressed read,
      // not by dropping live metadata because it is absent from the first 1000.
      final outsideOpenIds = _conversationSync.openConversationIds
          .difference(visibleChats.map((chat) => chat.id).toSet())
          .difference(pendingChatIds);
      newerIds.addAll(outsideOpenIds);
      _dirtyChatIds.addAll(outsideOpenIds);
      final preserved = await _cache.readForAction(
        newerIds,
        ownerUserId: scope.userId,
      );
      _ensureSummaryScope(scope, epoch);
      final accepted = [
        ...reconciled.where((chat) => !newerIds.contains(chat.id)),
        ...preserved,
      ];
      if (enableListPagination) {
        // A capped legacy response cannot prove cached tail rows inaccessible.
        await _cache.applySummaryBatch(
          accepted.map((c) => c.id).toSet(),
          accepted,
          ownerUserId: scope.userId,
        );
      } else {
        await _cache.replaceAll(accepted, ownerUserId: scope.userId);
      }
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
    _scheduleSummarySync();
    _requestUnreadRefresh();
    if (enableListPagination && !_pagesSupported) {
      _refreshingList = false;
      _hasMoreRemote = false;
      _emitList();
    }
    _config.diagnostics?.recordSyncItems('chats', reconciled.length);
  }

  Future<void> _performSummaryBatch(
    Set<String> ids,
    AccountSessionSnapshot scope,
    int epoch,
  ) async {
    _ensureSummaryScope(scope, epoch);
    if (_unreadConsumers > 0 && _unreadStateSupported) {
      final version = _summaryVersion;
      final unreadVersion = _unreadVersion;
      final unread = await _cache.readUnreadState(ownerUserId: scope.userId);
      _ensureSummaryScope(scope, epoch);
      try {
        final response = await _remote.fetchUnreadState(conversationIds: ids);
        await _applySummaryResult(
          ids,
          response.chats,
          scope,
          epoch,
          version,
          unreadTotal: response.unreadTotal,
          unreadRevision: unread.revision,
          unreadVersion: unreadVersion,
        );
        return;
      } on PostgrestException catch (error) {
        if (error.code != 'PGRST202') rethrow;
        _ensureSummaryScope(scope, epoch);
        _unreadStateSupported = false;
        _needsUnreadRefresh = false;
      }
    }
    if (ids.isEmpty) return;
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
    await _applySummaryResult(ids, chats, scope, epoch, version);
  }

  Future<void> _applySummaryResult(
    Set<String> ids,
    List<Chat> chats,
    AccountSessionSnapshot scope,
    int epoch,
    int version, {
    bool protectAgainstSnapshot = false,
    int? unreadTotal,
    int? unreadRevision,
    int? unreadVersion,
  }) async {
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
      final pendingNow = protectAgainstSnapshot
          ? (await _chatCache.readPendingChatDeletions(
              ownerUserId: scope.userId,
            )).map((item) => item.chatId).toSet()
          : pending;
      _ensureSummaryScope(scope, epoch);
      final newer = ids
          .where((id) => (_summaryVersions[id] ?? 0) > version)
          .toSet();
      _dirtyChatIds.addAll(newer);
      final currentIds = ids.difference(newer).difference(pendingNow);
      await _cache.applySummaryBatch(
        currentIds,
        reconciled
            .where((chat) => currentIds.contains(chat.id))
            .toList(growable: false),
        ownerUserId: scope.userId,
        activityByChatId: {
          for (final chat in chats)
            if (currentIds.contains(chat.id))
              chat.id: chat.lastMessageTime.toUtc(),
        },
      );
      _markListVerified(currentIds);
      _removePresentedIds(
        currentIds.difference(chats.map((c) => c.id).toSet()),
      );
      await _refreshPresentedIds(currentIds, scope);
      if (unreadTotal != null &&
          unreadVersion == _unreadVersion &&
          !_hasUnreadMutation(scope)) {
        await _cache.applyUnreadTotal(
          unreadTotal,
          expectedRevision: unreadRevision!,
          ownerUserId: scope.userId,
        );
      }
      if (protectAgainstSnapshot) {
        _dirtyChatIds.removeAll(currentIds);
        for (final id in currentIds) {
          _summaryVersions[id] = ++_summaryVersion;
        }
      }
    });
    if (protectAgainstSnapshot) _scheduleSummarySync();
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
      if (enableListPagination) {
        _listError = error;
        _refreshingList = false;
        _emitList();
      }
      final controller = _watchController;
      if (_accountSessionController.isCurrent(scope) &&
          (enableListPagination
              ? (await _cache.readAvailableSlice(
                  ownerUserId: scope.userId,
                )).chats.isEmpty
              : (await _cache.read(ownerUserId: scope.userId)).isEmpty) &&
          controller != null &&
          !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }
}
