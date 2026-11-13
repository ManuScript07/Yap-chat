import 'package:drift/drift.dart'
    show Variable, QueryInterceptor, QueryExecutor, ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

final _base = DateTime.utc(2026, 10, 26);
String _id(int n) => n.toString().padLeft(8, '0');
DateTime _time(int n) => _base.add(Duration(microseconds: n));
Chat _chat(int n, {String? name, String? text}) => Chat(
  id: _id(n),
  peerId: 'peer-${_id(n)}',
  userName: name ?? 'Пользователь $n',
  avatarStoragePath: 'peer-${_id(n)}/avatar.jpg',
  lastMessage: text ?? 'message $n',
  lastMessageTime: _base,
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
);
ChatListPage _page(
  List<int> ids, {
  String query = '',
  bool more = false,
  int? total = 0,
  List<ChatListPageItem>? items,
}) => ChatListPage(
  items:
      items ??
      [
        for (final n in ids)
          ChatListPageItem(
            chat: _chat(n, name: query.isEmpty ? null : '$query $n'),
            activityAt: _time(n),
          ),
      ],
  query: query,
  unreadTotal: total,
  nextCursor: !more
      ? null
      : ChatListPageCursor(
          activityAt: _time(ids.last),
          conversationId: _id(ids.last),
          query: query,
        ),
);

void main() {
  late AppDatabase db;
  late ChatsCacheDataSource cache;
  late _Media media;
  var owner = 'a';
  setUp(() {
    owner = 'a';
    db = AppDatabase.forTesting(NativeDatabase.memory());
    media = _Media(db);
    cache = ChatsCacheDataSource(
      database: db,
      userIdProvider: () => owner,
      mediaCache: media,
    );
  });
  tearDown(() => db.close());

  test(
    'delta in 10000 cached entries uses a full PK probe and identical replay does not write',
    () async {
      final trace = _DeltaTrace();
      final tracedDb = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(trace),
      );
      addTearDown(tracedDb.close);
      final traced = ChatsCacheDataSource(
        database: tracedDb,
        userIdProvider: () => 'a',
      );
      await traced.replaceAll([for (var n = 0; n < 10000; n++) _chat(n)]);
      await traced.applyListPage(
        await traced.beginListRefresh(),
        _page([9999], more: true),
      );
      await tracedDb.customStatement('''
      INSERT OR IGNORE INTO cached_chat_list_entries(owner_user_id,query,chat_id,activity_micros)
      SELECT owner_user_id,'',id,${_base.microsecondsSinceEpoch}+CAST(id AS INTEGER) FROM cached_chats WHERE owner_user_id='a'
    ''');
      trace.enabled = true;
      final changed = _chat(5000, text: 'changed');
      final activity = {_id(5000): _time(20000)};
      await traced.applySummaryBatch(
        {_id(5000)},
        [changed],
        activityByChatId: activity,
      );
      expect(trace.maximumRows, 1);
      final plan = await tracedDb.executor.runSelect(
        'EXPLAIN QUERY PLAN ${trace.sql}',
        trace.args,
      );
      expect(
        plan.toString(),
        contains('owner_user_id=? AND query=? AND chat_id=?'),
      );
      expect(trace.writes, 2);
      trace.writes = 0;
      await traced.applySummaryBatch(
        {_id(5000)},
        [changed],
        activityByChatId: activity,
      );
      expect(trace.writes, 0);
    },
  );

  test(
    'delta adds/moves an off-page chat without changing coverage or cursor',
    () async {
      final request = await cache.beginListRefresh();
      await cache.applyListPage(request, _page([30, 20], more: true));
      final before = await cache.readListState();
      await cache.applySummaryBatch(
        {_id(10)},
        [_chat(10)],
        activityByChatId: {_id(10): _time(40)},
      );
      expect((await cache.readListSlice()).chats.map((c) => c.id), [
        _id(10),
        _id(30),
        _id(20),
      ]);
      var after = await cache.readListState();
      expect(after.revision, before.revision);
      expect(after.nextCursor?.activityAt, before.nextCursor?.activityAt);
      expect(after.nextCursor?.conversationId, _id(20));
      final continuation = (await cache.nextListRequest())!;
      // An older in-flight page must preserve the ID whose delta is newer.
      await cache.applyListPage(
        continuation,
        _page([10, 0]),
        protectedIds: {_id(10)},
      );
      expect((await cache.readListSlice()).chats.map((c) => c.id), [
        _id(10),
        _id(30),
        _id(20),
        _id(0),
      ]);
      after = await cache.readListState();
      expect(after.hasMore, false);
    },
  );

  test(
    'deleting the latest message can move a chat backwards without advancing the cursor',
    () async {
      final request = await cache.beginListRefresh();
      await cache.applyListPage(request, _page([30, 20, 10], more: true));
      await cache.applySummaryBatch(
        {_id(30)},
        [_chat(30, text: 'previous message')],
        activityByChatId: {_id(30): _time(5)},
      );
      expect((await cache.readListSlice()).chats.map((c) => c.id), [
        _id(20),
        _id(10),
        _id(30),
      ]);
      expect((await cache.nextListRequest())?.after?.conversationId, _id(10));
    },
  );

  test(
    'delta updates membership of existing prefix searches, including a completed empty search',
    () async {
      for (final query in ['', 'ал', 'бор']) {
        final request = await cache.beginListRefresh(query: query);
        await cache.applyListPage(request, _page([], query: query));
      }
      await cache.applySummaryBatch(
        {_id(1)},
        [_chat(1, name: 'Алёна')],
        activityByChatId: {_id(1): _time(1)},
      );
      expect((await cache.readListSlice(query: 'ал')).chats.single.id, _id(1));
      await cache.applySummaryBatch(
        {_id(1)},
        [_chat(1, name: 'Борис ')],
        activityByChatId: {_id(1): _time(2)},
      );
      expect((await cache.readListSlice(query: 'ал')).chats, isEmpty);
      expect((await cache.readListSlice(query: 'бор')).chats.single.id, _id(1));
      expect((await cache.readListSlice()).chats.single.id, _id(1));
      expect((await cache.readListState(query: 'бор')).hasMore, false);
      await cache.applySummaryBatch(
        {_id(1)},
        [_chat(1, name: ' Борис')],
        activityByChatId: {_id(1): _time(3)},
      );
      expect((await cache.readListSlice(query: 'бор')).chats, isEmpty);
    },
  );

  test(
    'delta without confirmed page coverage does not invent coverage or discard legacy cache',
    () async {
      await cache.replaceAll([_chat(1), _chat(2)]);
      final failedRequest = await cache.beginListRefresh();
      await cache.applySummaryBatch(
        {_id(1)},
        [_chat(1, text: 'new')],
        activityByChatId: {_id(1): _time(9)},
      );
      expect(await db.select(db.cachedChatListEntries).get(), isEmpty);
      expect((await cache.readListState()).revision, failedRequest.revision);
      expect((await cache.readListState()).hasRemotePage, false);
      expect((await cache.readListSlice()).chats, hasLength(2));
    },
  );

  test(
    'delta is owner scoped and malformed positions fail before metadata or membership changes',
    () async {
      for (final user in ['a', 'b']) {
        final request = await cache.beginListRefresh(ownerUserId: user);
        await cache.applyListPage(request, _page([2, 1]));
      }
      await cache.applySummaryBatch(
        {_id(1)},
        [_chat(1, text: 'new')],
        activityByChatId: {_id(1): _time(5)},
      );
      expect(
        (await cache.readListSlice(ownerUserId: 'b')).chats.map((c) => c.id),
        [_id(2), _id(1)],
      );
      final previous = (await cache.readListSlice()).chats;
      await expectLater(
        cache.applySummaryBatch(
          {_id(1)},
          [_chat(1, text: 'bad')],
          activityByChatId: {_id(9): _time(9)},
        ),
        throwsArgumentError,
      );
      expect((await cache.readListSlice()).chats, previous);
      expect((await cache.readById(_id(1)))?.lastMessage, 'new');
    },
  );

  test(
    'metadata and membership rollback together if the membership write fails',
    () async {
      final request = await cache.beginListRefresh();
      await cache.applyListPage(request, _page([2, 1]));
      await db.customStatement(
        '''CREATE TEMP TRIGGER reject_delta BEFORE UPDATE ON cached_chat_list_entries
      BEGIN SELECT RAISE(ABORT, 'forced test failure'); END''',
      );
      await expectLater(
        cache.applySummaryBatch(
          {_id(1)},
          [_chat(1, text: 'bad')],
          activityByChatId: {_id(1): _time(5)},
        ),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('forced test failure'),
          ),
        ),
      );
      expect((await cache.readById(_id(1)))?.lastMessage, 'message 1');
      expect((await cache.readListSlice()).chats.map((c) => c.id), [
        _id(2),
        _id(1),
      ]);
    },
  );

  test('new/failed refresh retains legacy cache and unknown badge', () async {
    await cache.replaceAll([_chat(1)]);
    final request = await cache.beginListRefresh();
    final state = await cache.readListState();
    expect(state.revision, request.revision);
    expect(state.hasRemotePage, false);
    expect(state.hasMore, true);
    expect(await cache.nextListRequest(), isNull);
    expect((await cache.readUnreadState()).total, isNull);
    final slice = await cache.readListSlice();
    expect(slice.chats.single.id, _id(1));
    expect(slice.serverBacked, false);
    expect(
      slice.chats.single.cachedAvatarPath,
      '/cached/peer-00000001/avatar.jpg',
    );
  });

  for (final count in [0, 1, 49, 50, 51, 999, 1000, 1001, 2005, 10000]) {
    test('legacy $count rows: slice and avatar mapping stay bounded', () async {
      await cache.replaceAll([for (var n = 0; n < count; n++) _chat(n)]);
      media.paths = 0;
      final slice = await cache.readListSlice();
      expect(slice.chats.length, count.clamp(0, 50));
      expect(slice.chats.map((c) => c.id), [
        for (var n = count - 1; n >= 0 && n >= count - 50; n--) _id(n),
      ]);
      expect(media.paths, count.clamp(0, 50));
      expect(slice.hasMoreCached, count > 50);
      if (count > 50) {
        final next = await cache.readListSlice(after: slice.nextCursor);
        expect(
          {
            ...slice.chats.map((c) => c.id),
            ...next.chats.map((c) => c.id),
          }.length,
          slice.chats.length + next.chats.length,
        );
        expect(next.chats.first.id, _id(count - 51));
      }
    });
  }

  test(
    'page is partial: retained metadata, history and other owners survive',
    () async {
      await cache.replaceAll([for (var n = 0; n < 120; n++) _chat(n)]);
      await cache.replaceAll([_chat(900)], ownerUserId: 'b');
      final messages = ChatCacheDataSource(
        database: db,
        userIdProvider: () => owner,
      );
      await messages.upsertMessages([
        ChatMessage(
          id: 'history',
          chatId: _id(0),
          senderId: 'peer',
          text: 'keep',
          timestamp: _base,
          isMine: false,
        ),
      ]);
      final request = await cache.beginListRefresh();
      expect(
        await cache.applyListPage(
          request,
          _page([119, 118], more: true, total: 120),
        ),
        true,
      );
      expect((await cache.read()).length, 120);
      expect((await cache.read(ownerUserId: 'b')).single.id, _id(900));
      expect(
        (await messages.readMessage('history', currentUserId: owner))?.text,
        'keep',
      );
      expect((await cache.readListSlice()).chats.map((c) => c.id), [
        _id(119),
        _id(118),
      ]);
      expect((await cache.readUnreadState()).total, 120);
    },
  );

  test(
    'all cached pages retain microseconds independently of pending preview',
    () async {
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([5, 4, 3], more: true, total: 9),
      );
      final next = (await cache.nextListRequest())!;
      expect(
        next.after!.activityAt.microsecondsSinceEpoch,
        _time(3).microsecondsSinceEpoch,
      );
      await cache.applyListPage(next, _page([2, 1, 0], total: 9));
      final first = await cache.readListSlice(limit: 2);
      expect(first.chats.map((c) => c.id), [_id(5), _id(4)]);
      expect(first.nextCursor!.activityMicros, _time(4).microsecondsSinceEpoch);
      final second = await cache.readListSlice(
        limit: 2,
        after: first.nextCursor,
      );
      expect(second.chats.map((c) => c.id), [_id(3), _id(2)]);
      await cache.updateLastMessage(
        ChatMessage(
          id: 'pending',
          chatId: _id(1),
          senderId: 'a',
          text: 'pending',
          timestamp: _base.add(const Duration(days: 1)),
          isMine: true,
          status: MessageStatus.sending,
        ),
      );
      final slice = await cache.readListSlice();
      expect(slice.chats.map((c) => c.id), [
        for (var n = 5; n >= 0; n--) _id(n),
      ]);
      expect(slice.chats[4].lastMessage, 'pending');
      expect((await cache.readListState()).hasMore, false);
      expect(await cache.nextListRequest(), isNull);
    },
  );

  test(
    'head refresh prunes only covered membership and keeps older pages offline',
    () async {
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([9, 8, 7], more: true),
      );
      await cache.applyListPage(
        (await cache.nextListRequest())!,
        _page([6, 5, 4], more: true),
      );
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([10, 9, 7], more: true),
      );
      expect(
        (await cache.readListSlice()).chats.map((c) => c.id),
        [10, 9, 7, 6, 5, 4].map(_id),
      );
      expect((await cache.readById(_id(8)))?.id, _id(8));
      expect((await cache.nextListRequest())!.after!.conversationId, _id(7));
      // A complete subsequent range may invalidate membership below its bound,
      // but never concludes that an absent chat's messages were deleted.
      await cache.applyListPage((await cache.nextListRequest())!, _page([6]));
      expect(
        (await cache.readListSlice()).chats.map((c) => c.id),
        [10, 9, 7, 6].map(_id),
      );
      expect(await cache.readById(_id(5)), isNotNull);
    },
  );

  test(
    'empty confirmed page differs from cache miss and preserves unknown total',
    () async {
      await cache.replaceAll([_chat(1)]);
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([], total: null),
      );
      final state = await cache.readListState();
      expect(state.hasRemotePage, true);
      expect(state.hasMore, false);
      expect((await cache.readListSlice()).chats, isEmpty);
      expect((await cache.read()).single.id, _id(1));
      expect((await cache.readUnreadState()).total, isNull);
    },
  );

  test(
    'empty page can advance over a server race without claiming end',
    () async {
      await cache.applyListPage(
        await cache.beginListRefresh(),
        ChatListPage(
          items: [],
          query: '',
          unreadTotal: 27,
          nextCursor: ChatListPageCursor(
            activityAt: _time(70),
            conversationId: _id(70),
          ),
        ),
      );
      expect((await cache.readListState()).hasMore, true);
      expect((await cache.nextListRequest())!.after!.conversationId, _id(70));
      expect((await cache.readUnreadState()).total, 27);
    },
  );

  test(
    'query CAS rejects stale heads, duplicate commits and stale next pages',
    () async {
      final old = await cache.beginListRefresh();
      final fresh = await cache.beginListRefresh();
      expect(
        await cache.applyListPage(fresh, _page([9, 8], more: true, total: 11)),
        true,
      );
      expect(await cache.applyListPage(old, _page([99], total: 99)), false);
      expect(await cache.applyListPage(fresh, _page([99], total: 99)), false);
      final tail = (await cache.nextListRequest())!;
      await cache.beginListRefresh();
      expect(await cache.applyListPage(tail, _page([7], total: 99)), false);
      expect(
        (await cache.readListSlice()).chats.map((c) => c.id),
        [9, 8].map(_id),
      );
      expect((await cache.readUnreadState()).total, 11);
      expect(await cache.readById(_id(99)), isNull);
    },
  );

  test(
    'badge invalidation preserves offline value and rejects a late total',
    () async {
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([9], total: 35),
      );
      final late = await cache.beginListRefresh(query: 'друг');
      await cache.invalidateUnreadState();
      expect((await cache.readUnreadState()).total, 35);
      expect(
        await cache.applyListPage(late, _page([8], query: 'друг', total: 3)),
        true,
      );
      expect((await cache.readUnreadState()).total, 35);
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([9], total: 27),
      );
      expect((await cache.readUnreadState()).total, 27);
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([9], total: null),
      );
      expect((await cache.readUnreadState()).total, 27);
    },
  );

  test(
    'different queries cannot overwrite a newer accepted global total',
    () async {
      final head = await cache.beginListRefresh();
      final search = await cache.beginListRefresh(query: 'user');
      await cache.applyListPage(search, _page([1], query: 'user', total: 42));
      await cache.applyListPage(head, _page([2], total: 7));
      expect((await cache.readUnreadState()).total, 42);
      expect((await cache.readListSlice()).chats.single.id, _id(2));
    },
  );

  test(
    'head result cannot overwrite protected rows with newer local changes',
    () async {
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([9, 8, 7], more: true),
      );
      await cache.applySummaryBatch({_id(8)}, [_chat(8, text: 'newer')]);
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([10, 9, 7], more: true),
        protectedIds: {_id(8)},
      );
      expect(
        (await cache.readListSlice()).chats.map((c) => c.id),
        [10, 9, 8, 7].map(_id),
      );
      expect((await cache.readById(_id(8)))!.lastMessage, 'newer');
    },
  );

  test(
    'search metadata is separate, normalized and literal for wildcards',
    () async {
      await cache.replaceAll([
        _chat(1, name: 'АЛЕКСЕЙ'),
        _chat(2, name: 'александр'),
        _chat(3, name: 'Миша алекс'),
        _chat(4, name: '100%_Test'),
        _chat(5, name: '100xxTest'),
      ]);
      expect(
        (await cache.readListSlice(query: '  АлЕкС ')).chats.map((c) => c.id),
        [2, 1].map(_id),
      );
      expect(
        (await cache.readListSlice(query: '100%_')).chats.single.id,
        _id(4),
      );
      await cache.applyListPage(
        await cache.beginListRefresh(query: 'алекс'),
        _page([1], query: 'алекс'),
      );
      expect(
        (await cache.readListSlice(query: 'АЛЕКС')).chats.single.id,
        _id(1),
      );
      expect((await cache.readListSlice()).chats.length, 5);
    },
  );

  test(
    'query eviction is bounded and old requests cannot survive ABA recreation',
    () async {
      final old = await cache.beginListRefresh(query: 'q0');
      for (var i = 1; i <= 10; i++) {
        await cache.beginListRefresh(query: 'q$i');
      }
      expect((await db.select(db.cachedChatListStates).get()).length, 8);
      final fresh = await cache.beginListRefresh(query: 'q0');
      expect(await cache.applyListPage(old, _page([1], query: 'q0')), false);
      expect(await cache.applyListPage(fresh, _page([2], query: 'q0')), true);
      await cache.beginListRefresh();
      expect((await db.select(db.cachedChatListStates).get()).length, 9);
    },
  );

  test(
    'requests capture owner and cached totals never cross account boundaries',
    () async {
      final request = await cache.beginListRefresh();
      owner = 'b';
      await cache.applyListPage(request, _page([1], total: 99));
      expect((await cache.readListSlice()).chats, isEmpty);
      expect((await cache.readUnreadState()).total, isNull);
      expect(
        (await cache.readListSlice(ownerUserId: 'a')).chats.single.id,
        _id(1),
      );
      expect((await cache.readUnreadState(ownerUserId: 'a')).total, 99);
    },
  );

  test(
    'confirmed removal clears query membership for every search only for that owner',
    () async {
      await cache.applyListPage(await cache.beginListRefresh(), _page([1]));
      await cache.applyListPage(
        await cache.beginListRefresh(query: 'польз'),
        _page([1], query: 'польз'),
      );
      await cache.applyListPage(
        await cache.beginListRefresh(ownerUserId: 'b'),
        _page([1]),
      );
      await cache.applySummaryBatch({_id(1)}, []);
      expect((await cache.readListSlice()).chats, isEmpty);
      expect((await cache.readListSlice(query: 'польз')).chats, isEmpty);
      expect(
        (await cache.readListSlice(ownerUserId: 'b')).chats.single.id,
        _id(1),
      );
      expect((await db.select(db.cachedChatListEntries).get()).length, 1);
    },
  );

  test(
    'slice stream switches coverage, keeps cached avatars and ignores equal data',
    () async {
      await cache.replaceAll([_chat(1)]);
      final values = <ChatListCacheSlice>[];
      final sub = cache.watchListSlice().listen(values.add);
      addTearDown(sub.cancel);
      await _until(() => values.length == 1);
      expect(values.single.chats.single.cachedAvatarPath, isNotNull);
      await cache.applyListPage(await cache.beginListRefresh(), _page([1]));
      await _until(() => values.length == 2);
      expect(values.last.serverBacked, true);
      await cache.applyListPage(await cache.beginListRefresh(), _page([1]));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(values.length, 2);
      await cache.applySummaryBatch({_id(1)}, [_chat(1, text: 'changed')]);
      await _until(() => values.length == 3);
      expect(values.last.chats.single.lastMessage, 'changed');
    },
  );

  test('malformed pages and local limits fail before partial writes', () async {
    final request = await cache.beginListRefresh();
    for (final page in [
      _page([1, 2]),
      _page([1, 1]),
      _page([1], query: 'other'),
      _page([1], total: -1),
      _page(List.generate(51, (i) => 100 - i)),
    ]) {
      await expectLater(
        cache.applyListPage(request, page),
        throwsArgumentError,
      );
    }
    expect(await cache.read(), isEmpty);
    expect((await cache.readUnreadState()).total, isNull);
    await expectLater(cache.readListSlice(limit: 0), throwsArgumentError);
    await expectLater(cache.readListSlice(limit: 201), throwsArgumentError);
    await expectLater(
      cache.beginListRefresh(query: 'a' * 101),
      throwsArgumentError,
    );
  });

  test(
    'transaction failure cannot leave half a page or altered coverage/badge',
    () async {
      await db.customStatement(
        "CREATE TRIGGER fail_page BEFORE INSERT ON cached_chats WHEN NEW.id='${_id(1)}' BEGIN SELECT RAISE(ABORT,'synthetic disk failure');END",
      );
      final request = await cache.beginListRefresh();
      await expectLater(
        cache.applyListPage(request, _page([2, 1], more: true, total: 42)),
        throwsA(
          predicate((e) => e.toString().contains('synthetic disk failure')),
        ),
      );
      expect(await cache.read(), isEmpty);
      expect(await db.select(db.cachedChatListEntries).get(), isEmpty);
      expect((await cache.readListState()).revision, request.revision);
      expect((await cache.readListState()).hasRemotePage, false);
      expect((await cache.readUnreadState()).total, isNull);
    },
  );

  test(
    'old local cursor after coverage change is rejected, not a false empty end',
    () async {
      await cache.replaceAll([_chat(3), _chat(2), _chat(1)]);
      final legacy = await cache.readListSlice(limit: 1);
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([3, 2], more: true),
      );
      await expectLater(
        cache.readListSlice(after: legacy.nextCursor),
        throwsStateError,
      );
      expect((await cache.readListState()).hasMore, true);
    },
  );

  test(
    'addressed total has the same CAS and unknown-zero distinction as a page',
    () async {
      expect((await cache.readUnreadState()).total, isNull);
      expect(await cache.applyUnreadTotal(0, expectedRevision: 0), true);
      expect((await cache.readUnreadState()).total, 0);
      expect(await cache.applyUnreadTotal(99, expectedRevision: 0), false);
      await expectLater(
        cache.applyUnreadTotal(-1, expectedRevision: 1),
        throwsArgumentError,
      );
      expect(await cache.applyUnreadTotal(42, expectedRevision: 1), true);
      expect((await cache.readUnreadState()).total, 42);
    },
  );

  test(
    'actual slice SQL keeps both branches indexed and returns only requested rows',
    () async {
      final trace = _SliceTrace();
      final tracedDb = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(trace),
      );
      try {
        final tracedCache = ChatsCacheDataSource(
          database: tracedDb,
          userIdProvider: () => 'a',
        );
        await tracedCache.replaceAll([
          for (var n = 0; n < 10000; n++) _chat(n),
        ]);
        await tracedCache.readListSlice();
        expect(trace.rows, 51);
        final legacyPlan = await tracedDb.executor.runSelect(
          'EXPLAIN QUERY PLAN ${trace.sql}',
          trace.args,
        );
        final legacyText = legacyPlan.toString();
        expect(legacyText, contains('cached_chats_owner_list_fallback_idx'));
        expect(legacyText, isNot(contains('TEMP B-TREE')));
        await tracedCache.applyListPage(
          await tracedCache.beginListRefresh(),
          _page([9999, 9998], more: true),
        );
        await tracedCache.readListSlice(limit: 1);
        expect(trace.rows, 2);
        final coveredPlan = await tracedDb.executor.runSelect(
          'EXPLAIN QUERY PLAN ${trace.sql}',
          trace.args,
        );
        expect(coveredPlan.toString(), isNot(contains('TEMP B-TREE')));
        expect(
          coveredPlan.toString(),
          contains('cached_chat_list_entries_order_idx'),
        );
      } finally {
        await tracedDb.close();
      }
    },
  );

  test(
    'unicode prefix bounds handle supplementary and surrogate-edge names',
    () async {
      await cache.replaceAll([
        _chat(1, name: '😀 First'),
        _chat(2, name: '😁 Next'),
        _chat(3, name: '\uD7FF edge'),
        _chat(4, name: '\uE000 next'),
        _chat(5, name: '\u{10ffff} last'),
      ]);
      expect((await cache.readListSlice(query: '😀')).chats.single.id, _id(1));
      expect(
        (await cache.readListSlice(query: '\uD7FF')).chats.single.id,
        _id(3),
      );
      expect(
        (await cache.readListSlice(query: '\u{10ffff}')).chats.single.id,
        _id(5),
      );
    },
  );

  test('logout clears all page/search/badge data only for its owner', () async {
    await cache.applyListPage(
      await cache.beginListRefresh(),
      _page([1], total: 5),
    );
    await cache.applyListPage(
      await cache.beginListRefresh(query: 'user'),
      _page([1], query: 'user', total: 5),
    );
    await cache.applyListPage(
      await cache.beginListRefresh(ownerUserId: 'b'),
      _page([2], total: 7),
    );
    final old = await cache.beginListRefresh();
    await media.clearUser('a');
    expect((await cache.readListSlice()).chats, isEmpty);
    expect((await cache.readListState()).revision, isNull);
    expect((await cache.readUnreadState()).total, isNull);
    expect(await cache.applyListPage(old, _page([3], total: 99)), false);
    expect(
      (await cache.readListSlice(ownerUserId: 'b')).chats.single.id,
      _id(2),
    );
    expect((await cache.readUnreadState(ownerUserId: 'b')).total, 7);
    expect(
      (await db.select(db.cachedChatListEntries).get()).single.ownerUserId,
      'b',
    );
    expect(
      (await db.select(db.cachedChatListStates).get()).single.ownerUserId,
      'b',
    );
    expect(
      (await db.select(db.cachedChatUnreadTotals).get()).single.ownerUserId,
      'b',
    );
  });

  test(
    'bounded SQL uses exact-key order indexes rather than Dart history scans',
    () async {
      await cache.replaceAll([for (var n = 0; n < 1000; n++) _chat(n)]);
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT id FROM cached_chats WHERE owner_user_id=? ORDER BY last_message_time*1000000 DESC,id DESC LIMIT 51',
            variables: [Variable<String>('a')],
          )
          .get();
      expect(
        plan.map((r) => r.data.toString()).join(),
        contains('cached_chats_owner_list_fallback_idx'),
      );
      await cache.applyListPage(
        await cache.beginListRefresh(),
        _page([999, 998], more: true),
      );
      final covered = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT chat_id FROM cached_chat_list_entries WHERE owner_user_id=? AND query=? AND (activity_micros,chat_id)<(?,?) ORDER BY activity_micros DESC,chat_id DESC LIMIT 51',
            variables: [
              Variable<String>('a'),
              Variable<String>(''),
              Variable<int>(_time(999).microsecondsSinceEpoch),
              Variable<String>(_id(999)),
            ],
          )
          .get();
      expect(
        covered.map((r) => r.data.toString()).join(),
        contains('cached_chat_list_entries_order_idx'),
      );
    },
  );
}

Future<void> _until(bool Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!check()) {
    if (DateTime.now().isAfter(end)) fail('cache stream did not update');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Media extends MediaCacheService {
  _Media(AppDatabase db) : super(database: db);
  int paths = 0;
  @override
  Future<void> prepareLocalPaths() async {}
  @override
  String? localStorageFilePath({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    String? mimeType,
  }) {
    paths++;
    return '/cached/$storagePath';
  }
}

class _SliceTrace extends QueryInterceptor {
  String sql = '';
  List<Object?> args = [];
  int rows = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> arguments,
  ) async {
    final result = await executor.runSelect(statement, arguments);
    if (statement.contains('AS order_micros') &&
        !statement.startsWith('EXPLAIN')) {
      sql = statement;
      args = List.of(arguments);
      rows = result.length;
    }
    return result;
  }
}

class _DeltaTrace extends QueryInterceptor {
  bool enabled = false;
  String sql = '';
  List<Object?> args = [];
  int maximumRows = 0, writes = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> arguments,
  ) async {
    final rows = await executor.runSelect(statement, arguments);
    if (enabled &&
        statement.contains('SELECT e.chat_id, e.activity_micros') &&
        !statement.startsWith('EXPLAIN')) {
      sql = statement;
      args = List.of(arguments);
      if (rows.length > maximumRows) maximumRows = rows.length;
    }
    return rows;
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> arguments,
  ) {
    if (enabled) writes++;
    return executor.runInsert(statement, arguments);
  }
}
