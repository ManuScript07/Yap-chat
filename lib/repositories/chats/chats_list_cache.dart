part of 'chats_cache_data_source.dart';

/// Prepared page storage. It does not start synchronization or subscriptions.
extension ChatsListCache on ChatsCacheDataSource {
  static const _uuid = Uuid();
  static const maximumSliceSize = 200;

  String _listQuery(String value) {
    final query = value.trim().toLowerCase();
    if (query.runes.length > 100) throw ArgumentError('Chat query is too long');
    return query;
  }

  Future<ChatListCacheState> readListState({
    String query = '',
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final normalized = _listQuery(query);
    final row =
        await (_database.select(_database.cachedChatListStates)..where(
              (t) => t.ownerUserId.equals(owner) & t.query.equals(normalized),
            ))
            .getSingleOrNull();
    return row == null
        ? ChatListCacheState(query: normalized)
        : _listState(row);
  }

  ChatListCacheState _listState(CachedChatListState row) => ChatListCacheState(
    query: row.query,
    revision: row.revision,
    hasRemotePage: row.hasRemotePage,
    checkedAt: row.checkedAt,
    nextCursor: row.nextActivityMicros == null || row.nextChatId == null
        ? null
        : ChatListPageCursor(
            activityAt: DateTime.fromMicrosecondsSinceEpoch(
              row.nextActivityMicros!,
              isUtc: true,
            ),
            conversationId: row.nextChatId!,
            query: row.query,
          ),
  );

  Stream<ChatListCacheState> watchListState({
    String query = '',
    String? ownerUserId,
  }) {
    final owner = ownerUserId ?? _userIdProvider();
    final normalized = _listQuery(query);
    return (_database.select(_database.cachedChatListStates)..where(
          (t) => t.ownerUserId.equals(owner) & t.query.equals(normalized),
        ))
        .watchSingleOrNull()
        .map(
          (row) => row == null
              ? ChatListCacheState(query: normalized)
              : _listState(row),
        );
  }

  Future<ChatUnreadCacheState> readUnreadState({String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    final row = await (_database.select(
      _database.cachedChatUnreadTotals,
    )..where((t) => t.ownerUserId.equals(owner))).getSingleOrNull();
    return row == null ? const ChatUnreadCacheState() : _unreadState(row);
  }

  ChatUnreadCacheState _unreadState(CachedChatUnreadTotal row) =>
      ChatUnreadCacheState(
        total: row.unreadTotal,
        revision: row.revision,
        checkedAt: row.checkedAt,
      );

  Stream<ChatUnreadCacheState> watchUnreadState({String? ownerUserId}) {
    final owner = ownerUserId ?? _userIdProvider();
    return (_database.select(
      _database.cachedChatUnreadTotals,
    )..where((t) => t.ownerUserId.equals(owner))).watchSingleOrNull().map(
      (row) => row == null ? const ChatUnreadCacheState() : _unreadState(row),
    );
  }

  /// A local mutation or Realtime event invalidates in-flight badge snapshots,
  /// retaining the last confirmed value for offline display.
  Future<void> invalidateUnreadState({String? ownerUserId}) async {
    final owner = ownerUserId ?? _userIdProvider();
    await _database.transaction(() async {
      final previous = await readUnreadState(ownerUserId: owner);
      await _database
          .into(_database.cachedChatUnreadTotals)
          .insertOnConflictUpdate(
            CachedChatUnreadTotalsCompanion.insert(
              ownerUserId: owner,
              revision: Value(previous.revision + 1),
            ),
          );
    });
  }

  /// Reused by page and addressed-summary responses; caller captures the
  /// revision before HTTP and invalidates it on any newer local/event change.
  Future<bool> applyUnreadTotal(
    int total, {
    required int expectedRevision,
    String? ownerUserId,
  }) async {
    if (total < 0 || expectedRevision < 0) {
      throw ArgumentError('Invalid unread snapshot');
    }
    final owner = ownerUserId ?? _userIdProvider();
    return _database.transaction(() async {
      final previous = await readUnreadState(ownerUserId: owner);
      if (previous.revision != expectedRevision) return false;
      await _database
          .into(_database.cachedChatUnreadTotals)
          .insertOnConflictUpdate(
            CachedChatUnreadTotalsCompanion.insert(
              ownerUserId: owner,
              revision: Value(previous.revision + 1),
              unreadTotal: Value(total),
              checkedAt: Value(DateTime.now().toUtc()),
            ),
          );
      return true;
    });
  }

  /// Start a new head request without clearing displayed rows or old coverage.
  Future<ChatListCacheRequest> beginListRefresh({
    String query = '',
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final normalized = _listQuery(query);
    return _database.transaction(() async {
      final revision = _uuid.v4();
      await _database
          .into(_database.cachedChatListStates)
          .insertOnConflictUpdate(
            CachedChatListStatesCompanion.insert(
              ownerUserId: owner,
              query: normalized,
              revision: revision,
            ),
          );
      // Keep the head and at most eight search queries. Dropping query coverage
      // never drops metadata/messages; UUID revisions prevent eviction ABA.
      final searches =
          await (_database.select(_database.cachedChatListStates)
                ..where(
                  (t) =>
                      t.ownerUserId.equals(owner) &
                      t.query.equals('').not() &
                      t.query.equals(normalized).not(),
                )
                ..orderBy([
                  (t) => OrderingTerm.desc(t.checkedAt),
                  (t) => OrderingTerm.asc(t.query),
                ]))
              .get();
      final stale = searches
          .skip(normalized.isEmpty ? 8 : 7)
          .map((r) => r.query)
          .toSet();
      if (stale.isNotEmpty) {
        await (_database.delete(_database.cachedChatListEntries)
              ..where((t) => t.ownerUserId.equals(owner) & t.query.isIn(stale)))
            .go();
        await (_database.delete(_database.cachedChatListStates)
              ..where((t) => t.ownerUserId.equals(owner) & t.query.isIn(stale)))
            .go();
      }
      return ChatListCacheRequest(
        ownerUserId: owner,
        query: normalized,
        revision: revision,
        unreadRevision: (await readUnreadState(ownerUserId: owner)).revision,
      );
    });
  }

  Future<ChatListCacheRequest?> nextListRequest({
    String query = '',
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    return _database.transaction(() async {
      final state = await readListState(query: query, ownerUserId: owner);
      if (!state.hasRemotePage || state.nextCursor == null) return null;
      return ChatListCacheRequest(
        ownerUserId: owner,
        query: state.query,
        revision: state.revision!,
        after: state.nextCursor,
        unreadRevision: (await readUnreadState(ownerUserId: owner)).revision,
      );
    });
  }

  int _position(DateTime time, String id, ChatListPageCursor cursor) {
    final compared = time.toUtc().compareTo(cursor.activityAt.toUtc());
    return compared != 0 ? compared : id.compareTo(cursor.conversationId);
  }

  void _validateListPage(
    ChatListCacheRequest request,
    ChatListPage page,
    Set<String> protectedIds,
  ) {
    if (request.query != _listQuery(request.query) ||
        page.query != request.query ||
        request.ownerUserId.isEmpty ||
        page.items.length > 50 ||
        protectedIds.length > maximumSliceSize ||
        (page.unreadTotal != null && page.unreadTotal! < 0) ||
        (request.after != null && request.after!.query != request.query)) {
      throw ArgumentError('Invalid chat list page');
    }
    final ids = <String>{};
    ChatListPageItem? previous;
    for (final item in page.items) {
      final id = item.chat.id;
      if (id.isEmpty ||
          !ids.add(id) ||
          (request.after != null &&
              _position(item.activityAt, id, request.after!) >= 0) ||
          (previous != null &&
              _position(
                    item.activityAt,
                    id,
                    ChatListPageCursor(
                      activityAt: previous.activityAt,
                      conversationId: previous.chat.id,
                    ),
                  ) >=
                  0)) {
        throw ArgumentError('Invalid page order or identity');
      }
      previous = item;
    }
    final next = page.nextCursor;
    if (next != null &&
        (next.query != request.query ||
            next.conversationId.isEmpty ||
            (request.after != null &&
                _position(
                      next.activityAt,
                      next.conversationId,
                      request.after!,
                    ) >=
                    0) ||
            (previous != null &&
                _position(
                      next.activityAt,
                      next.conversationId,
                      ChatListPageCursor(
                        activityAt: previous.activityAt,
                        conversationId: previous.chat.id,
                      ),
                    ) >
                    0))) {
      throw ArgumentError('Invalid next page cursor');
    }
  }

  /// CAS commit: metadata, query coverage, original cursor and badge are atomic.
  /// A successful empty range prunes query membership, never unrelated metadata
  /// or message history. The caller protects IDs with newer local mutations.
  Future<bool> applyListPage(
    ChatListCacheRequest request,
    ChatListPage page, {
    Set<String> protectedIds = const {},
  }) async {
    _validateListPage(request, page, protectedIds);
    final owner = request.ownerUserId;
    return _database.transaction(() async {
      final current = await readListState(
        query: request.query,
        ownerUserId: owner,
      );
      if (current.revision != request.revision) return false;
      if (request.after != null &&
          (current.nextCursor == null ||
              _position(
                    request.after!.activityAt,
                    request.after!.conversationId,
                    current.nextCursor!,
                  ) !=
                  0)) {
        return false;
      }
      final keep = {...page.items.map((i) => i.chat.id), ...protectedIds};
      final conditions = <String>['owner_user_id = ?', 'query = ?'];
      final variables = <Variable>[
        Variable<String>(owner),
        Variable<String>(request.query),
      ];
      if (request.after case final after?) {
        conditions.add('(activity_micros, chat_id) < (?, ?)');
        variables.addAll([
          Variable<int>(after.activityAt.microsecondsSinceEpoch),
          Variable<String>(after.conversationId),
        ]);
      }
      if (page.nextCursor case final end?) {
        conditions.add('(activity_micros, chat_id) >= (?, ?)');
        variables.addAll([
          Variable<int>(end.activityAt.microsecondsSinceEpoch),
          Variable<String>(end.conversationId),
        ]);
      }
      if (keep.isNotEmpty) {
        conditions.add(
          'chat_id NOT IN (${List.filled(keep.length, '?').join(',')})',
        );
        variables.addAll(keep.map(Variable<String>.new));
      }
      await _database.customUpdate(
        'DELETE FROM cached_chat_list_entries WHERE ${conditions.join(' AND ')}',
        variables: variables,
        updates: {_database.cachedChatListEntries},
      );
      final items = page.items
          .where((i) => !protectedIds.contains(i.chat.id))
          .toList(growable: false);
      final cached = {
        for (final chat in await readForAction(
          items.map((i) => i.chat.id).toSet(),
          ownerUserId: owner,
        ))
          chat.id: chat,
      };
      // A plain IN can choose the covering order index and filter every entry
      // in this query. Keep the small requested set outermost for PK probes.
      final entries = items.isEmpty
          ? <QueryRow>[]
          : await _database
                .customSelect(
                  '''
        WITH requested(id) AS (VALUES ${List.filled(items.length, '(?)').join(',')})
        SELECT e.* FROM requested r CROSS JOIN cached_chat_list_entries e
        WHERE e.owner_user_id=? AND e.query=? AND e.chat_id=r.id
      ''',
                  variables: [
                    ...items.map((i) => Variable<String>(i.chat.id)),
                    Variable<String>(owner),
                    Variable<String>(request.query),
                  ],
                  readsFrom: {_database.cachedChatListEntries},
                )
                .get();
      final activity = {
        for (final e in entries)
          e.read<String>('chat_id'): e.read<int>('activity_micros'),
      };
      for (final item in items) {
        if (cached[item.chat.id] == null ||
            !_sameChat(cached[item.chat.id]!, item.chat)) {
          await _database
              .into(_database.cachedChats)
              .insertOnConflictUpdate(_companion(item.chat, owner));
        }
        if (activity[item.chat.id] != item.activityAt.microsecondsSinceEpoch) {
          await _database
              .into(_database.cachedChatListEntries)
              .insertOnConflictUpdate(
                CachedChatListEntriesCompanion.insert(
                  ownerUserId: owner,
                  query: request.query,
                  chatId: item.chat.id,
                  activityMicros: item.activityAt.microsecondsSinceEpoch,
                ),
              );
        }
      }
      await _database
          .into(_database.cachedChatListStates)
          .insertOnConflictUpdate(
            CachedChatListStatesCompanion.insert(
              ownerUserId: owner,
              query: request.query,
              revision: _uuid.v4(),
              hasRemotePage: const Value(true),
              nextActivityMicros: Value(
                page.nextCursor?.activityAt.microsecondsSinceEpoch,
              ),
              nextChatId: Value(page.nextCursor?.conversationId),
              checkedAt: Value(DateTime.now().toUtc()),
            ),
          );
      if (page.unreadTotal != null) {
        await applyUnreadTotal(
          page.unreadTotal!,
          expectedRevision: request.unreadRevision,
          ownerUserId: owner,
        );
      }
      return true;
    });
  }

  Selectable<QueryRow> _listSliceQuery(
    String owner,
    String query,
    int limit,
    ChatListLocalCursor? after,
    bool server,
  ) {
    if (limit < 1 ||
        limit > maximumSliceSize ||
        (after != null && after.query != query)) {
      throw ArgumentError('Invalid local chat slice');
    }
    // Select just one source: a false UNION branch can still walk its index.
    final variables = <Variable>[];
    String prefix(String alias) {
      if (query.isEmpty) return '';
      final runes = query.runes.toList();
      var upper = '';
      for (var i = runes.length - 1; i >= 0; i--) {
        if (runes[i] < 0x10ffff) {
          var next = runes[i] + 1;
          if (next == 0xd800) next = 0xe000;
          upper = String.fromCharCodes([...runes.take(i), next]);
          break;
        }
      }
      variables.add(Variable<String>(query));
      if (upper.isEmpty) return ' AND $alias.peer_display_name_search >= ?';
      variables.add(Variable<String>(upper));
      return ' AND $alias.peer_display_name_search >= ? AND $alias.peer_display_name_search < ?';
    }

    variables.add(Variable<String>(owner));
    if (server) variables.add(Variable<String>(query));
    final namePredicate = prefix('c');
    if (after != null) {
      variables.addAll([
        Variable<int>(after.activityMicros),
        Variable<String>(after.chatId),
      ]);
    }
    variables.add(Variable<int>(limit + 1));
    final activity = server
        ? 'e.activity_micros'
        : 'c.last_message_time * 1000000';
    final id = server ? 'e.chat_id' : 'c.id';
    return _database.customSelect(
      '''
      SELECT c.*, $activity AS order_micros, $id AS cursor_id
      FROM ${server ? 'cached_chat_list_entries e JOIN cached_chats c ON c.owner_user_id=e.owner_user_id AND c.id=e.chat_id' : 'cached_chats c'}
      WHERE ${server ? 'e.owner_user_id=? AND e.query=?' : 'c.owner_user_id=?'} $namePredicate
        ${after == null ? '' : 'AND ($activity, $id) < (?, ?)'}
      ORDER BY order_micros DESC, cursor_id DESC LIMIT ?
    ''',
      variables: variables,
      readsFrom: {
        _database.cachedChats,
        if (server) _database.cachedChatListEntries,
      },
    );
  }

  Future<ChatListCacheSlice> _mapListSlice(
    List<QueryRow> rows,
    String query,
    int limit,
    bool server,
  ) async {
    await _prepareAvatarPaths();
    final visible = rows.take(limit).toList(growable: false);
    return ChatListCacheSlice(
      chats: visible
          .map((r) => _mapRow(_database.cachedChats.map(r.data)))
          .toList(growable: false),
      serverBacked: server,
      nextCursor: rows.length <= limit
          ? null
          : ChatListLocalCursor(
              query: query,
              activityMicros: visible.last.read<int>('order_micros'),
              chatId: visible.last.read<String>('id'),
              serverBacked: server,
            ),
    );
  }

  Future<ChatListCacheSlice> readListSlice({
    String query = '',
    int limit = 50,
    ChatListLocalCursor? after,
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final normalized = _listQuery(query);
    final snapshot = await _database.transaction(() async {
      final state = await readListState(query: normalized, ownerUserId: owner);
      if (after != null && state.hasRemotePage != after.serverBacked) {
        throw StateError('Local chat list coverage changed; reload the slice');
      }
      final rows = await _listSliceQuery(
        owner,
        normalized,
        limit,
        after,
        state.hasRemotePage,
      ).get();
      return (rows, state.hasRemotePage);
    });
    return _mapListSlice(snapshot.$1, normalized, limit, snapshot.$2);
  }

  Stream<ChatListCacheSlice> watchListSlice({
    String query = '',
    int limit = 50,
    String? ownerUserId,
  }) {
    final owner = ownerUserId ?? _userIdProvider();
    final normalized = _listQuery(query);
    return watchListState(query: normalized, ownerUserId: owner)
        .map((s) => s.hasRemotePage)
        .distinct()
        .switchMap(
          (server) => _listSliceQuery(owner, normalized, limit, null, server)
              .watch()
              .asyncMap(
                (rows) => _mapListSlice(rows, normalized, limit, server),
              ),
        )
        .distinct(
          (a, b) =>
              a.serverBacked == b.serverBacked &&
              a.nextCursor?.chatId == b.nextCursor?.chatId &&
              a.nextCursor?.activityMicros == b.nextCursor?.activityMicros &&
              a.chats.length == b.chats.length &&
              a.chats.indexed.every(
                (p) =>
                    _sameChat(p.$2, b.chats[p.$1]) &&
                    p.$2.cachedAvatarPath == b.chats[p.$1].cachedAvatarPath,
              ),
        );
  }
}
