import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  test(
    'changing search aborts only the search and leaves head, direct lookup and writes in flight',
    () async {
      final wire = _AbortClient();
      final client = SupabaseClient(
        'http://localhost',
        'test-key',
        httpClient: wire,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final remote = _Remote(
        client: client,
        talker: Talker(settings: TalkerSettings(enabled: false)),
        summaryRequestTimeout: const Duration(seconds: 3),
      );
      final search = remote.fetchChatListPage(searchQuery: 'alice');
      final error = expectLater(
        search,
        throwsA(isA<http.RequestAbortedException>()),
      );
      final head = remote.fetchChatListPage();
      final direct = remote.fetchChatByPeerId('peer');
      final write = remote.markAsRead({'chat'}).then<void>((_) {});
      await _until(() => wire.requests.length == 4);
      remote.cancelListSearchRequests();
      await error;
      expect(wire.aborts, 1);
      for (final request in wire.requests.where((r) => !r.reply.isCompleted)) {
        final body = request.uri.path.endsWith('get_chat_list_page')
            ? jsonEncode({
                'items': [],
                'query': '',
                'has_more': false,
                'next_cursor': null,
                'unread_total': 0,
              })
            : request.uri.path.endsWith('get_direct_chat_summary')
            ? '[]'
            : null;
        request.reply.complete(
          http.StreamedResponse(
            body == null
                ? const Stream<List<int>>.empty()
                : Stream.value(utf8.encode(body)),
            body == null ? 204 : 200,
            request: request.request,
            headers: {'content-type': 'application/json'},
          ),
        );
      }
      expect((await head).items, isEmpty);
      expect(await direct, isNull);
      await write;
    },
  );
  for (final mode in [
    'full',
    'targeted',
    'page',
    'peer',
    'unread',
    'creation',
  ]) {
    test('SDK aborts timed-out summary HTTP, mode=$mode', () async {
      final wire = _AbortClient();
      final client = SupabaseClient(
        'http://localhost',
        'test-key',
        httpClient: wire,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final remote = _Remote(
        client: client,
        talker: Talker(settings: TalkerSettings(enabled: false)),
        summaryRequestTimeout: const Duration(milliseconds: 100),
      );
      final result = switch (mode) {
        'targeted' => remote.fetchChatsByIds({'chat'}),
        'page' => remote.fetchChatListPage(),
        'peer' => remote.fetchChatByPeerId('peer'),
        'unread' => remote.fetchUnreadState(),
        'creation' => remote.createDirectConversation('peer'),
        _ => remote.fetchChats(),
      };
      await expectLater(result, throwsA(isA<TimeoutException>()));
      expect(wire.requests, hasLength(1));
      expect(wire.aborts, 1);
    });
  }
  test(
    'pause cancels a summary HTTP request but never an accepted write',
    () async {
      final wire = _AbortClient();
      final client = SupabaseClient(
        'http://localhost',
        'test-key',
        httpClient: wire,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final remote = ChatsRemoteDataSource(
        client: client,
        talker: Talker(settings: TalkerSettings(enabled: false)),
      );
      final read = remote.fetchChatsByIds({'chat'});
      final readError = expectLater(
        read,
        throwsA(isA<http.RequestAbortedException>()),
      );
      // PostgrestBuilder is lazy: attach then() so the write is in flight too.
      final write = remote.markAsRead({'chat'}).then<void>((_) {});
      await _until(() => wire.requests.length == 2);
      await remote.pauseChanges();
      await readError;
      expect(wire.aborts, 1);
      final pendingWrite = wire.requests.singleWhere(
        (r) => r.uri.path.endsWith('mark_conversations_read'),
      );
      expect(pendingWrite.reply.isCompleted, false);
      pendingWrite.reply.complete(
        http.StreamedResponse(
          const Stream<List<int>>.empty(),
          204,
          request: pendingWrite.request,
        ),
      );
      await write;
    },
  );
}

class _Remote extends ChatsRemoteDataSource {
  _Remote({
    required super.client,
    required super.talker,
    required super.summaryRequestTimeout,
  });
  @override
  String get currentUserId => 'owner';
}

Future<void> _until(bool Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!check()) {
    if (DateTime.now().isAfter(end)) fail('HTTP did not start');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _AbortClient extends http.BaseClient {
  final requests =
      <
        ({
          Uri uri,
          http.BaseRequest request,
          Completer<http.StreamedResponse> reply,
        })
      >[];
  int aborts = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final reply = Completer<http.StreamedResponse>();
    requests.add((uri: request.url, request: request, reply: reply));
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        if (!reply.isCompleted) {
          aborts++;
          reply.completeError(http.RequestAbortedException(request.url));
        }
      });
    }
    return reply.future;
  }
}
