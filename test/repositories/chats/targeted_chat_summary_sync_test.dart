import 'dart:async';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  test(
    'missing page API falls back once and offline search remains usable',
    () async {
      final h = await _Harness.create(51, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      h.remote.nextPageError = const PostgrestException(
        message: 'missing get_chat_list_page',
        code: 'PGRST202',
      );
      await h.repository.getChats();
      final pages = h.remote.pageRequests.length;
      await h.repository.loadMoreChatList();
      await until(() => views.last.chats.length == 51);
      await h.repository.setChatListQuery('peer 0');
      await until(() => views.last.query == 'peer 0' && views.last.ready);
      expect(views.last.chats.single.id, '0');
      expect(views.last.hasMoreRemote, false);
      expect(views.last.error, null);
      expect(h.remote.pageRequests.length, pages);
      expect(h.remote.fullCalls, 1);
    },
  );
  test(
    'offscreen retained metadata updates and search mismatches disappear immediately',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      await h.repository.loadMoreChatList();
      await until(() => views.last.chats.length == 100);
      final retained = views.last.chats.last.id;
      final index = int.parse(retained);
      h.remote.chats[index] = h.remote.chats[index].copyWith(isMuted: true);
      h.remote.emit(retained, 'muted');
      await until(
        () => views.last.chats.any((c) => c.id == retained && c.isMuted),
      );
      final query = 'peer $retained';
      await h.repository.setChatListQuery(query);
      await until(
        () =>
            views.last.query == query &&
            !views.last.isRefreshing &&
            views.last.chats.any((c) => c.id == retained),
      );
      h.remote.chats[index] = h.remote.chats[index].copyWith(
        userName: 'renamed',
      );
      h.remote.emit(retained, 'profile_changed');
      await until(() => !views.last.chats.any((c) => c.id == retained));
      await h.repository.setChatListQuery('');
      await until(
        () =>
            views.last.query.isEmpty &&
            views.last.chats.any(
              (c) => c.id == retained && c.userName == 'renamed',
            ),
      );
      expect(h.remote.fullCalls, 0);
    },
  );
  test(
    'cancelled periodic search cannot fail the replacement main list',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      await h.repository.setChatListQuery('peer 9');
      await until(
        () =>
            views.last.query == 'peer 9' &&
            !views.last.isRefreshing &&
            views.last.ready,
      );
      final gate = h.remote.nextSearchGate = Completer<ChatListPage>();
      // Fresh searches are reused. A real catalog change must invalidate that
      // evidence before exercising cancellation of a periodic search refresh.
      h.remote.emit('0', 'profile_changed');
      final refresh = h.repository.getChats();
      await until(() => h.remote.pageRequests.length == 4);
      await h.repository.setChatListQuery('');
      gate.completeError(StateError('cancelled obsolete search'));
      await refresh;
      await until(() => views.last.query.isEmpty && views.last.ready);
      expect(views.last.error, null);
      await h.repository.loadMoreChatList();
      await until(() => views.last.chats.length >= 100);
      expect(views.last.error, null);
    },
  );
  test(
    'hiding a retained offscreen row removes it without viewport verification',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      await h.repository.loadMoreChatList();
      await until(() => views.last.chats.length == 100);
      final hidden = views.last.chats.last.id;
      h.remote.chats.removeWhere((c) => c.id == hidden);
      h.remote.emit(hidden, 'hidden');
      await until(() => !views.last.chats.any((c) => c.id == hidden));
      expect(await h.row(hidden), null);
      expect(h.remote.fullCalls, 0);
    },
  );
  test(
    'subscribed during a head read schedules one recovery follow-up',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      final gate = h.remote.nextPageGate = Completer<ChatListPage>();
      final refresh = h.repository.getChats();
      await until(() => h.remote.pageRequests.length == 2);
      h.remote.changes.add(
        const ConversationChange(conversationId: null, reason: 'subscribed'),
      );
      h.remote.unreadTotal = 123;
      gate.complete(
        ChatListPage(items: [], query: '', nextCursor: null, unreadTotal: 999),
      );
      await refresh;
      await until(() async => (await h.cache.readUnreadState()).total == 123);
      await until(() => !views.last.isRefreshing);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.remote.pageRequests, hasLength(3));
      expect(h.remote.fullCalls, 0);
    },
  );
  test(
    '500 changes during a head read stay bounded and lift far chats',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      final gate = h.remote.nextPageGate = Completer<ChatListPage>();
      final refresh = h.repository.getChats();
      await until(() => h.remote.pageRequests.length == 2);
      for (var i = 0; i < 500; i++) {
        h.remote.chats[i] = h.remote.chats[i].copyWith(
          lastMessageTime: DateTime.utc(2027).add(Duration(seconds: i)),
        );
        h.remote.emit('$i');
      }
      gate.complete(
        ChatListPage(items: [], query: '', nextCursor: null, unreadTotal: 1000),
      );
      await refresh;
      await until(() => views.last.chats.any((c) => int.parse(c.id) < 500));
      expect(h.remote.batches.every((ids) => ids.length <= 50), true);
      expect(h.remote.fullCalls, 0);
      expect(h.remote.pageRequests, hasLength(2));
      expect(views.last.error, null);
    },
  );
  for (final count in [0, 1, 49, 50, 51, 1000, 2005]) {
    test('paged cold start $count reads one head only', () async {
      final h = await _Harness.create(count, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      expect(views.last.chats, hasLength(count.clamp(0, 50)));
      expect(h.remote.pageRequests, hasLength(1));
      expect(h.remote.fullCalls, 0);
      expect((await h.cache.readUnreadState()).total, count);
      expect(h.remote.watchCalls, 1);
      expect(h.messageRemote.fetchCalls, 0);
    });
  }
  test(
    'all 2005 cached chats remain accessible offline and searchable beyond the head',
    () async {
      final h = await _Harness.create(2005, paged: true);
      addTearDown(h.dispose);
      await h.cache.applySummaryBatch(
        h.remote.chats.map((c) => c.id).toSet(),
        h.remote.chats,
      );
      await h.repository.pauseRealtime();
      final views = await _watchList(h);
      for (var i = 0; i < 43 && views.last.chats.length < 2005; i++) {
        await h.repository.loadMoreChatList();
      }
      await until(() => views.last.chats.length == 2005);
      expect(
        views.last.chats.map((c) => c.id).toSet(),
        h.remote.chats.map((c) => c.id).toSet(),
      );
      await h.repository.setChatListQuery('PEER 1999');
      await until(
        () =>
            views.last.query == 'peer 1999' &&
            views.last.ready &&
            views.last.chats.length == 1,
      );
      expect(views.last.chats.single.id, '1999');
      expect(h.remote.pageRequests, hasLength(1));
      expect(h.remote.fullCalls, 0);
      await h.repository.setChatListQuery('');
      await until(
        () => views.last.query.isEmpty && views.last.chats.length == 2005,
      );
    },
  );
  test(
    'a slow network page does not block browsing retained local pages',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      await h.cache.applySummaryBatch(
        h.remote.chats.map((c) => c.id).toSet(),
        h.remote.chats,
      );
      final views = await _watchList(h);
      final gate = h.remote.nextPageGate = Completer<ChatListPage>();
      await h.repository.loadMoreChatList();
      await until(() => h.remote.pageRequests.length == 2);
      for (var i = 0; i < 12; i++) {
        await h.repository.loadMoreChatList();
      }
      await until(() => views.last.chats.length >= 650);
      expect(h.remote.pageRequests, hasLength(2));
      gate.complete(
        ChatListPage(items: [], query: '', nextCursor: null, unreadTotal: 1000),
      );
      await until(() => !views.last.isLoadingRemote);
    },
  );
  test(
    'an update outside loaded pages immediately moves into the live head',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      expect(views.last.chats.any((c) => c.id == '0'), false);
      h.remote.chats[0] = chat('0').copyWith(
        lastMessageId: 'new',
        lastMessageTime: DateTime.utc(2027),
        unreadCount: 2,
      );
      h.remote.emit('0');
      await until(() => views.last.chats.first.id == '0');
      expect(h.remote.pageRequests, hasLength(1));
      expect(h.remote.batches, [
        {'0'},
      ]);
      expect(h.remote.fullCalls, 0);
    },
  );
  test(
    'local pending preview outside the visible head also moves to the top',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      await h.cache.applySummaryBatch({'0'}, [h.remote.chats[0]]);
      final views = await _watchList(h);
      await h.cache.updateLastMessage(
        ChatMessage(
          id: 'pending',
          chatId: '0',
          senderId: 'owner',
          isMine: true,
          text: 'pending',
          timestamp: DateTime.utc(2027),
          type: MessageType.text,
          status: MessageStatus.sending,
        ),
      );
      await until(() => views.last.chats.first.id == '0');
      expect(h.remote.pageRequests, hasLength(1));
    },
  );
  test(
    'failed append keeps the list and cursor; retry loads the next page',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      final before = (await h.cache.readListState()).nextCursor!.conversationId;
      h.remote.nextPageError = StateError('offline');
      await h.repository.loadMoreChatList();
      await until(() => views.last.error != null);
      expect(views.last.chats, hasLength(50));
      expect(
        (await h.cache.readListState()).nextCursor!.conversationId,
        before,
      );
      await h.repository.loadMoreChatList(retry: true);
      await until(
        () => views.last.chats.length == 100 && views.last.error == null,
      );
      expect(h.remote.pageRequests, hasLength(3));
    },
  );
  test(
    'periodic head refresh preserves an already advanced continuation',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      await h.repository.loadMoreChatList();
      await until(() => views.last.chats.length == 100);
      final cursor = (await h.cache.readListState()).nextCursor!;
      await h.repository.getChats();
      expect(
        (await h.cache.readListState()).nextCursor!.conversationId,
        cursor.conversationId,
      );
      expect(h.remote.fullCalls, 0);
    },
  );
  test(
    'viewport verification removes a hidden cached chat after a missed event',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      await h.cache.applySummaryBatch({'0'}, [h.remote.chats[0]]);
      await _watchList(h);
      h.remote.chats.removeWhere((c) => c.id == '0');
      h.repository.setChatListObservedIds({'0'}, {});
      await until(() async => await h.row('0') == null);
      expect(h.remote.fullCalls, 0);
      expect(h.remote.pageRequests, hasLength(1));
    },
  );
  test(
    'rapid A-B-A search cannot accept the old A page or reuse its generation',
    () async {
      final h = await _Harness.create(1000, paged: true);
      addTearDown(h.dispose);
      final views = await _watchList(h);
      final gate = h.remote.nextPageGate = Completer<ChatListPage>();
      await h.repository.setChatListQuery('peer 1');
      await until(() => h.remote.pageRequests.length == 2);
      await h.repository.setChatListQuery('peer 2');
      await h.repository.setChatListQuery('peer 1');
      gate.complete(
        ChatListPage(
          items: [
            ChatListPageItem(
              chat: chat('wrong'),
              activityAt: DateTime.utc(2027),
            ),
          ],
          query: 'peer 1',
          nextCursor: null,
          unreadTotal: 999,
        ),
      );
      await until(
        () =>
            views.last.query == 'peer 1' &&
            views.last.ready &&
            !views.last.isRefreshing &&
            views.last.chats.isNotEmpty,
      );
      expect(
        views.last.chats.every(
          (c) => c.userName.toLowerCase().startsWith('peer 1'),
        ),
        true,
      );
      expect(views.last.chats.any((c) => c.id == 'wrong'), false);
      expect((await h.cache.readUnreadState()).total, 1000);
    },
  );
  test(
    'newer persisted total rejects a late response from another snapshot',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => values.lastOrNull == 3);
      final gate = h.remote.nextUnreadGate = Completer<ChatUnreadState>();
      h.remote.emit('0');
      await until(() => h.remote.unreadSelections.length == 2);
      final state = await h.cache.readUnreadState();
      await h.cache.applyUnreadTotal(10, expectedRevision: state.revision);
      gate.complete(ChatUnreadState(chats: [chat('0')], unreadTotal: 999));
      await until(() => values.last == 10);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(values, isNot(contains(999)));
      expect((await h.cache.readUnreadState()).total, 10);
    },
  );

  test(
    'offline observer immediately retains a previously confirmed total',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      await h.cache.applyUnreadTotal(77, expectedRevision: 0);
      h.remote.nextUnreadError = StateError('offline');
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => h.remote.unreadSelections.isNotEmpty);
      expect(values, [77]);
      expect((await h.cache.readUnreadState()).total, 77);
    },
  );

  test(
    'remote hide refreshes total without requesting the hidden metadata',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => values.lastOrNull == 3);
      h.remote.chats.removeWhere((c) => c.id == '1');
      h.remote.emit('1', 'hidden');
      await until(() => values.last == 2);
      expect(await h.row('1'), isNull);
      expect(h.remote.unreadSelections.last, isEmpty);
      expect(h.remote.batches, isEmpty);
    },
  );

  test('coalesced reconciliation refreshes a missed off-list total', () async {
    final h = await _Harness.create(3);
    addTearDown(h.dispose);
    final values = <int?>[];
    final sub = h.repository.watchUnreadCount().listen(values.add);
    addTearDown(sub.cancel);
    await until(() => values.lastOrNull == 3);
    h.remote.unreadTotal = 99;
    await Future.wait([h.repository.getChats(), h.repository.getChats()]);
    await until(() => values.last == 99);
    expect(h.remote.fullCalls, 2);
    expect(h.remote.unreadSelections, [<String>{}, <String>{}]);
  });

  test('global count is shared and independent of cached list size', () async {
    final h = await _Harness.create(1000);
    addTearDown(h.dispose);
    h.remote.unreadTotal = 50001;
    final a = <int?>[], b = <int?>[];
    final first = h.repository.watchUnreadCount().listen(a.add);
    final second = h.repository.watchUnreadCount().listen(b.add);
    addTearDown(first.cancel);
    addTearDown(second.cancel);
    await until(() => a.lastOrNull == 50001 && b.lastOrNull == 50001);
    expect(await h.repository.watchUnreadCount().first, 50001);
    expect(h.remote.unreadSelections, [<String>{}]);
    expect(h.remote.watchCalls, 1);
    expect(h.remote.fullCalls, 1);
    h.remote.unreadTotal = 50002;
    h.remote.chats[0] = chat('0').copyWith(unreadCount: 2);
    h.remote.emit('0');
    await until(() => a.last == 50002 && b.last == 50002);
    expect((await h.row('0'))?.unreadCount, 2);
    expect(h.remote.unreadSelections.last, {'0'});
    expect(h.remote.batches, isEmpty);
    await first.cancel();
    expect(h.remote.changes.hasListener, true);
    expect((await h.cache.readUnreadState()).total, 50002);
  });

  test(
    'a newer event rejects the whole stale count, not unrelated metadata',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => values.lastOrNull == 3);
      final gate = h.remote.nextUnreadGate = Completer<ChatUnreadState>();
      h.remote.emit('0');
      await until(() => h.remote.unreadSelections.length == 2);
      h.remote.unreadTotal = 7;
      h.remote.emit('1');
      gate.complete(ChatUnreadState(chats: [chat('0')], unreadTotal: 999));
      await until(() => values.last == 7);
      expect(values, isNot(contains(999)));
      expect(h.remote.fullCalls, 1);
    },
  );

  test(
    'read in flight rejects old count and confirms after accepted write without realtime',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => values.lastOrNull == 3);
      final response = h.remote.nextUnreadGate = Completer<ChatUnreadState>();
      h.remote.emit('0');
      await until(() => h.remote.unreadSelections.length == 2);
      final writeGate = h.remote.mutationGate = Completer<void>();
      final write = h.repository.markAsRead({'0'});
      await until(() => h.remote.mutationCalls == 1);
      response.complete(ChatUnreadState(chats: [chat('0')], unreadTotal: 999));
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(values.last, 3);
      writeGate.complete();
      await write;
      await until(() => values.last == 2);
      expect(values, isNot(contains(999)));
      expect((await h.row('0'))?.unreadCount, 0);
    },
  );

  for (final action in ['mute', 'hide']) {
    test('$action confirms global count without a realtime event', () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => values.lastOrNull == 3);
      if (action == 'mute') {
        await h.repository.setMuted({'0'}, isMuted: true);
      } else {
        await h.repository.deleteChats({'0'});
      }
      await until(() => values.last == 2);
      expect(h.remote.unreadSelections.last, isEmpty);
      expect(h.remote.fullCalls, 1);
      if (action == 'mute') {
        final calls = h.remote.unreadSelections.length;
        await h.repository.setMuted({'0'}, isMuted: true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(h.remote.unreadSelections.length, calls);
      }
    });
  }

  test(
    'failed count preserves cached total and uses existing rate-limit backoff',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => values.lastOrNull == 3);
      h.remote.nextUnreadError = const PostgrestException(
        message: 'limit',
        code: 'PT429',
      );
      h.remote.emit('0');
      await until(() => h.remote.unreadSelections.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      expect(h.remote.unreadSelections, hasLength(2));
      expect(values.last, 3);
      expect((await h.cache.readUnreadState()).total, 3);
      expect(h.remote.fullCalls, 1);
    },
  );

  test(
    'missing count RPC retains legacy addressed updates without retry loop',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      h.remote.nextUnreadError = const PostgrestException(
        message: 'missing',
        code: 'PGRST202',
      );
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => h.remote.unreadSelections.length == 1);
      h.remote.chats[0] = chat('0').copyWith(unreadCount: 9);
      h.remote.emit('0');
      await until(() async => (await h.row('0'))?.unreadCount == 9);
      expect(h.remote.unreadSelections, hasLength(1));
      expect(values.last, isNull);
      expect(h.remote.batches, [
        {'0'},
      ]);
      expect(h.remote.fullCalls, 1);
    },
  );

  test(
    'pause discards old HTTP count and resume confirms a fresh snapshot',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <int?>[];
      final sub = h.repository.watchUnreadCount().listen(values.add);
      addTearDown(sub.cancel);
      await until(() => values.lastOrNull == 3);
      final gate = h.remote.nextUnreadGate = Completer<ChatUnreadState>();
      h.remote.emit('0');
      await until(() => h.remote.unreadSelections.length == 2);
      await h.repository.pauseRealtime();
      h.remote.unreadTotal = 8;
      await h.repository.resumeRealtime();
      gate.complete(ChatUnreadState(chats: [chat('0')], unreadTotal: 999));
      await until(() => values.last == 8);
      expect(values, isNot(contains(999)));
      expect(h.remote.watchCalls, 1);
    },
  );

  test('late account response cannot populate another account count', () async {
    final h = await _Harness.create(3);
    addTearDown(h.dispose);
    final gate = h.remote.nextUnreadGate = Completer<ChatUnreadState>();
    final values = <int?>[];
    final sub = h.repository.watchUnreadCount().listen(values.add);
    addTearDown(sub.cancel);
    await until(() => h.remote.unreadSelections.length == 1);
    h.account.setAuthenticatedUser('other');
    gate.complete(ChatUnreadState(chats: [], unreadTotal: 999));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await h.cache.readUnreadState(ownerUserId: 'other')).total, isNull);
    expect(values, isNot(contains(999)));
    expect(await h.repository.watchUnreadCount().first, isNull);
  });

  test(
    'peer observers share synchronization and ignore unrelated rows',
    () async {
      final h = await _Harness.create(1000);
      addTearDown(h.dispose);
      final a = <Chat?>[], b = <Chat?>[];
      final first = h.repository.watchChatByPeerId(' peer-17 ').listen(a.add);
      final second = h.repository.watchChatByPeerId('peer-17').listen(b.add);
      addTearDown(first.cancel);
      addTearDown(second.cancel);
      await until(() => a.isNotEmpty && b.isNotEmpty);
      expect(a.single?.id, '17');
      expect(b.single?.id, '17');
      expect(h.remote.watchCalls, 1);
      expect(h.remote.fullCalls, 1);
      await h.cache.applySummaryBatch(
        {'18'},
        [chat('18').copyWith(unreadCount: 99)],
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(a, hasLength(1));
      expect(b, hasLength(1));
      h.remote.chats[17] = chat('17').copyWith(unreadCount: 9);
      h.remote.emit('17');
      await until(() => a.last?.unreadCount == 9 && b.last?.unreadCount == 9);
      expect(h.remote.batches, [
        {'17'},
      ]);
      expect(h.remote.fullCalls, 1);
      expect(h.messageRemote.fetchCalls, 0);
      await first.cancel();
      await h.cache.applySummaryBatch(
        {'17'},
        [chat('17').copyWith(blockedByPeer: true)],
      );
      await until(() => b.last?.blockedByPeer == true);
      expect(a.last?.blockedByPeer, false);
      await second.cancel();
      expect(h.remote.changes.hasListener, true);
    },
  );
  test(
    'peer lease keeps recovery alive after the list closes and releases last',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <Chat?>[];
      final peer = h.repository.watchChatByPeerId('peer-1').listen(values.add);
      addTearDown(peer.cancel);
      await until(() => values.isNotEmpty);
      await h.subscription.cancel();
      expect(h.remote.changes.hasListener, true);
      h.remote.chats[1] = chat('1').copyWith(unreadCount: 9);
      h.remote.emit('1');
      await until(() => values.last?.unreadCount == 9);
      await h.repository.pauseRealtime();
      h.remote.chats[1] = chat('1').copyWith(unreadCount: 12);
      await h.repository.resumeRealtime();
      await until(() => values.last?.unreadCount == 12);
      await peer.cancel();
      await until(() => !h.remote.changes.hasListener);
    },
  );
  test(
    'stale peer stream cannot read a new account or start a new watcher',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final stale = h.repository.watchChatByPeerId('peer-1');
      h.account.setAuthenticatedUser('other');
      final calls = h.remote.watchCalls;
      expect(await stale.single, isNull);
      expect(h.remote.watchCalls, calls);
      await h.cache.applySummaryBatch(
        {'1'},
        [chat('1').copyWith(unreadCount: 42)],
        ownerUserId: 'other',
      );
      expect(
        (await h.cache.read(
          ownerUserId: 'owner',
        )).firstWhere((c) => c.id == '1').unreadCount,
        1,
      );
    },
  );
  test(
    'missing peer appears, deletion becomes null, late observers replay the row',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final values = <Chat?>[];
      final sub = h.repository.watchChatByPeerId('peer-new').listen(values.add);
      addTearDown(sub.cancel);
      await until(() => values.isNotEmpty);
      expect(values.single, isNull);
      final added = chat('new');
      h.remote.chats.add(added);
      h.remote.emit('new');
      await until(() => values.last?.id == 'new');
      expect(
        (await h.repository.watchChatByPeerId('peer-new').first)?.id,
        'new',
      );
      h.remote.chats.removeWhere((c) => c.id == 'new');
      h.remote.emit('new', 'hidden');
      await until(() => values.last == null);
      expect(h.remote.watchCalls, 1);
    },
  );
  test(
    'one event among 1000 chats reads/writes only the changed row',
    () async {
      final h = await _Harness.create(1000);
      addTearDown(h.dispose);
      final reads = h.messages.previewReads;
      h.trace.enabled = true;
      h.remote.chats[17] = h.remote.chats[17].copyWith(unreadCount: 9);
      h.remote.emit('17');
      await until(() async => (await h.row('17'))?.unreadCount == 9);
      expect(h.remote.fullCalls, 1);
      expect(h.remote.batches, [
        {'17'},
      ]);
      expect(h.messages.previewReads - reads, 1);
      expect(h.trace.inserts, 1);
      expect(await h.cache.read(), hasLength(1000));
      expect((await h.row('18'))?.unreadCount, 1);
      expect(h.messageRemote.fetchCalls, 0);
      expect(h.remote.maximumConcurrent, 1);
    },
  );

  test(
    'duplicates coalesce and 121 distinct IDs split into bounded batches',
    () async {
      final h = await _Harness.create(150);
      addTearDown(h.dispose);
      for (var i = 0; i < 121; i++) {
        h.remote.chats[i] = h.remote.chats[i].copyWith(unreadCount: 5);
        h.remote.emit('$i');
        h.remote.emit('$i');
      }
      await until(
        () async =>
            (await h.cache.read()).where((c) => c.unreadCount == 5).length ==
            121,
      );
      expect(h.remote.fullCalls, 1);
      expect(h.remote.batches, hasLength(3));
      expect(h.remote.batches.every((ids) => ids.length <= 50), true);
      expect(h.remote.batches.expand((ids) => ids).toList(), hasLength(121));
      expect(h.remote.maximumConcurrent, 1);
    },
  );

  test(
    'events arriving in flight discard stale metadata and retain dirty ID',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final gate = h.remote.nextBatchGate = Completer<List<Chat>>();
      h.remote.emit('0');
      await until(() => h.remote.batches.length == 1);
      h.remote.chats[0] = h.remote.chats[0].copyWith(unreadCount: 11);
      h.remote.emit('0');
      await Future<void>.delayed(Duration.zero);
      gate.complete([h.remote.chats[0].copyWith(unreadCount: 7)]);
      await until(() async => (await h.row('0'))?.unreadCount == 11);
      expect(h.observedUnread, isNot(contains(7)));
      expect(h.remote.batches, [
        {'0'},
        {'0'},
      ]);
    },
  );

  test('hidden event cannot be undone by an older batch response', () async {
    final h = await _Harness.create(3);
    addTearDown(h.dispose);
    final gate = h.remote.nextBatchGate = Completer<List<Chat>>();
    h.remote.emit('0');
    await until(() => h.remote.batches.length == 1);
    h.remote.emit('0', 'hidden');
    await Future<void>.delayed(Duration.zero);
    gate.complete([h.remote.chats[0].copyWith(unreadCount: 7)]);
    await until(() async => await h.row('0') == null);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(await h.row('0'), null);
    expect(h.observedUnread, isNot(contains(7)));
    expect(h.remote.batches, hasLength(1));
    expect(await h.cache.read(), hasLength(2));
  });

  test(
    'a full snapshot in flight also preserves a newer hidden event',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final gate = h.remote.nextFullGate = Completer<List<Chat>>();
      final refresh = h.repository.getChats();
      await until(() => h.remote.fullCalls == 2);
      h.remote.emit('0', 'hidden');
      await until(() async => await h.row('0') == null);
      gate.complete(List.of(h.remote.chats));
      await refresh;
      expect(await h.row('0'), null);
    },
  );

  test(
    'resume discards pre-pause HTTP and recovers a missed incoming chat',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final gate = h.remote.nextBatchGate = Completer<List<Chat>>();
      h.remote.emit('0');
      await until(() => h.remote.batches.length == 1);
      await h.repository.pauseRealtime();
      h.remote.chats[0] = h.remote.chats[0].copyWith(unreadCount: 13);
      h.remote.chats.add(chat('incoming'));
      await h.repository.resumeRealtime().timeout(const Duration(seconds: 2));
      // The old request is still hung: new-epoch events must also make progress.
      h.remote.chats[1] = h.remote.chats[1].copyWith(unreadCount: 17);
      h.remote.emit('1');
      await until(() async => (await h.row('1'))?.unreadCount == 17);
      gate.complete([h.remote.chats[0].copyWith(unreadCount: 7)]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await h.row('0'))?.unreadCount, 13);
      expect(await h.row('incoming'), isNotNull);
      expect(h.observedUnread, isNot(contains(7)));
      expect(h.remote.maximumConcurrent, 2);
    },
  );

  test(
    'account switch cannot commit an old batch into either account',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final gate = h.remote.nextBatchGate = Completer<List<Chat>>();
      h.remote.emit('0');
      await until(() => h.remote.batches.length == 1);
      h.account.setAuthenticatedUser('other');
      await h.repository.pauseRealtime();
      h.remote.chats = [chat('other-chat')];
      final resumed = h.repository.resumeRealtime();
      gate.complete([chat('0').copyWith(unreadCount: 7)]);
      await resumed;
      expect(
        (await h.cache.read(
          ownerUserId: 'owner',
        )).firstWhere((c) => c.id == '0').unreadCount,
        1,
      );
      expect((await h.cache.read(ownerUserId: 'other')).map((c) => c.id), [
        'other-chat',
      ]);
    },
  );

  test(
    'transient failure keeps cache and retries without another event',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      h.remote.nextBatchError = StateError('offline');
      h.remote.chats[0] = h.remote.chats[0].copyWith(unreadCount: 8);
      h.remote.emit('0');
      await until(() => h.remote.batches.length == 1);
      expect((await h.row('0'))?.unreadCount, 1);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(h.remote.batches, hasLength(1));
      await until(() async => (await h.row('0'))?.unreadCount == 8);
      expect(h.remote.fullCalls, 1);
      expect(h.remote.batches, hasLength(2));
    },
  );

  test(
    'quota rejection backs off instead of retrying on each new event',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      h.remote.nextBatchError = const PostgrestException(
        message: 'chat_summary_refresh_rate_limited',
        code: 'PT429',
      );
      h.remote.emit('0');
      await until(() => h.remote.batches.length == 1);
      for (var i = 0; i < 10; i++) {
        h.remote.emit('0');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(h.remote.batches, hasLength(1));
      expect(await h.cache.read(), hasLength(3));
      // Resume still performs authoritative recovery, independent of batch quota.
      h.remote.chats[0] = h.remote.chats[0].copyWith(unreadCount: 12);
      await h.repository.pauseRealtime();
      await h.repository.resumeRealtime();
      expect((await h.row('0'))?.unreadCount, 12);
    },
  );

  test(
    'missing migration falls back once, without breaking older backend',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      h.remote.nextBatchError = const PostgrestException(
        message: 'missing RPC',
        code: 'PGRST202',
      );
      h.remote.chats[0] = h.remote.chats[0].copyWith(unreadCount: 8);
      h.remote.emit('0');
      await until(() async => (await h.row('0'))?.unreadCount == 8);
      h.remote.chats[0] = h.remote.chats[0].copyWith(unreadCount: 9);
      h.remote.emit('0');
      await until(() async => (await h.row('0'))?.unreadCount == 9);
      expect(h.remote.batches, hasLength(1));
      expect(h.remote.fullCalls, 3);
    },
  );

  test(
    'new incoming chat is inserted and absent requested chat alone is removed',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      h.remote.chats.add(chat('incoming'));
      h.remote.chats.removeWhere((c) => c.id == '0');
      h.remote.emit('incoming');
      h.remote.emit('0');
      await until(
        () async => await h.row('incoming') != null && await h.row('0') == null,
      );
      expect((await h.cache.read()).map((c) => c.id).toSet(), {
        '1',
        '2',
        'incoming',
      });
      expect(h.remote.fullCalls, 1);
    },
  );

  test(
    'explicit full sync waits for a batch and actually fetches a full snapshot',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final gate = h.remote.nextBatchGate = Completer<List<Chat>>();
      h.remote.emit('0');
      await until(() => h.remote.batches.length == 1);
      h.remote.chats[1] = h.remote.chats[1].copyWith(unreadCount: 42);
      final full = h.repository.getChats();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(h.remote.fullCalls, 1);
      gate.complete([h.remote.chats[0]]);
      await full;
      expect((await h.row('1'))?.unreadCount, 42);
      expect(h.remote.fullCalls, 2);
      expect(h.remote.maximumConcurrent, 1);
    },
  );

  test('pending local preview survives an older server summary', () async {
    final h = await _Harness.create(3);
    addTearDown(h.dispose);
    final serverTime = DateTime.utc(2026, 10, 27, 0, 0, 0, 0, 123);
    h.remote.chats[0] = chat('0').copyWith(lastMessageTime: serverTime);
    final request = await h.cache.beginListRefresh();
    await h.cache.applyListPage(
      request,
      ChatListPage(
        items: [
          ChatListPageItem(chat: h.remote.chats[0], activityAt: serverTime),
        ],
        query: '',
        nextCursor: null,
      ),
    );
    await h.messages.upsertMessage(
      ChatMessage(
        id: 'pending',
        chatId: '0',
        isMine: true,
        senderId: 'owner',
        text: 'local text',
        timestamp: DateTime(2027),
        type: MessageType.text,
        status: MessageStatus.sending,
      ),
      isPending: true,
    );
    h.remote.emit('0');
    await until(() async => (await h.row('0'))?.lastMessageId == 'pending');
    expect((await h.row('0'))?.lastMessage, 'local text');
    final entry =
        (await h.database.select(h.database.cachedChatListEntries).get())
            .single;
    expect(entry.activityMicros, serverTime.microsecondsSinceEpoch);
    expect((await h.row('0'))?.lastMessageTime.year, 2027);
  });

  test('stopping the watcher cancels scheduled batch work', () async {
    final h = await _Harness.create(3);
    addTearDown(h.dispose);
    h.remote.emit('0');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await h.subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(h.remote.batches, isEmpty);
  });

  test(
    'logout during debounce cannot redirect dirty IDs to a new account',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      h.remote.emit('0');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      h.account.setAuthenticatedUser(null);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(h.remote.batches, isEmpty);
      expect(await h.cache.read(ownerUserId: 'owner'), hasLength(3));
    },
  );

  test(
    'invalid partial response cannot remove or overwrite unrelated chats',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final gate = h.remote.nextBatchGate = Completer<List<Chat>>();
      h.remote.emit('0');
      await until(() => h.remote.batches.length == 1);
      gate.complete([chat('unrequested')]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((await h.cache.read()).map((c) => c.id).toSet(), {'0', '1', '2'});
      await until(() => h.remote.batches.length == 2);
      expect(await h.row('0'), isNotNull);
    },
  );

  test(
    'partial cache commits are scoped and reject malformed batches atomically',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      await h.cache.replaceAll([chat('0')], ownerUserId: 'other');
      await expectLater(
        h.cache.applySummaryBatch({'0'}, [chat('1')]),
        throwsArgumentError,
      );
      await expectLater(
        h.cache.applySummaryBatch({'0'}, [chat('0'), chat('0')]),
        throwsArgumentError,
      );
      expect(await h.cache.read(), hasLength(3));
      await h.cache.applySummaryBatch(
        {'0', '1'},
        [chat('1').copyWith(unreadCount: 15)],
      );
      expect(await h.row('0'), null);
      expect((await h.row('1'))?.unreadCount, 15);
      expect(await h.row('2'), isNotNull);
      expect((await h.cache.read(ownerUserId: 'other')).single.id, '0');
    },
  );
  test(
    'large cache ID operations stay below legacy SQLite parameter limits',
    () async {
      final h = await _Harness.create(1001);
      addTearDown(h.dispose);
      h.trace.enabled = true;
      final ids = h.remote.chats.map((c) => c.id).toSet();
      expect(await h.cache.readForAction(ids), hasLength(1001));
      await h.cache.replaceAll(h.remote.chats.take(2).toList());
      expect(await h.cache.read(), hasLength(2));
      expect(h.trace.maximumReadDeleteArgs, lessThanOrEqualTo(401));
    },
  );
  test(
    'a pre-pause hidden handler cannot erase freshly restored metadata',
    () async {
      final h = await _Harness.create(3);
      addTearDown(h.dispose);
      final gate = h.messages.nextPendingRead =
          Completer<List<PendingChatDeletion>>();
      h.remote.emit('0', 'hidden');
      await until(() => h.messages.nextPendingRead == null);
      await h.repository.pauseRealtime();
      h.remote.chats[0] = h.remote.chats[0].copyWith(unreadCount: 21);
      await h.repository.resumeRealtime().timeout(const Duration(seconds: 2));
      gate.complete([]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((await h.row('0'))?.unreadCount, 21);
    },
  );
}

Future<void> until(FutureOr<bool> Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 7));
  while (!await check()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for summary synchronization');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<List<ChatListViewState>> _watchList(_Harness h) async {
  final values = <ChatListViewState>[];
  final sub = h.repository.watchChatList().listen(values.add);
  addTearDown(sub.cancel);
  await until(() => values.isNotEmpty && values.last.ready);
  return values;
}

Chat chat(String id) => Chat(
  id: id,
  peerId: 'peer-$id',
  userName: 'Peer $id',
  lastMessage: 'preview',
  lastMessageId: 'message-$id',
  lastMessageTime: DateTime(2026),
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
);

class _Harness {
  _Harness(
    this.database,
    this.account,
    this.media,
    this.cache,
    this.messages,
    this.messageRemote,
    this.remote,
    this.repository,
    this.trace,
  );
  final AppDatabase database;
  final AccountSessionController account;
  final MediaCacheService media;
  final ChatsCacheDataSource cache;
  final _Messages messages;
  final _MessageRemote messageRemote;
  final _Remote remote;
  final ChatsRepository repository;
  final _Trace trace;
  late final StreamSubscription<List<Chat>> subscription;
  final observedUnread = <int>[];
  static Future<_Harness> create(int count, {bool paged = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final trace = _Trace();
    final db = AppDatabase.forTesting(
      NativeDatabase.memory().interceptWith(trace),
    );
    final account = AccountSessionController(initialUserId: 'owner');
    final media = MediaCacheService(database: db);
    final talker = Talker(settings: TalkerSettings(enabled: false));
    final config = AppConfig(
      environment: AppEnvironment.prod,
      preferences: prefs,
      talker: talker,
      env: const {},
      database: db,
      accountSessionController: account,
    );
    final cache = ChatsCacheDataSource(
      database: db,
      userIdProvider: () => account.userId!,
    );
    final messages = _Messages(db, account);
    final mr = _MessageRemote();
    final remote = _Remote([for (var i = 0; i < count; i++) chat('$i')]);
    final sync = ConversationSyncService(
      cache: messages,
      remote: mr,
      hydrator: ChatMessageHydrator(
        config: config,
        remote: mr,
        mediaCache: media,
      ),
      chatsCache: cache,
      accountSessionController: account,
    );
    final repository = ChatsRepository(
      enableListPagination: paged,
      config: config,
      cache: cache,
      remote: remote,
      mediaCache: media,
      chatCache: messages,
      conversationSync: sync,
      accountSessionController: account,
    );
    final h = _Harness(
      db,
      account,
      media,
      cache,
      messages,
      mr,
      remote,
      repository,
      trace,
    );
    h.subscription = repository.watchChats().listen((chats) {
      for (final c in chats) {
        if (c.id == '0') h.observedUnread.add(c.unreadCount);
      }
    });
    await until(
      () async =>
          (await cache.read()).length == (paged ? count.clamp(0, 50) : count),
    );
    return h;
  }

  Future<Chat?> row(String id) async =>
      (await cache.readForAction({id})).firstOrNull;
  Future<void> dispose() async {
    await subscription.cancel();
    await repository.pauseRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await account.drainCommits();
    await remote.changes.close();
    media.dispose();
    await database.close();
  }
}

class _Remote extends ChatsRemoteDataSource {
  _Remote(this.chats)
    : super(
        client: SupabaseClient('http://localhost', 'test'),
        talker: Talker(),
      );
  List<Chat> chats;
  final pageRequests = <(String, ChatListPageCursor?)>[];
  Completer<ChatListPage>? nextPageGate;
  Completer<ChatListPage>? nextSearchGate;
  Object? nextPageError;
  @override
  Future<ChatListPage> fetchChatListPage({
    ChatListPageCursor? after,
    int pageSize = 50,
    String searchQuery = '',
  }) async {
    pageRequests.add((searchQuery, after));
    final gate =
        nextPageGate ?? (searchQuery.isNotEmpty ? nextSearchGate : null);
    nextPageGate = null;
    if (searchQuery.isNotEmpty) nextSearchGate = null;
    final error = nextPageError;
    nextPageError = null;
    if (error != null) throw error;
    if (gate != null) return gate.future;
    final rows =
        chats
            .where(
              (c) =>
                  c.userName.toLowerCase().startsWith(searchQuery) &&
                  (after == null ||
                      c.lastMessageTime.isBefore(after.activityAt) ||
                      c.lastMessageTime.isAtSameMomentAs(after.activityAt) &&
                          c.id.compareTo(after.conversationId) < 0),
            )
            .toList()
          ..sort((a, b) {
            final order = b.lastMessageTime.compareTo(a.lastMessageTime);
            return order == 0 ? b.id.compareTo(a.id) : order;
          });
    final selected = rows.take(pageSize).toList();
    return ChatListPage(
      items: selected
          .map(
            (c) => ChatListPageItem(
              chat: c,
              activityAt: c.lastMessageTime.toUtc(),
            ),
          )
          .toList(),
      query: searchQuery,
      nextCursor: rows.length <= pageSize
          ? null
          : ChatListPageCursor(
              activityAt: selected.last.lastMessageTime.toUtc(),
              conversationId: selected.last.id,
              query: searchQuery,
            ),
      unreadTotal:
          unreadTotal ??
          chats
              .where((c) => !c.isMuted)
              .fold<int>(0, (n, c) => n + c.unreadCount),
    );
  }

  final changes = StreamController<ConversationChange>.broadcast();
  int fullCalls = 0, active = 0, maximumConcurrent = 0, watchCalls = 0;
  final batches = <Set<String>>[];
  Completer<List<Chat>>? nextBatchGate, nextFullGate;
  Object? nextBatchError;
  int? unreadTotal;
  final unreadSelections = <Set<String>>[];
  Completer<ChatUnreadState>? nextUnreadGate;
  Object? nextUnreadError;
  Completer<void>? mutationGate;
  int mutationCalls = 0;

  @override
  Future<ChatUnreadState> fetchUnreadState({
    Set<String> conversationIds = const {},
  }) async {
    unreadSelections.add(Set.of(conversationIds));
    final gate = nextUnreadGate;
    nextUnreadGate = null;
    final error = nextUnreadError;
    nextUnreadError = null;
    if (error != null) throw error;
    return gate?.future ??
        ChatUnreadState(
          chats: chats.where((c) => conversationIds.contains(c.id)).toList(),
          unreadTotal:
              unreadTotal ??
              chats
                  .where((c) => !c.isMuted)
                  .fold(0, (total, c) => total + c.unreadCount),
        );
  }

  @override
  Future<void> markAsRead(Set<String> ids) async {
    mutationCalls++;
    await mutationGate?.future;
    chats = [
      for (final c in chats)
        ids.contains(c.id) ? c.copyWith(unreadCount: 0) : c,
    ];
  }

  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {
    mutationCalls++;
    await mutationGate?.future;
    chats = [
      for (final c in chats)
        ids.contains(c.id) ? c.copyWith(isMuted: isMuted) : c,
    ];
  }

  @override
  Future<void> hideChats(Set<String> ids, {required DateTime clearedAt}) async {
    mutationCalls++;
    await mutationGate?.future;
    chats = chats.where((c) => !ids.contains(c.id)).toList();
  }

  void emit(String id, [String reason = 'insert']) =>
      changes.add(ConversationChange(conversationId: id, reason: reason));
  @override
  Stream<ConversationChange> watchChanges() {
    watchCalls++;
    return changes.stream;
  }

  @override
  Future<void> pauseChanges() async {}
  @override
  Future<void> resumeChanges() async {}
  @override
  Future<List<Chat>> fetchChats() async {
    fullCalls++;
    final gate = nextFullGate;
    nextFullGate = null;
    return _fetch(gate, List.of(chats));
  }

  @override
  Future<List<Chat>> fetchChatsByIds(Set<String> ids) async {
    batches.add(Set.of(ids));
    final gate = nextBatchGate;
    nextBatchGate = null;
    final error = nextBatchError;
    nextBatchError = null;
    if (error != null) throw error;
    return _fetch(gate, chats.where((c) => ids.contains(c.id)).toList());
  }

  Future<List<Chat>> _fetch(
    Completer<List<Chat>>? gate,
    List<Chat> result,
  ) async {
    active++;
    if (active > maximumConcurrent) maximumConcurrent = active;
    try {
      return gate == null ? result : await gate.future;
    } finally {
      active--;
    }
  }
}

class _Messages extends ChatCacheDataSource {
  _Messages(AppDatabase db, AccountSessionController account)
    : super(database: db, userIdProvider: () => account.userId!);
  int previewReads = 0;
  Completer<List<PendingChatDeletion>>? nextPendingRead;
  @override
  Future<List<PendingChatDeletion>> readPendingChatDeletions({
    String? ownerUserId,
  }) {
    final gate = nextPendingRead;
    nextPendingRead = null;
    return gate?.future ??
        super.readPendingChatDeletions(ownerUserId: ownerUserId);
  }

  @override
  Future<ChatMessage?> readLatestMessage(
    String id, {
    required String currentUserId,
  }) {
    previewReads++;
    return super.readLatestMessage(id, currentUserId: currentUserId);
  }
}

class _MessageRemote extends ChatRemoteDataSource {
  _MessageRemote() : super(client: SupabaseClient('http://localhost', 'test'));
  int fetchCalls = 0;
  @override
  String get currentUserId => 'owner';
  @override
  Future<List<ChatMessage>> fetchMessages(
    String id, {
    DateTime? beforeTimestamp,
    String? beforeMessageId,
    int pageSize = 60,
  }) async {
    fetchCalls++;
    return const [];
  }
}

class _Trace extends QueryInterceptor {
  bool enabled = false;
  int inserts = 0;
  int maximumReadDeleteArgs = 0;
  void _record(List<Object?> args) {
    if (enabled && args.length > maximumReadDeleteArgs) {
      maximumReadDeleteArgs = args.length;
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String sql,
    List<Object?> args,
  ) {
    _record(args);
    return executor.runSelect(sql, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String sql,
    List<Object?> args,
  ) {
    _record(args);
    return executor.runDelete(sql, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String sql,
    List<Object?> args,
  ) {
    if (enabled && sql.contains('cached_chats')) inserts++;
    return executor.runInsert(sql, args);
  }
}
