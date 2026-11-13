import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  Future<void> check(
    Object payload,
    Future<void> Function(_Remote, List<http.Request>) action, {
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

  test(
    'single peer summary uses one existing-client RPC and normal metadata mapping',
    () async {
      await check([_row], (remote, requests) async {
        final chat = await remote.fetchChatByPeerId(' peer ');
        expect(chat?.id, 'chat');
        expect(chat?.peerId, 'peer');
        expect(chat?.blockedByPeer, true);
        expect(chat?.avatarUrl, isNull);
        expect(chat?.avatarStoragePath, 'peer/avatar.jpg');
        expect(chat?.unreadCount, 7);
        expect(chat?.isMuted, true);
        expect(requests, hasLength(1));
        expect(
          requests.single.url.path,
          '/rest/v1/rpc/get_direct_chat_summary',
        );
        expect(jsonDecode(requests.single.body), {'peer_user_id': 'peer'});
      });
    },
  );
  test('empty summary is absence, not a draft creation', () async {
    await check([], (remote, requests) async {
      expect(await remote.fetchChatByPeerId('peer'), isNull);
      expect(requests, hasLength(1));
    });
  });
  test('self/empty peer validation happens before HTTP', () async {
    await check([], (remote, requests) async {
      await expectLater(remote.fetchChatByPeerId(' '), throwsArgumentError);
      await expectLater(remote.fetchChatByPeerId('owner'), throwsArgumentError);
      expect(requests, isEmpty);
    });
  });
  final malformed = <String, Object>{
    'two rows': [_row, _row],
    'wrong peer': [
      {..._row, 'peer_id': 'other'},
    ],
    'empty ID': [
      {..._row, 'id': ''},
    ],
    'wrong ID type': [
      {..._row, 'id': 5},
    ],
    'not a row': ['invalid'],
  };
  for (final entry in malformed.entries) {
    test('rejects ${entry.key} before mapping', () async {
      await check(entry.value, (remote, _) async {
        await expectLater(
          remote.fetchChatByPeerId('peer'),
          throwsFormatException,
        );
      });
    });
  }
  test('429 is propagated, never a successful empty response', () async {
    await check(
      {'message': 'chat_summary_refresh_rate_limited', 'code': 'PT429'},
      (remote, requests) async {
        await expectLater(
          remote.fetchChatByPeerId('peer'),
          throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', 'PT429'),
          ),
        );
        expect(requests, hasLength(1));
      },
      status: 429,
    );
  });
}

const _row = {
  'id': 'chat',
  'peer_id': 'peer',
  'peer_display_name': 'Name',
  'peer_avatar_url': 'https://old.invalid/avatar',
  'peer_avatar_storage_path': 'peer/avatar.jpg',
  'last_message_at': '2026-01-01T00:00:00Z',
  'unread_count': 7,
  'is_muted': true,
  'blocked_by_peer': true,
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
