import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

void main() {
  test('sends the correct RPC and cursor shape for each tab', () async {
    const viewer = '10000000-0000-4000-8000-000000000001';
    const serverSession = '10000000-0000-4000-8000-000000000002';
    const token = '10000000-0000-4000-8000-000000000003';
    final requests = <(String, Map<String, dynamic>)>[];
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final rpc = request.url.pathSegments.last;
        final args = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add((rpc, args));
        final personalized = rpc == FeedTab.forYou.rpc;
        final session = args['requested_session'] as String? ?? serverSession;
        final isHead = personalized
            ? args['requested_cursor'] == null
            : args['after_position'] == -1;
        return http.Response(
          jsonEncode({
            'session_id': session,
            'expires_at': '2026-11-13T20:20:00Z',
            'items': [
              if (!isHead)
                {
                  'post': {
                    'id': 'post',
                    'author_id': 'author',
                    'author': {'display_name': ' Name ', 'username': 'handle'},
                    'text': 'Text',
                    'formatting': {
                      'version': 1,
                      'spans': [
                        {'start': 0, 'end': 4, 'style': 'bold'},
                      ],
                    },
                    'created_at': '2026-11-13T20:00:00Z',
                    'photos': [
                      {
                        'id': 'photo',
                        'thumbnail_path': 'fixture/thumbnail.jpg',
                      },
                    ],
                  },
                },
            ],
            'has_more': isHead,
            'next_cursor': !isHead
                ? null
                : personalized
                ? token
                : {'session_id': session, 'after_position': 19},
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final claims = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': viewer,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            }),
          ),
        )
        .replaceAll('=', '');
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.signature',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {'id': viewer, 'aud': 'authenticated'},
      }),
    );
    final accounts = AccountSessionController(initialUserId: viewer);
    final repository = FeedRepository(client: client, accounts: accounts);
    final account = accounts.capture();

    for (final tab in FeedTab.values) {
      final first = await repository.fetch(tab, account: account);
      final (rpc, head) = requests.last;
      expect(rpc, tab.rpc);
      expect(first.posts, isEmpty);
      final next = first.nextCursor!;
      final last = await repository.fetch(tab, account: account, cursor: next);
      expect(last.nextCursor, isNull);
      expect(last.posts.single.authorName, 'Name');
      expect(last.posts.single.formatting, [
        (start: 0, end: 4, style: FeedTextStyle.bold),
      ]);
      expect(last.posts.single.createdAt, DateTime.utc(2026, 11, 13, 20));
      expect(
        last.posts.single.photos.single.thumbnailPath,
        'fixture/thumbnail.jpg',
      );
      final (_, tail) = requests.last;
      expect(head['requested_limit'], 20);
      expect(tail['requested_limit'], 20);
      expect(tail['requested_session'], next.sessionId);
      if (tab == FeedTab.forYou) {
        expect(head['requested_session'], matches(RegExp(r'^[a-f0-9-]{36}$')));
        expect(tail['requested_session'], head['requested_session']);
        expect(tail['requested_cursor'], token);
      } else {
        expect(head['requested_session'], isNull);
        expect(head['after_position'], -1);
        expect(tail['after_position'], 19);
      }
    }
    accounts.setAuthenticatedUser('other');
    await expectLater(
      repository.fetch(FeedTab.forYou, account: account),
      throwsA(isA<StaleAccountSessionException>()),
    );
    expect(requests, hasLength(6));
  });
}
