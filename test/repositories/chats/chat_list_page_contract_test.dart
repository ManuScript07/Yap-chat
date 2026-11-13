import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

const _id1 = 'b8630000-0000-0000-0000-000000000001';
const _id2 = 'b8630000-0000-0000-0000-000000000002';
const _id3 = 'b8630000-0000-0000-0000-000000000003';
const _instant = '2026-01-01T12:34:56.123456Z';

void main() {
  test(
    'page carries an account total even when the page has no items',
    () async {
      final h = _Harness({
        'items': [],
        'has_more': false,
        'query': '',
        'next_cursor': null,
        'unread_total': 55,
      });
      addTearDown(h.dispose);
      expect((await h.remote.fetchChatListPage()).unreadTotal, 55);
    },
  );
  for (final value in [-1, null, '1', 1.5]) {
    test('page rejects malformed aggregate $value', () async {
      final h = _Harness({
        'items': [],
        'has_more': false,
        'query': '',
        'next_cursor': null,
        'unread_total': value,
      });
      addTearDown(h.dispose);
      await expectLater(h.remote.fetchChatListPage(), throwsFormatException);
    });
  }
  test(
    'real SDK JSON parsing preserves microseconds, metadata and search cursor',
    () async {
      final h = _Harness({
        'items': [_row(_id3), _row(_id2)],
        'has_more': true,
        'query': 'ал',
        'next_cursor': _cursor(_id2, query: 'ал'),
      });
      addTearDown(h.dispose);
      final page = await h.remote.fetchChatListPage(searchQuery: '  АЛ  ');
      expect(page.items.map((e) => e.chat.id), [_id3, _id2]);
      expect(page.items.first.activityAt.microsecond, 456);
      expect(page.nextCursor?.activityAt.toUtc().toIso8601String(), _instant);
      expect(page.query, 'ал');
      expect(page.hasMore, true);
      expect(page.items.first.chat.unreadCount, 3);
      expect(page.items.first.chat.isMuted, true);
      expect(() => page.items.clear(), throwsUnsupportedError);
      expect(jsonDecode(h.requests.single.body), {
        'after_activity_at': null,
        'after_conversation_id': null,
        'page_size': 50,
        'search_query': 'ал',
      });
    },
  );
  test(
    'next cursor is submitted without rounding or local timezone conversion',
    () async {
      final h = _Harness({
        'items': [_row(_id1)],
        'has_more': false,
        'query': '',
        'next_cursor': null,
      });
      addTearDown(h.dispose);
      final result = await h.remote.fetchChatListPage(
        after: ChatListPageCursor(
          activityAt: DateTime.parse('2026-01-01T15:34:56.123456+03:00'),
          conversationId: _id2,
        ),
      );
      expect(result.hasMore, false);
      expect(result.nextCursor, null);
      expect(jsonDecode(h.requests.single.body)['after_activity_at'], _instant);
    },
  );
  test('concurrently emptied page can still advance a valid cursor', () async {
    final h = _Harness({
      'items': [],
      'has_more': true,
      'query': '',
      'next_cursor': _cursor(_id1),
    });
    addTearDown(h.dispose);
    final page = await h.remote.fetchChatListPage(
      after: ChatListPageCursor(
        activityAt: DateTime.parse(_instant),
        conversationId: _id3,
      ),
    );
    expect(page.items, isEmpty);
    expect(page.hasMore, true);
    expect(page.nextCursor?.conversationId, _id1);
  });
  test('empty final page has no cursor', () async {
    final h = _Harness({
      'items': [],
      'has_more': false,
      'query': '',
      'next_cursor': null,
    });
    addTearDown(h.dispose);
    expect((await h.remote.fetchChatListPage()).items, isEmpty);
  });
  test(
    'invalid size/query and stale-search cursor do not issue HTTP',
    () async {
      final h = _Harness({});
      addTearDown(h.dispose);
      for (final size in [0, -1, 51]) {
        await expectLater(
          h.remote.fetchChatListPage(pageSize: size),
          throwsArgumentError,
        );
      }
      await expectLater(
        h.remote.fetchChatListPage(searchQuery: List.filled(101, 'a').join()),
        throwsArgumentError,
      );
      await expectLater(
        h.remote.fetchChatListPage(
          searchQuery: 'new',
          after: ChatListPageCursor(
            activityAt: DateTime.parse(_instant),
            conversationId: _id3,
            query: 'old',
          ),
        ),
        throwsArgumentError,
      );
      expect(h.requests, isEmpty);
    },
  );
  final malformed = <String, Map<String, dynamic>>{
    'missing array': {'items': null},
    'not a boolean': {'has_more': 1},
    'wrong query': {'query': 'other'},
    'duplicate ID': {
      'items': [_row(_id3), _row(_id3)],
    },
    'ascending ties': {
      'items': [_row(_id1), _row(_id2)],
    },
    'invalid time': {
      'items': [
        {..._row(_id3), 'list_activity_at': 'broken'},
      ],
    },
    'missing cursor': {'has_more': true},
    'final cursor': {'next_cursor': _cursor(_id3)},
    'cursor query': {
      'has_more': true,
      'next_cursor': _cursor(_id3, query: 'bad'),
    },
    'cursor before last item': {
      'items': [_row(_id1)],
      'has_more': true,
      'next_cursor': _cursor(_id3),
    },
  };
  for (final entry in malformed.entries) {
    test('malformed page fails atomically: ${entry.key}', () async {
      final h = _Harness({
        'items': [_row(_id3)],
        'has_more': false,
        'query': '',
        'next_cursor': null,
        ...entry.value,
      });
      addTearDown(h.dispose);
      await expectLater(h.remote.fetchChatListPage(), throwsFormatException);
    });
  }
  test('non-advancing cursor is rejected', () async {
    final h = _Harness({
      'items': [],
      'has_more': true,
      'query': '',
      'next_cursor': _cursor(_id3),
    });
    addTearDown(h.dispose);
    await expectLater(
      h.remote.fetchChatListPage(
        after: ChatListPageCursor(
          activityAt: DateTime.parse(_instant),
          conversationId: _id3,
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'rows outside a requested cursor and oversized pages are rejected',
    () async {
      final h = _Harness({
        'items': [_row(_id3)],
        'has_more': false,
        'query': '',
        'next_cursor': null,
      });
      addTearDown(h.dispose);
      await expectLater(
        h.remote.fetchChatListPage(
          after: ChatListPageCursor(
            activityAt: DateTime.parse(_instant),
            conversationId: _id2,
          ),
        ),
        throwsFormatException,
      );
      h.payload = {
        'items': [_row(_id3), _row(_id2)],
        'has_more': false,
        'query': '',
        'next_cursor': null,
      };
      await expectLater(
        h.remote.fetchChatListPage(pageSize: 1),
        throwsFormatException,
      );
    },
  );
  test(
    'rate limit and network failures never become an empty successful page',
    () async {
      final h = _Harness({
        'message': 'chat_list_page_rate_limited',
        'code': 'PT429',
      });
      addTearDown(h.dispose);
      h.status = 429;
      await expectLater(
        h.remote.fetchChatListPage(),
        throwsA(isA<PostgrestException>()),
      );
      expect(h.requests, hasLength(1));
    },
  );
}

Map<String, dynamic> _row(String id) => {
  'id': id,
  'peer_id': 'peer',
  'peer_display_name': 'Алёна',
  'last_message_at': _instant,
  'list_activity_at': _instant,
  'unread_count': 3,
  'is_muted': true,
};
Map<String, dynamic> _cursor(String id, {String query = ''}) => {
  'activity_at': _instant,
  'conversation_id': id,
  'query': query,
};

class _Harness {
  _Harness(this.payload) {
    client = SupabaseClient(
      'http://localhost',
      'key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(payload),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    remote = _Remote(client);
  }
  Map<String, dynamic> payload;
  int status = 200;
  final requests = <http.Request>[];
  late final SupabaseClient client;
  late final _Remote remote;
  Future<void> dispose() => client.dispose();
}

class _Remote extends ChatsRemoteDataSource {
  _Remote(SupabaseClient client)
    : super(
        client: client,
        talker: Talker(settings: TalkerSettings(enabled: false)),
      );
  @override
  String get currentUserId => 'owner';
}
