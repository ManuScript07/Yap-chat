// Opt-in integration: two real SDK clients + Drift + 1000 local conversations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:uuid/uuid.dart';
// ignore: depend_on_referenced_packages
import 'package:web_socket_channel/io.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/repositories/realtime/realtime.dart';

const _enabled = bool.fromEnvironment('TARGETED_CHAT_LOCAL');
const _uuid = Uuid();
void main() {
  test(
    'paged production flow keeps 1005 offline chats live on two SDK clients',
    () async {
      final auth = await _env('supabase_auth_Yap_chat');
      final storage = await _env('supabase_storage_Yap_chat');
      final owner = _uuid.v4();
      final peers = [for (var i = 0; i < 1005; i++) _uuid.v4()];
      final chats = [for (var i = 0; i < 1005; i++) _uuid.v4()];
      final users = [owner, ...peers];
      final before = await _counts();
      final devices = <_Device>[];
      var stage = 'fixtures';
      try {
        await _sql(
          '''begin;
        insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
        ${users.map((id) => "('$id',false,false,'{}')").join(',')};
        insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at) values
        ${chats.indexed.map((p) => "('${p.$2}',least('$owner'::uuid,'${peers[p.$1]}'::uuid),greatest('$owner'::uuid,'${peers[p.$1]}'::uuid),'${peers[p.$1]}','2020-01-01'::timestamptz+${p.$1}*interval '1 second')").join(',')};
        insert into public.conversation_members(conversation_id,user_id) values
        ${chats.indexed.expand((p) => ["('${p.$2}','$owner')", "('${p.$2}','${peers[p.$1]}')"]).join(',')};commit;''',
        );
        final views = <List<ChatListViewState>>[];
        final totals = <List<int?>>[];
        for (var i = 0; i < 2; i++) {
          stage = 'device $i bootstrap';
          final d = await _Device.create(
            owner,
            storage['ANON_KEY']!,
            auth['GOTRUE_JWT_SECRET']!,
            paged: true,
          );
          devices.add(d);
          final v = <ChatListViewState>[];
          views.add(v);
          final u = <int?>[];
          totals.add(u);
          d.subscriptions.add(d.repository.watchChatList().listen(v.add));
          d.subscriptions.add(d.repository.watchUnreadCount().listen(u.add));
          await _until(
            () =>
                d.ready &&
                v.isNotEmpty &&
                v.last.ready &&
                v.last.chats.length == 50 &&
                u.lastOrNull == 0,
          );
          expect(d.remote.fullCalls, 0);
          expect(
            d.remote.pageCalls,
            inInclusiveRange(1, 2),
            reason: 'Socket readiness may follow the initial HTTP snapshot',
          );
          expect(d.client.getChannels(), hasLength(1));
          expect(d.connection.value, false);
        }
        stage = 'all remote pages';
        final a = devices[0], b = devices[1];
        final onlineWatch = Stopwatch()..start();
        for (var i = 0; i < 24 && views[0].last.chats.length < 1005; i++) {
          await a.repository.loadMoreChatList();
          await _until(
            () =>
                !views[0].last.isLoadingRemote && !views[0].last.isLoadingCache,
          );
        }
        await _until(() => views[0].last.chats.length == 1005);
        onlineWatch.stop();
        expect(views[0].last.chats.map((c) => c.id).toList(), chats.reversed);
        expect(views[0].last.hasMoreRemote, false);
        final aCache = ChatsCacheDataSource(
          database: a.database,
          userIdProvider: () => owner,
        );
        expect(await aCache.read(), hasLength(1005));
        stage = 'offline reopened presentation';
        await a.repository.pauseRealtime();
        // Drop only the presentation, retaining the existing shared root lease.
        await a.subscriptions.removeAt(2).cancel();
        // subscriptions: connection readiness, root snapshot, list, unread.
        final offline = <ChatListViewState>[];
        a.subscriptions.add(a.repository.watchChatList().listen(offline.add));
        await _until(() => offline.isNotEmpty && offline.last.ready);
        final beforeOffline = a.remote.pageCalls;
        final offlineWatch = Stopwatch()..start();
        for (var i = 0; i < 24 && offline.last.chats.length < 1005; i++) {
          await a.repository.loadMoreChatList();
        }
        await _until(() => offline.last.chats.length == 1005);
        offlineWatch.stop();
        expect(a.remote.pageCalls, beforeOffline);
        final offlineRequests = a.remote.pageCalls - beforeOffline;
        expect(offline.last.chats.map((c) => c.id).toSet(), chats.toSet());
        stage = 'far incoming message while A is paused';
        final bHead = b.remote.pageCalls;
        await _sql(_insert(chats[0], peers[0]));
        await _until(
          () => views[1].last.chats.first.id == chats[0] && totals[1].last == 1,
        );
        expect(b.remote.pageCalls, bHead);
        expect(b.remote.batches.last, {chats[0]});
        stage = 'resume catches missed update';
        await a.repository.resumeRealtime();
        await _until(
          () =>
              a.ready &&
              offline.last.chats.first.id == chats[0] &&
              totals[0].last == 1,
        );
        expect(offline.last.chats, hasLength(1005));
        expect(await aCache.read(), hasLength(1005));
        stage = 'hidden offscreen row from device B';
        final hidden = chats[500];
        expect(offline.last.chats.any((c) => c.id == hidden), true);
        await b.repository.deleteChats({hidden});
        await _until(() => !offline.last.chats.any((c) => c.id == hidden));
        stage = 'search and clearing retain the complete available list';
        final name = offline.last.chats.first.userName.toLowerCase();
        await a.repository.setChatListQuery(name);
        await _until(
          () =>
              offline.last.query == name &&
              offline.last.ready &&
              !offline.last.isRefreshing,
        );
        expect(
          offline.last.chats.every(
            (c) => c.userName.toLowerCase().startsWith(name),
          ),
          true,
        );
        await a.repository.setChatListQuery('');
        await _until(
          () => offline.last.query.isEmpty && offline.last.chats.length == 1004,
        );
        for (final d in devices) {
          expect(d.remote.fullCalls, 0);
          expect(d.remote.batches.every((ids) => ids.length <= 50), true);
          expect(d.client.getChannels(), hasLength(1));
          expect(
            await d.database.select(d.database.cachedMessages).get(),
            isEmpty,
          );
        }
        stdout.writeln(
          'PRODUCTION_PAGED_CHAT_LIST ${jsonEncode({'passed': true, 'chats': 1005, 'online_browse_ms': onlineWatch.elapsedMilliseconds, 'offline_browse_ms': offlineWatch.elapsedMilliseconds, 'offline_requests': offlineRequests, 'page_calls': devices.map((d) => d.remote.pageCalls).toList(), 'full_calls': devices.map((d) => d.remote.fullCalls).toList(), 'channels': devices.map((d) => d.client.getChannels().length).toList(), 'far_update_promoted': true, 'hidden_retained_removed': true})}',
        );
      } catch (error) {
        stdout.writeln(
          'PRODUCTION_PAGED_CHAT_LIST_FAILED stage=$stage error=$error',
        );
        rethrow;
      } finally {
        for (final d in devices) {
          await d.dispose();
        }
        final ids = users.map((id) => "'$id'").join(',');
        await _sql(
          '''begin;delete from public.conversations where user_one_id in($ids) or user_two_id in($ids);
        delete from public.profiles where id in($ids);delete from auth.users where id in($ids);commit;''',
        );
        expect(await _counts(), before);
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(seconds: 120)),
  );
  test(
    '1000 chats, two devices, real insert/read/mute/hide/resume/reconnect',
    () async {
      final auth = await _env('supabase_auth_Yap_chat');
      final storage = await _env('supabase_storage_Yap_chat');
      final owner = _uuid.v4();
      final peers = [for (var i = 0; i < 1000; i++) _uuid.v4()];
      final chats = [for (var i = 0; i < 1000; i++) _uuid.v4()];
      final users = [owner, ...peers];
      final devices = <_Device>[];
      final before = await _counts();
      var stage = 'fixtures';
      try {
        await _sql(
          '''begin;
        insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
        ${users.map((id) => "('$id',false,false,'{}')").join(',')};
        insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at) values
        ${chats.indexed.map((pair) => "('${pair.$2}',least('$owner'::uuid,'${peers[pair.$1]}'::uuid),greatest('$owner'::uuid,'${peers[pair.$1]}'::uuid),'${peers[pair.$1]}','2020-01-01'::timestamptz+${pair.$1}*interval '1 second')").join(',')};
        insert into public.conversation_members(conversation_id,user_id) values
        ${chats.indexed.expand((pair) => ["('${pair.$2}','$owner')", "('${pair.$2}','${peers[pair.$1]}')"]).join(',')};commit;''',
        );
        for (var i = 0; i < 2; i++) {
          stage = 'initial device $i';
          final device = await _Device.create(
            owner,
            storage['ANON_KEY']!,
            auth['GOTRUE_JWT_SECRET']!,
          );
          devices.add(device);
          await _until(() => device.ready && device.latest.length == 1000);
        }
        stage = 'typed page API';
        for (final d in devices) {
          final first = await d.remote.fetchChatListPage();
          expect(first.unreadTotal, 0);
          expect(first.items.map((e) => e.chat.id), chats.reversed.take(50));
          expect(
            first.items.first.activityAt,
            DateTime.utc(2020, 1, 1).add(const Duration(seconds: 999)),
          );
          expect(first.hasMore, true);
          final next = await d.remote.fetchChatListPage(
            after: first.nextCursor,
          );
          expect(
            next.items.map((e) => e.chat.id),
            chats.reversed.skip(50).take(50),
          );
          expect({
            ...first.items.map((e) => e.chat.id),
            ...next.items.map((e) => e.chat.id),
          }, hasLength(100));
          final listCache = ChatsCacheDataSource(
            database: d.database,
            userIdProvider: () => owner,
          );
          await listCache.applyListPage(
            await listCache.beginListRefresh(),
            first,
          );
        }
        final peerValues = <List<Chat?>>[];
        final unreadValues = <List<int?>>[];
        for (final d in devices) {
          final counts = <int?>[];
          unreadValues.add(counts);
          d.subscriptions.add(
            d.repository.watchUnreadCount().listen(counts.add),
          );
          for (var observer = 0; observer < 2; observer++) {
            final values = <Chat?>[];
            peerValues.add(values);
            d.subscriptions.add(
              d.repository.watchChatByPeerId(peers[0]).listen(values.add),
            );
          }
        }
        await _until(
          () => peerValues.every(
            (values) => values.isNotEmpty && values.last?.id == chats[0],
          ),
        );
        await _until(
          () => unreadValues.every((counts) => counts.lastOrNull == 0),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final baseline = [for (final d in devices) d.remote.fullCalls];
        stage = 'insert burst';
        await _sql(
          'begin;${[for (var i = 0; i < 100; i++) _insert(chats[i], peers[i])].join('\n')}commit;',
        );
        await _until(
          () => devices.every(
            (d) => d.latest.where((c) => c.unreadCount == 1).length == 100,
          ),
        );
        await _until(
          () => peerValues.every((values) => values.last?.unreadCount == 1),
        );
        await _until(() => unreadValues.every((counts) => counts.last == 100));
        final activity =
            jsonDecode(
                  await _sql(
                    '''select jsonb_object_agg(conversation_id,
          (extract(epoch from activity_at)*1000000)::bigint) from private.chat_list_catalog
          where user_id='$owner' and conversation_id in(${chats.take(100).map((id) => "'$id'").join(',')});''',
                  ),
                )
                as Map<String, dynamic>;
        for (final d in devices) {
          final entries = await d.database
              .select(d.database.cachedChatListEntries)
              .get();
          for (final entry in entries.where(
            (e) => activity.containsKey(e.chatId),
          )) {
            expect(entry.activityMicros, activity[entry.chatId]);
          }
          expect(
            entries.where((e) => activity.containsKey(e.chatId)),
            hasLength(100),
          );
          final listCache = ChatsCacheDataSource(
            database: d.database,
            userIdProvider: () => owner,
          );
          expect(
            (await listCache.readListState()).nextCursor?.conversationId,
            chats[950],
          );
        }
        for (var i = 0; i < 2; i++) {
          expect(devices[i].remote.fullCalls, baseline[i]);
          expect(devices[i].remote.batches.length, inInclusiveRange(2, 4));
          expect(devices[i].client.getChannels(), hasLength(1));
          expect(devices[i].sockets, hasLength(1));
        }
        final burst = [
          for (final d in devices)
            {
              'full_requests':
                  d.remote.fullCalls - baseline[devices.indexOf(d)],
              'batch_requests': d.remote.batches.length,
              'rows_requested': d.remote.batches.fold<int>(
                0,
                (n, ids) => n + ids.length,
              ),
            },
        ];
        for (final d in devices) {
          final state = await d.remote.fetchUnreadState(
            conversationIds: {chats[0]},
          );
          expect(state.unreadTotal, 100);
          expect(state.chats.single.unreadCount, 1);
          expect((await d.remote.fetchChatListPage()).unreadTotal, 100);
        }
        expect(
          devices.every(
            (d) => d.remote.batches.every((ids) => ids.length <= 50),
          ),
          true,
        );

        stage = 'manual read';
        await devices[0].repository.markAsRead(chats.take(50).toSet());
        await _until(
          () => devices.every(
            (d) => chats.take(50).every((id) => d.row(id)?.unreadCount == 0),
          ),
        );
        await _until(
          () => peerValues.every((values) => values.last?.unreadCount == 0),
        );
        await _until(() => unreadValues.every((counts) => counts.last == 50));
        for (final d in devices) {
          expect(
            chats.skip(50).take(50).every((id) => d.row(id)?.unreadCount == 1),
            true,
          );
        }
        stage = 'mute';
        expect((await devices[0].remote.fetchUnreadState()).unreadTotal, 50);
        await devices[0].repository.setMuted(
          chats.take(50).toSet(),
          isMuted: true,
        );
        await _until(
          () => devices.every(
            (d) => chats.take(50).every((id) => d.row(id)?.isMuted == true),
          ),
        );
        await _until(
          () => peerValues.every((values) => values.last?.isMuted == true),
        );
        stage = 'hide';
        await devices[0].repository.deleteChats({chats[0]});
        await _until(() => devices.every((d) => d.row(chats[0]) == null));
        await _until(() => peerValues.every((values) => values.last == null));
        final restoredMessage = _uuid.v4();
        stage = 'incoming restore';
        await _sql(_insert(chats[0], peers[0], id: restoredMessage));
        await _until(
          () => devices.every(
            (d) => d.row(chats[0])?.lastMessageId == restoredMessage,
          ),
        );
        expect(devices.every((d) => d.row(chats[0])?.unreadCount == 1), true);
        await _until(
          () => peerValues.every(
            (values) => values.last?.lastMessageId == restoredMessage,
          ),
        );

        stage = 'pause';
        await devices[0].repository.pauseRealtime();
        final missed = _uuid.v4();
        await _sql(_insert(chats[900], peers[900], id: missed));
        await _until(() => devices[1].row(chats[900])?.lastMessageId == missed);
        expect(devices[0].row(chats[900])?.lastMessageId, isNot(missed));
        stage = 'resume';
        await devices[0].repository.resumeRealtime();
        await _until(
          () =>
              devices[0].row(chats[900])?.lastMessageId == missed &&
              devices[0].ready,
        );
        await _until(() => unreadValues.every((counts) => counts.last == 51));

        // Break only the physical transport: SDK/source recovery must catch up.
        devices[0].ready = false;
        stage = 'transport recovery';
        await devices[0].sockets.last.sink.close();
        final reconnectMessage = _uuid.v4();
        await _sql(_insert(chats[901], peers[901], id: reconnectMessage));
        await _until(
          () =>
              devices[0].ready &&
              devices[0].row(chats[901])?.lastMessageId == reconnectMessage,
        );
        await _until(() => unreadValues.every((counts) => counts.last == 52));
        for (final d in devices) {
          expect(d.latest, hasLength(1000));
          expect(d.client.getChannels(), hasLength(1));
          expect(
            await d.database.select(d.database.cachedMessages).get(),
            isEmpty,
          );
        }
        final report = {
          'passed': true,
          'chats': 1000,
          'devices': 2,
          'typed_page_api': true,
          'two_peer_observers_per_device': true,
          'peer_read_mute_hide_incoming_restore': true,
          'live_global_count_read_resume_reconnect': true,
          'live_delta_exact_activity_and_unchanged_cursor': true,
          'count_only_reads': [
            for (final d in devices) d.remote.countOnlyReads,
          ],
          'global_unread_in_page_and_subset': true,
          'burst': burst,
          'manual_read_mute_hide_incoming_restore': true,
          'missed_event_resume': true,
          'transport_recovery': true,
          'steady_channels_per_device': [
            for (final d in devices) d.client.getChannels().length,
          ],
          'transports_created_including_recovery': [
            for (final d in devices) d.sockets.length,
          ],
          'closed_chat_history_rows': 0,
        };
        File(
          'tmp/targeted_chat_local_integration.json',
        ).writeAsStringSync(jsonEncode(report));
        // ignore: avoid_print
        print('TARGETED_CHAT_LOCAL ${jsonEncode(report)}');
      } catch (error) {
        File('tmp/targeted_chat_local_failure.json').writeAsStringSync(
          jsonEncode({
            'stage': stage,
            'error_type': error.runtimeType.toString(),
            'devices': [
              for (final d in devices)
                {
                  'ready': d.ready,
                  'rows': d.latest.length,
                  'full_calls': d.remote.fullCalls,
                  'full_results': d.remote.fullResults,
                  'read_errors': d.remote.readErrors,
                  'batches': d.remote.batches.map((e) => e.length).toList(),
                  'unread': d.latest.fold<int>(0, (n, c) => n + c.unreadCount),
                },
            ],
          }),
        );
        rethrow;
      } finally {
        for (final device in devices) {
          await device.dispose();
        }
        final ids = users.map((id) => "'$id'").join(',');
        await _sql(
          '''begin;delete from public.conversations where user_one_id in($ids) or user_two_id in($ids);
        delete from public.profiles where id in($ids);delete from auth.users where id in($ids);commit;''',
        );
        expect(await _counts(), before);
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(seconds: 100)),
  );
  test(
    'addressed navigation outside 1000 rows and first-send creation use bounded reads',
    () async {
      final auth = await _env('supabase_auth_Yap_chat');
      final storage = await _env('supabase_storage_Yap_chat');
      final owner = _uuid.v4(), newPeer = _uuid.v4();
      final peers = [for (var i = 0; i < 2005; i++) _uuid.v4()];
      final chats = [for (var i = 0; i < 2005; i++) _uuid.v4()];
      final users = [owner, newPeer, ...peers];
      final before = await _counts();
      _Device? device;
      try {
        await _sql(
          '''begin;
      insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values
      ${users.map((id) => "('$id',false,false,'{}')").join(',')};
      insert into public.conversations(id,user_one_id,user_two_id,created_by,created_at) values
      ${chats.indexed.map((pair) => "('${pair.$2}',least('$owner'::uuid,'${peers[pair.$1]}'::uuid),greatest('$owner'::uuid,'${peers[pair.$1]}'::uuid),'${peers[pair.$1]}','2020-01-01'::timestamptz+${pair.$1}*interval '1 second')").join(',')};
      insert into public.conversation_members(conversation_id,user_id)values
      ${chats.indexed.expand((pair) => ["('${pair.$2}','$owner')", "('${pair.$2}','${peers[pair.$1]}')"]).join(',')};
      insert into public.messages(id,conversation_id,sender_id,type,text,created_at)values('${_uuid.v4()}','${chats[0]}','${peers[0]}','text','older hidden history','2019-01-01');commit;''',
        );
        final d = device = await _Device.create(
          owner,
          storage['ANON_KEY']!,
          auth['GOTRUE_JWT_SECRET']!,
        );
        await _until(() => d.ready && d.latest.length == 1000);
        expect(d.row(chats[0]), isNull);
        final globalCounts = <int?>[];
        d.subscriptions.add(
          d.repository.watchUnreadCount().listen(globalCounts.add),
        );
        await _until(() => globalCounts.lastOrNull == 1);
        final outsidePeer = <Chat?>[];
        d.subscriptions.add(
          d.repository.watchChatByPeerId(peers[0]).listen(outsidePeer.add),
        );
        await _until(() => outsidePeer.isNotEmpty);
        expect(outsidePeer.single, isNull);
        // The unread chat is outside the legacy 1000-row head. Its unread
        // contribution must survive an empty selection or filtered page.
        expect((await d.remote.fetchUnreadState()).unreadTotal, 1);
        expect((await d.remote.fetchChatListPage()).unreadTotal, 1);
        await _verifyPagedCache(d.remote, owner, chats.toSet());
        final baseline = d.remote.fullCalls;
        final tail = await d.repository.getChatById(chats[0]);
        expect(tail?.id, chats[0]);
        await _until(() => outsidePeer.last?.id == chats[0]);
        expect(d.remote.fullCalls, baseline);
        expect(d.remote.batches, [
          {chats[0]},
        ]);
        d.sync.openConversation(chats[0]);
        await d.repository.getChats();
        await _until(
          () => d.remote.batches.length >= 2 && d.row(chats[0]) != null,
        );
        expect(d.row(chats[0]), isNotNull);
        final afterExplicitFull = d.remote.fullCalls;
        final draft = await d.repository.prepareDirectChat(
          peerId: peers[1],
          peerUsername: 'peer',
          peerDisplayName: 'Peer',
        );
        expect(draft.isDraft, true);
        await _until(() => d.row(chats[1]) != null);
        expect(d.remote.peerCalls, 1);
        expect(d.remote.fullCalls, afterExplicitFull);
        expect(d.remote.createCalls, 0);
        final newDraft = await d.repository.prepareDirectChat(
          peerId: newPeer,
          peerUsername: 'new',
          peerDisplayName: 'New',
        );
        expect(newDraft.isDraft, true);
        await _until(() => d.remote.peerCalls == 2);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(d.remote.createCalls, 0);
        expect(
          await _sql(
            "select count(*)from public.conversations where user_one_id='$owner' or user_two_id='$owner';",
          ),
          '2005',
        );
        await expectLater(
          d.repository.ensureDirectChat(newPeer),
          throwsA(isA<ChatLimitReachedException>()),
        );
        expect(d.remote.createCalls, 1);
        expect(d.remote.fullCalls, afterExplicitFull);
        // The existing product limit is 100 visible chats (including incoming).
        // Keep the two addressed conversations, then test an allowed first send.
        await _sql(
          "update public.conversation_members set hidden_at=clock_timestamp() where user_id='$owner' and conversation_id not in('${chats[0]}','${chats[1]}');",
        );
        await d.repository.getChats();
        final beforeFirstSend = d.remote.fullCalls;
        final created = await d.repository.ensureDirectChat(newPeer);
        expect(created.isDraft, false);
        expect(created.peerId, newPeer);
        expect(d.remote.createCalls, 2);
        expect(d.remote.fullCalls, beforeFirstSend);
        final messageId = _uuid.v4();
        await ChatRemoteDataSource(client: d.client).sendMessage(
          id: messageId,
          chatId: created.id,
          type: MessageType.text,
          text: 'first message after addressed creation',
        );
        await _until(() => d.row(created.id)?.lastMessageId == messageId);
        await d.client.rpc<void>(
          'hide_conversations',
          params: {
            'conversation_ids': [chats[0]],
            'cleared_before': DateTime.now().toUtc().toIso8601String(),
          },
        );
        await _until(() => d.row(chats[0]) == null);
        d.sync.closeConversation(chats[0], session: d.account.capture());
        final hiddenDraft = await d.repository.prepareDirectChat(
          peerId: peers[0],
          peerUsername: 'old',
          peerDisplayName: 'Old',
        );
        expect(hiddenDraft.isDraft, true);
        await _until(() => d.remote.peerCalls == 3);
        final reopened = await d.repository.ensureDirectChat(peers[0]);
        expect(reopened.id, chats[0]);
        expect(reopened.lastMessageId, isNull);
        final restoredMessage = _uuid.v4();
        final messageRemote = ChatRemoteDataSource(client: d.client);
        await messageRemote.sendMessage(
          id: restoredMessage,
          chatId: reopened.id,
          type: MessageType.text,
          text: 'after manual reopen',
        );
        await _until(
          () => d.row(reopened.id)?.lastMessageId == restoredMessage,
        );
        final restoredHistory = await messageRemote.fetchMessages(reopened.id);
        expect(restoredHistory.map((message) => message.id), [restoredMessage]);
        expect(
          await d.database.select(d.database.cachedMessages).get(),
          isEmpty,
        );
        expect(d.client.getChannels(), hasLength(1));
        expect(d.sockets, hasLength(1));
        final report = {
          'passed': true,
          'server_chats_before_creation': 2005,
          'legacy_head_rows': 1000,
          'unread_total_includes_chat_outside_head': true,
          'outside_id_lookup': true,
          'outside_peer_observer': true,
          'live_global_count_includes_outside_head': true,
          'profile_existing_lookup': true,
          'new_profile_did_not_create': true,
          'first_send_created_once': true,
          'existing_100_limit_enforced': true,
          'creation_attempts': d.remote.createCalls,
          'sent_message_visible': true,
          'hidden_open_chat_removed': true,
          'manual_reopen_kept_id_and_clear_cutoff': true,
          'explicit_history_validation_requests': 1,
          'full_reads_for_navigation': d.remote.fullCalls - beforeFirstSend,
          'known_id_batches': d.remote.batches.map((e) => e.length).toList(),
          'peer_requests': d.remote.peerCalls,
          'channels': d.client.getChannels().length,
          'message_history_rows': 0,
        };
        File(
          'tmp/direct_chat_lookup_local_integration.json',
        ).writeAsStringSync(jsonEncode(report));
        // ignore: avoid_print
        print('DIRECT_CHAT_LOOKUP_LOCAL ${jsonEncode(report)}');
      } finally {
        await device?.dispose();
        final ids = users.map((id) => "'$id'").join(',');
        await _sql(
          '''begin;delete from public.conversations where user_one_id in($ids) or user_two_id in($ids);
      delete from public.profiles where id in($ids);delete from auth.users where id in($ids);commit;''',
        );
        expect(await _counts(), before);
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(seconds: 100)),
  );
}

String _insert(String chat, String sender, {String? id}) =>
    "insert into public.messages(id,conversation_id,sender_id,type,text,created_at) values('${id ?? _uuid.v4()}','$chat','$sender','text','real summary integration',clock_timestamp());";

class _Device {
  _Device(
    this.client,
    this.realtime,
    this.remote,
    this.database,
    this.media,
    this.repository,
    this.sockets,
    this.sync,
    this.account,
    this.connection,
  );
  final SupabaseClient client;
  final UserRealtimeDataSource realtime;
  final _MeasuredRemote remote;
  final AppDatabase database;
  final MediaCacheService media;
  final ChatsRepository repository;
  final List<IOWebSocketChannel> sockets;
  final ConversationSyncService sync;
  final AccountSessionController account;
  final AppConnectionStatus connection;
  final subscriptions = <StreamSubscription<dynamic>>[];
  List<Chat> latest = [];
  bool ready = false;
  Chat? row(String id) => latest.where((c) => c.id == id).firstOrNull;
  static Future<_Device> create(
    String owner,
    String anon,
    String secret, {
    bool paged = false,
  }) async {
    final sockets = <IOWebSocketChannel>[];
    final client = SupabaseClient(
      'http://127.0.0.1:54321',
      anon,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions: RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: Duration.zero,
        transport: (url, headers) {
          final socket = IOWebSocketChannel.connect(url, headers: headers);
          sockets.add(socket);
          return socket;
        },
      ),
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': _jwt(owner, secret),
        'refresh_token': 'local-test',
        'token_type': 'bearer',
        'user': {
          'id': owner,
          'aud': 'authenticated',
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final media = MediaCacheService(database: db);
    final account = AccountSessionController(initialUserId: owner);
    final talker = Talker(settings: TalkerSettings(enabled: false));
    final config = AppConfig(
      environment: AppEnvironment.prod,
      preferences: prefs,
      talker: talker,
      env: const {},
      database: db,
      accountSessionController: account,
    );
    final connection = AppConnectionStatus(
      accountSessionController: account,
      presentationDelay: Duration.zero,
    )..watchHeartbeats(client.realtime.onHeartbeat);
    final realtime = UserRealtimeDataSource(
      client: client,
      talker: talker,
      connectionStatus: connection,
    );
    final remote = _MeasuredRemote(client, realtime, talker, connection);
    final cache = ChatsCacheDataSource(
      database: db,
      userIdProvider: () => owner,
    );
    final messages = ChatCacheDataSource(
      database: db,
      userIdProvider: () => owner,
    );
    final mr = ChatRemoteDataSource(
      client: client,
      connectionStatus: connection,
    );
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
    final d = _Device(
      client,
      realtime,
      remote,
      db,
      media,
      repository,
      sockets,
      sync,
      account,
      connection,
    );
    d.subscriptions.add(
      realtime.watchConnectionEvents().listen((ready) => d.ready = ready),
    );
    d.subscriptions.add(
      repository.watchChats().listen((chats) => d.latest = chats),
    );
    return d;
  }

  Future<void> dispose() async {
    connection.dispose();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await repository.pauseRealtime();
    await realtime.dispose();
    await client.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    media.dispose();
    await database.close();
  }
}

class _MeasuredRemote extends ChatsRemoteDataSource {
  _MeasuredRemote(
    SupabaseClient client,
    UserRealtimeDataSource realtime,
    Talker talker,
    AppConnectionStatus connection,
  ) : super(
        client: client,
        userRealtime: realtime,
        talker: talker,
        connectionStatus: connection,
      );
  int fullCalls = 0;
  int pageCalls = 0;
  @override
  Future<ChatListPage> fetchChatListPage({
    ChatListPageCursor? after,
    int pageSize = 50,
    String searchQuery = '',
  }) {
    pageCalls++;
    return super.fetchChatListPage(
      after: after,
      pageSize: pageSize,
      searchQuery: searchQuery,
    );
  }

  int peerCalls = 0, createCalls = 0;
  final fullResults = <int>[];
  final readErrors = <String>[];
  final batches = <Set<String>>[];
  int countOnlyReads = 0;
  @override
  Future<List<Chat>> fetchChats() async {
    fullCalls++;
    try {
      final rows = await super.fetchChats();
      fullResults.add(rows.length);
      return rows;
    } catch (error) {
      readErrors.add(
        error is PostgrestException
            ? '${error.code}: ${error.message}'
            : error.runtimeType.toString(),
      );
      rethrow;
    }
  }

  @override
  Future<List<Chat>> fetchChatsByIds(Set<String> ids) {
    batches.add(Set.of(ids));
    return super.fetchChatsByIds(ids);
  }

  @override
  Future<ChatUnreadState> fetchUnreadState({
    Set<String> conversationIds = const {},
  }) {
    if (conversationIds.isEmpty) {
      countOnlyReads++;
    } else {
      batches.add(Set.of(conversationIds));
    }
    return super.fetchUnreadState(conversationIds: conversationIds);
  }

  @override
  Future<Chat?> fetchChatByPeerId(String peerId) {
    peerCalls++;
    return super.fetchChatByPeerId(peerId);
  }

  @override
  Future<String> createDirectConversation(String peerId) {
    createCalls++;
    return super.createDirectConversation(peerId);
  }
}

Future<void> _until(bool Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!check()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Missing local chat state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _verifyPagedCache(
  ChatsRemoteDataSource remote,
  String owner,
  Set<String> expectedIds,
) async {
  final connection = sqlite.sqlite3.openInMemory();
  var db = AppDatabase.forTesting(
    NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
  );
  try {
    var cache = ChatsCacheDataSource(database: db, userIdProvider: () => owner);
    final reference = <String>[];
    var request = await cache.beginListRefresh();
    var pages = 0;
    while (true) {
      final page = await remote.fetchChatListPage(after: request.after);
      reference.addAll(page.items.map((i) => i.chat.id));
      expect(page.unreadTotal, 1);
      expect(await cache.applyListPage(request, page), true);
      pages++;
      final next = await cache.nextListRequest();
      if (next == null) break;
      request = next;
      expect(pages, lessThan(50));
    }
    expect(pages, 41);
    expect(reference.toSet(), expectedIds);
    expect(reference.toSet().length, reference.length);
    expect((await cache.readUnreadState()).total, 1);
    expect(await db.select(db.cachedMessages).get(), isEmpty);
    await db.close();
    db = AppDatabase.forTesting(
      NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
    );
    cache = ChatsCacheDataSource(database: db, userIdProvider: () => owner);
    final offline = <String>[];
    ChatListLocalCursor? after;
    do {
      final slice = await cache.readListSlice(after: after);
      expect(slice.chats.length, lessThanOrEqualTo(50));
      expect(slice.serverBacked, true);
      offline.addAll(slice.chats.map((c) => c.id));
      after = slice.nextCursor;
    } while (after != null);
    expect(offline, reference);
    expect((await cache.readUnreadState()).total, 1);
    expect((await cache.readListState()).hasMore, false);
    stdout.writeln(
      'PAGED_CHAT_CACHE_LOCAL ${jsonEncode({'passed': true, 'chats': offline.length, 'pages': pages, 'reopened_offline_order_matches': true, 'history_rows': 0, 'badge_outside_head': 1})}',
    );
  } finally {
    await db.close();
    connection.close();
  }
}

Future<String> _counts() => _sql(
  "select jsonb_build_object('users',(select count(*) from auth.users),'chats',(select count(*) from public.conversations),'messages',(select count(*) from public.messages),'unread_keys',(select count(*)from private.chat_unread_messages),'unread_counts',(select count(*)from private.chat_unread_counts));",
);
Future<String> _sql(String sql) async {
  final p = await Process.start('docker', [
    'exec',
    '-i',
    'supabase_db_Yap_chat',
    'psql',
    '-X',
    '-U',
    'postgres',
    '-d',
    'postgres',
    '-v',
    'ON_ERROR_STOP=1',
    '-qAt',
  ]);
  final out = utf8.decodeStream(p.stdout), err = utf8.decodeStream(p.stderr);
  p.stdin.write("set statement_timeout='30s';\n$sql");
  await p.stdin.close();
  final code = await p.exitCode;
  expect(code, 0, reason: await err);
  return (await out).trim();
}

Future<Map<String, String>> _env(String name) async {
  final r = await Process.run('docker', [
    'inspect',
    '--format',
    '{{json .Config.Env}}',
    name,
  ]);
  expect(r.exitCode, 0, reason: 'Local Docker required');
  return {
    for (final s in (jsonDecode(r.stdout as String) as List).cast<String>())
      s.substring(0, s.indexOf('=')): s.substring(s.indexOf('=') + 1),
  };
}

String _jwt(String user, String secret) {
  String encode(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final data =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': user, 'role': 'authenticated', 'aud': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600})}';
  return '$data.${base64Url.encode(Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(data)).bytes).replaceAll('=', '')}';
}
