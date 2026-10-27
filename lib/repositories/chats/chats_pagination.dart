part of 'chats_repository.dart';

extension _ChatsPagination on ChatsRepository {
  bool get _listCurrent =>
      _listScope != null && _accountSessionController.isCurrent(_listScope!);

  void _removePresentedIds(Set<String> ids) {
    if (!_listCurrent || ids.isEmpty) return;
    for (final id in ids) {
      _listRows.remove(id);
      _mainListRows?.remove(id);
      _selectedRows.remove(id);
    }
    _missingSelectedIds = {
      ..._missingSelectedIds,
      ...ids.intersection(_selectedListIds),
    };
    _emitList();
  }

  Future<void> _refreshPresentedIds(
    Set<String> ids,
    AccountSessionSnapshot scope,
  ) async {
    if (!_listCurrent || _listConsumers == 0) return;
    final generation = _listGeneration;
    final retained = ids
        .where(
          (id) =>
              _listRows.containsKey(id) ||
              (_mainListRows?.containsKey(id) ?? false),
        )
        .toSet();
    if (retained.isEmpty) return;
    final items = await _cache.readAvailableItems(
      retained,
      ownerUserId: scope.userId,
    );
    if (!_accountSessionController.isCurrent(scope) ||
        !_listCurrent ||
        generation != _listGeneration) {
      return;
    }
    for (final item in items) {
      if (_mainListRows?.containsKey(item.chat.id) ?? false) {
        _mainListRows![item.chat.id] = item;
      }
    }
    _mergeListItems(items.where((item) => _listRows.containsKey(item.chat.id)));
    _emitList();
  }

  void _mergeListItems(Iterable<ChatListLocalItem> items) {
    for (final item in items) {
      if (_activeListQuery.isEmpty ||
          item.chat.userName.toLowerCase().startsWith(_activeListQuery)) {
        _listRows[item.chat.id] = item;
      } else {
        _listRows.remove(item.chat.id);
      }
    }
  }

  Iterable<ChatListLocalItem> _sliceItems(ChatListCacheSlice slice) =>
      slice.chats.map(
        (c) => ChatListLocalItem(
          c,
          slice.orderByChatId[c.id] ?? c.lastMessageTime.microsecondsSinceEpoch,
        ),
      );

  void _acceptListHead(ChatListCacheSlice slice, String query, int generation) {
    if (!_listCurrent || _listConsumers == 0) return;
    if (query.isEmpty && _activeListQuery.isNotEmpty) {
      for (final item in _sliceItems(slice)) {
        _mainListRows?[item.chat.id] = item;
      }
      return;
    }
    if (query != _activeListQuery || generation != _listGeneration) return;
    _cacheListReady = true;
    _mergeListItems(_sliceItems(slice));
    if (_localListAfter == null && slice.chats.isNotEmpty) {
      final last = slice.chats.last;
      _localListAfter = ChatListLocalCursor(
        query: query,
        activityMicros: slice.orderByChatId[last.id]!,
        chatId: last.id,
        serverBacked: false,
      );
      _watchListTail();
    }
    _emitList();
  }

  void _emitList() {
    final controller = _listController;
    if (!_listCurrent ||
        controller == null ||
        controller.isClosed ||
        _listConsumers == 0) {
      return;
    }
    final rows = _listRows.values.toList()
      ..sort((a, b) {
        final order = b.orderMicros.compareTo(a.orderMicros);
        return order == 0 ? b.chat.id.compareTo(a.chat.id) : order;
      });
    controller.add(
      ChatListViewState(
        query: _activeListQuery,
        chats: List.unmodifiable(rows.map((e) => e.chat)),
        selectedChats: List.unmodifiable(_selectedRows.values),
        missingSelectedIds: Set.unmodifiable(_missingSelectedIds),
        ready: _cacheListReady && (rows.isNotEmpty || !_refreshingList),
        hasMoreCached: _hasMoreLocal,
        hasMoreRemote: _hasMoreRemote && !_isRealtimePaused,
        isLoadingCache: _loadingLocal,
        isLoadingRemote: _loadingRemote,
        isRefreshing: _refreshingList,
        error: _listError,
      ),
    );
  }

  void _watchListTail() {
    unawaited(_tailSubscription?.cancel());
    if (!_listCurrent || _listConsumers == 0) return;
    final generation = _listGeneration;
    _tailSubscription = _cache
        .watchAvailableSlice(
          query: _activeListQuery,
          after: _localListAfter,
          limit: 1,
          ownerUserId: _listScope!.userId,
        )
        .listen(
          (slice) {
            if (!_listCurrent || generation != _listGeneration) return;
            _hasMoreLocal = slice.chats.isNotEmpty;
            _emitList();
          },
          onError: (Object error, StackTrace _) {
            if (_listCurrent && generation == _listGeneration) {
              _listError = error;
              _emitList();
            }
          },
        );
  }

  void _watchObservedListIds() {
    unawaited(_observedListSubscription?.cancel());
    final generation = ++_observedGeneration;
    if (!_listCurrent || _listConsumers == 0) return;
    final ids = {..._visibleListIds, ..._selectedListIds};
    _observedListSubscription = _cache
        .watchAvailableIds(ids, ownerUserId: _listScope!.userId)
        .listen(
          (items) {
            if (!_listCurrent || generation != _observedGeneration) return;
            final byId = {for (final item in items) item.chat.id: item};
            for (final id in ids) {
              if (!byId.containsKey(id)) {
                _listRows.remove(id);
                _mainListRows?.remove(id);
              }
            }
            _mergeListItems(
              items.where(
                (e) =>
                    _listRows.containsKey(e.chat.id) ||
                    _visibleListIds.contains(e.chat.id),
              ),
            );
            _selectedRows
              ..clear()
              ..addEntries(
                items
                    .where((e) => _selectedListIds.contains(e.chat.id))
                    .map((e) => MapEntry(e.chat.id, e.chat)),
              );
            _missingSelectedIds = _selectedListIds.difference(
              byId.keys.toSet(),
            );
            _emitList();
          },
          onError: (Object error, StackTrace _) {
            if (_listCurrent && generation == _observedGeneration) {
              _listError = error;
              _emitList();
            }
          },
        );
  }

  Future<void> _startListQuery(String query, {bool restoreMain = false}) async {
    final generation = ++_listGeneration;
    final scope = _listScope!;
    _activeListQuery = query;
    _remote.cancelListSearchRequests();
    await _searchHeadSubscription?.cancel();
    await _tailSubscription?.cancel();
    if (!_accountSessionController.isCurrent(scope) ||
        generation != _listGeneration) {
      return;
    }
    _cacheListReady = false;
    _cacheAppend = null;
    _hasMoreLocal = false;
    _hasMoreRemote = true;
    _loadingLocal = false;
    _loadingRemote = false;
    _refreshingList = true;
    _listError = null;
    _listRows.clear();
    _localListAfter = restoreMain ? _mainListAfter : null;
    if (restoreMain && _mainListRows != null) _listRows.addAll(_mainListRows!);
    if (restoreMain) {
      _mainListRows = null;
      _mainListAfter = null;
    }
    _visibleListIds = {};
    _watchObservedListIds();
    _watchListTail();
    if (query.isEmpty) {
      final slice =
          _availableHead ??
          await _cache.readAvailableSlice(ownerUserId: scope.userId);
      _acceptListHead(slice, query, generation);
      final state = await _cache.readListState(ownerUserId: scope.userId);
      if (state.hasRemotePage) {
        _refreshingList = false;
        _hasMoreRemote = state.hasMore;
      }
    } else {
      _searchHeadSubscription = _cache
          .watchAvailableSlice(query: query, ownerUserId: scope.userId)
          .listen(
            (slice) => _acceptListHead(slice, query, generation),
            onError: (Object error, StackTrace _) {
              if (_listCurrent && generation == _listGeneration) {
                _listError = error;
                _refreshingList = false;
                _emitList();
              }
            },
          );
    }
    if (!_accountSessionController.isCurrent(scope) ||
        generation != _listGeneration) {
      return;
    }
    // Initialization already refreshes the main head through the shared queue.
    if (query.isNotEmpty && !_isRealtimePaused && _pagesSupported) {
      unawaited(
        _requestPage(
          query,
          true,
          generation,
        ).catchError((Object _, StackTrace _) {}),
      );
    }
    if (_isRealtimePaused || !_pagesSupported) {
      _refreshingList = false;
      _hasMoreRemote = false;
    }
    _emitList();
  }

  Future<void> _performPagedSync(
    AccountSessionSnapshot scope,
    int epoch,
  ) async {
    final recovery = _listRecoveryVersion;
    await _readPage('', true, scope, epoch);
    if (recovery != _listRecoveryVersion) _pageFollowup = true;
    _ensureSummaryScope(scope, epoch);
    final query = _activeListQuery;
    if (query.isNotEmpty && _listConsumers > 0) {
      final generation = _listGeneration;
      try {
        await _readPage(query, true, scope, epoch, generation: generation);
      } catch (_) {
        // Query replacement aborts only its search read. It must not publish
        // that expected cancellation as a failure of the replacement list.
        _ensureSummaryScope(scope, epoch);
        if (generation == _listGeneration) rethrow;
      }
    }
    _ensureSummaryScope(scope, epoch);
    final headIds = _verifiedHeadIds;
    _dirtyChatIds.addAll(
      {
        ..._visibleListIds,
        ..._selectedListIds,
        ..._conversationSync.openConversationIds,
      }.difference(headIds),
    );
    _scheduleSummarySync();
  }

  Future<void> _readPage(
    String query,
    bool refresh,
    AccountSessionSnapshot scope,
    int epoch, {
    int? generation,
  }) async {
    _ensureSummaryScope(scope, epoch);
    if (generation != null &&
        (generation != _listGeneration || query != _activeListQuery)) {
      return;
    }
    final request = refresh
        ? await _cache.beginListRefresh(query: query, ownerUserId: scope.userId)
        : await _cache.nextListRequest(query: query, ownerUserId: scope.userId);
    if (request == null) {
      if (query == _activeListQuery) {
        _hasMoreRemote = false;
        _emitList();
      }
      return;
    }
    final version = _summaryVersion, unreadVersion = _unreadVersion;
    final recovery = _listRecoveryVersion;
    final preserve =
        refresh &&
        !_resetRemoteContinuation &&
        _initializedQueries.contains(query);
    _ensureSummaryScope(scope, epoch);
    if (generation != null &&
        (generation != _listGeneration || query != _activeListQuery)) {
      return;
    }
    final page = await _remote.fetchChatListPage(
      after: request.after,
      searchQuery: query,
    );
    _ensureSummaryScope(scope, epoch);
    if (generation != null &&
        (generation != _listGeneration || query != _activeListQuery)) {
      return;
    }
    final pending = (await _chatCache.readPendingChatDeletions(
      ownerUserId: scope.userId,
    )).map((e) => e.chatId).toSet();
    final items = await Future.wait(
      page.items.map(
        (item) async => ChatListPageItem(
          chat: await _mergeLocalPreview(item.chat, scope),
          activityAt: item.activityAt,
        ),
      ),
    );
    await _accountSessionController.commit(scope, () async {
      _ensureSummaryScope(scope, epoch);
      if (generation != null &&
          (generation != _listGeneration || query != _activeListQuery)) {
        return;
      }
      final protected = page.items
          .where(
            (i) =>
                pending.contains(i.chat.id) ||
                (_summaryVersions[i.chat.id] ?? 0) > version,
          )
          .map((i) => i.chat.id)
          .toSet();
      final totalCurrent =
          unreadVersion == _unreadVersion && !_hasUnreadMutation(scope);
      final accepted = await _cache.applyListPage(
        request,
        ChatListPage(
          items: items,
          query: page.query,
          nextCursor: page.nextCursor,
          unreadTotal: totalCurrent ? page.unreadTotal : null,
        ),
        protectedIds: protected,
        pruneMissing: version == _summaryVersion,
        preserveContinuation: preserve,
      );
      if (!accepted) return;
      final acceptedIds = page.items
          .map((i) => i.chat.id)
          .where((id) => !protected.contains(id))
          .toSet();
      _markListVerified(acceptedIds);
      if (query.isEmpty) _verifiedHeadIds = acceptedIds;
      _initializedQueries.add(query);
      if (query.isEmpty && recovery == _listRecoveryVersion) {
        _resetRemoteContinuation = false;
      }
      _dirtyChatIds.removeAll(
        page.items.map((i) => i.chat.id).where((id) => !protected.contains(id)),
      );
      if (totalCurrent && page.unreadTotal != null) _needsUnreadRefresh = false;
      if (query.isEmpty && totalCurrent && page.unreadTotal != null) {
        _headHasConfirmedTotal = true;
      }
      if (query == _activeListQuery && _listConsumers > 0) {
        final ids = items
            .map((e) => e.chat.id)
            .where((id) => !protected.contains(id))
            .toSet();
        final rows = await _cache.readAvailableItems(
          ids,
          ownerUserId: scope.userId,
        );
        // Cache mapping preserves prepared avatar paths. No history hydration.
        _mergeListItems(rows);
        _hasMoreRemote = (await _cache.readListState(
          query: query,
          ownerUserId: scope.userId,
        )).hasMore;
        _listError = null;
        _refreshingList = false;
        _cacheListReady = true;
        _emitList();
      }
    });
  }

  Future<void> _requestPage(String query, bool refresh, int generation) {
    final scope = _accountSessionController.capture(), epoch = _summaryEpoch;
    final key = (
      scope.userId,
      scope.generation,
      epoch,
      query,
      refresh,
      generation,
    );
    final existing = _pageReads[key];
    if (existing != null) return existing;
    late final Future<void> operation;
    operation =
        _enqueueSummaryOperation(
              () => _readPage(
                query,
                refresh,
                scope,
                epoch,
                generation: generation,
              ),
            )
            .catchError((Object error, StackTrace stack) {
              if (_summaryScopeIsCurrent(scope, epoch) &&
                  generation == _listGeneration &&
                  error is! StaleAccountSessionException) {
                _listError = error;
                _refreshingList = false;
                _emitList();
              }
              Error.throwWithStackTrace(error, stack);
            })
            .whenComplete(() {
              if (identical(_pageReads[key], operation)) _pageReads.remove(key);
            });
    _pageReads[key] = operation;
    return operation;
  }
}

// Public methods are members of the existing repository. Extensions above only
// organize its implementation; no independent network coordinator is created.
