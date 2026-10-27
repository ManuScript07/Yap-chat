part of 'chats_cache_data_source.dart';

/// The available local list is independent of remote page coverage. In
/// particular, a fresh server head must never hide retained offline metadata.
extension ChatsAvailableCache on ChatsCacheDataSource {
  Future<List<ChatListLocalItem>> readAvailableItems(
    Set<String> ids, {
    String? ownerUserId,
  }) async {
    final rows = await _readRowsForAction(ids, ownerUserId: ownerUserId);
    await _prepareAvatarPaths();
    return rows
        .map(
          (r) => ChatListLocalItem(
            _mapRow(r),
            r.listOrderMicros ?? r.lastMessageTime.microsecondsSinceEpoch,
          ),
        )
        .toList(growable: false);
  }

  Selectable<QueryRow> _availableQuery(
    String owner,
    String query,
    int limit,
    ChatListLocalCursor? after,
  ) {
    if (limit < 1 ||
        limit > ChatsListCache.maximumSliceSize ||
        after != null && after.query != query) {
      throw ArgumentError('Invalid available chat slice');
    }
    final variables = <Variable>[Variable<String>(owner)];
    var prefix = '';
    if (query.isNotEmpty) {
      // Literal prefix, including % and _. Dart normalization also covers RU.
      final pattern = query
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      prefix = " AND c.peer_display_name_search LIKE ? ESCAPE '\\'";
      variables.add(Variable<String>('$pattern%'));
    }
    const order = 'COALESCE(c.list_order_micros,c.last_message_time * 1000000)';
    if (after != null) {
      variables.addAll([
        Variable<int>(after.activityMicros),
        Variable<int>(after.activityMicros),
        Variable<String>(after.chatId),
      ]);
    }
    variables.add(Variable<int>(limit + 1));
    return _database.customSelect(
      '''
      SELECT c.*, $order AS order_micros FROM cached_chats c
      WHERE c.owner_user_id=? $prefix
        ${after == null ? '' : 'AND $order<=? AND ($order,c.id)<(?,?)'}
      ORDER BY $order DESC,c.id DESC LIMIT ?
    ''',
      variables: variables,
      readsFrom: {_database.cachedChats},
    );
  }

  Future<ChatListCacheSlice> _availableSlice(
    List<QueryRow> rows,
    String query,
    int limit,
  ) async {
    await _prepareAvatarPaths();
    final visible = rows.take(limit).toList(growable: false);
    return ChatListCacheSlice(
      chats: visible
          .map((r) => _mapRow(_database.cachedChats.map(r.data)))
          .toList(growable: false),
      orderByChatId: Map.unmodifiable({
        for (final r in visible)
          r.read<String>('id'): r.read<int>('order_micros'),
      }),
      serverBacked: false,
      nextCursor: rows.length <= limit
          ? null
          : ChatListLocalCursor(
              query: query,
              activityMicros: visible.last.read<int>('order_micros'),
              chatId: visible.last.read<String>('id'),
              serverBacked: false,
            ),
    );
  }

  Future<ChatListCacheSlice> readAvailableSlice({
    String query = '',
    int limit = 50,
    ChatListLocalCursor? after,
    String? ownerUserId,
  }) async {
    final normalized = _listQuery(query);
    return _availableSlice(
      await _availableQuery(
        ownerUserId ?? _userIdProvider(),
        normalized,
        limit,
        after,
      ).get(),
      normalized,
      limit,
    );
  }

  Stream<ChatListCacheSlice> watchAvailableSlice({
    String query = '',
    int limit = 50,
    ChatListLocalCursor? after,
    String? ownerUserId,
  }) {
    final normalized = _listQuery(query);
    return _availableQuery(
          ownerUserId ?? _userIdProvider(),
          normalized,
          limit,
          after,
        )
        .watch()
        .asyncMap((rows) => _availableSlice(rows, normalized, limit))
        .distinct(
          (a, b) =>
              a.nextCursor?.chatId == b.nextCursor?.chatId &&
              a.chats.length == b.chats.length &&
              a.chats.indexed.every(
                (p) =>
                    p.$2 == b.chats[p.$1] &&
                    a.orderByChatId[p.$2.id] == b.orderByChatId[p.$2.id],
              ),
        );
  }

  Stream<List<ChatListLocalItem>> watchAvailableIds(
    Set<String> ids, {
    String? ownerUserId,
  }) {
    if (ids.length > 150) throw ArgumentError('Too many observed chats');
    if (ids.isEmpty) return Stream.value(const []);
    final owner = ownerUserId ?? _userIdProvider();
    return _database
        .customSelect(
          '''
      WITH requested(id) AS (VALUES ${List.filled(ids.length, '(?)').join(',')})
      SELECT c.* FROM requested r CROSS JOIN cached_chats c
      WHERE c.owner_user_id=? AND c.id=r.id
    ''',
          variables: [
            ...ids.map(Variable<String>.new),
            Variable<String>(owner),
          ],
          readsFrom: {_database.cachedChats},
        )
        .watch()
        .asyncMap((rows) async {
          await _prepareAvatarPaths();
          return rows
              .map((r) {
                final c = _database.cachedChats.map(r.data);
                return ChatListLocalItem(
                  _mapRow(c),
                  c.listOrderMicros ?? c.lastMessageTime.microsecondsSinceEpoch,
                );
              })
              .toList(growable: false);
        });
  }
}
