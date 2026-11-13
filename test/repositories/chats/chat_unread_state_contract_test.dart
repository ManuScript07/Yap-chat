import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  Future<void> check(
    Map<String, dynamic> payload,
    Future<void> Function(ChatsRemoteDataSource, List<http.Request>) action, {
    int status = 200,
  }) async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
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
    try {
      await action(_Remote(client), requests);
    } finally {
      await client.dispose();
    }
  }

  test('global total is independent of the one selected summary', () async {
    await check(
      {
        'items': [_row],
        'unread_total': 42,
      },
      (remote, requests) async {
        final state = await remote.fetchUnreadState(conversationIds: {'chat'});
        expect(state.unreadTotal, 42);
        expect(state.chats.single.unreadCount, 3);
        expect(() => state.chats.clear(), throwsUnsupportedError);
        expect(requests.single.url.path, '/rest/v1/rpc/get_chat_unread_state');
        expect(jsonDecode(requests.single.body), {
          'conversation_ids': ['chat'],
        });
      },
    );
  });
  test(
    'empty selection can return a nonzero badge without fetching profiles',
    () async {
      await check({'items': [], 'unread_total': 7}, (remote, requests) async {
        final state = await remote.fetchUnreadState();
        expect(state.chats, isEmpty);
        expect(state.unreadTotal, 7);
        expect(requests, hasLength(1));
        expect(jsonDecode(requests.single.body), {'conversation_ids': []});
      });
    },
  );
  test('invalid selection never reaches HTTP', () async {
    await check({'items': [], 'unread_total': 0}, (remote, requests) async {
      await expectLater(
        remote.fetchUnreadState(conversationIds: {' '}),
        throwsArgumentError,
      );
      await expectLater(
        remote.fetchUnreadState(
          conversationIds: {for (var i = 0; i < 51; i++) '$i'},
        ),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
    });
  });
  final malformed = <String, Map<String, dynamic>>{
    'negative total': {'items': [], 'unread_total': -1},
    'missing total': {'items': []},
    'null total': {'items': [], 'unread_total': null},
    'string total': {'items': [], 'unread_total': '3'},
    'fractional total': {'items': [], 'unread_total': 3.5},
    'invalid items': {'items': {}, 'unread_total': 0},
    'unrequested row': {
      'items': [
        {..._row, 'id': 'other'},
      ],
      'unread_total': 1,
    },
    'duplicate rows': {
      'items': [_row, _row],
      'unread_total': 1,
    },
  };
  for (final entry in malformed.entries) {
    test('rejects ${entry.key}', () async {
      await check(entry.value, (remote, _) async {
        await expectLater(
          remote.fetchUnreadState(conversationIds: {'chat', 'chat2'}),
          throwsFormatException,
        );
      });
    });
  }
  test('429 propagates without a retry or false zero', () async {
    await check({'message': 'quota', 'code': 'PT429'}, (
      remote,
      requests,
    ) async {
      await expectLater(
        remote.fetchUnreadState(),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'PT429'),
        ),
      );
      expect(requests, hasLength(1));
    }, status: 429);
  });
}

const _row = {
  'id': 'chat',
  'peer_id': 'peer',
  'last_message_at': '2026-01-01T00:00:00Z',
  'unread_count': 3,
};

class _Remote extends ChatsRemoteDataSource {
  _Remote(SupabaseClient client)
    : super(
        client: client,
        talker: Talker(settings: TalkerSettings(enabled: false)),
      );
  @override
  String get currentUserId => 'owner';
}
