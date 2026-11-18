import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

void main() {
  test('uses the comment RPC target, sort and reaction revisions', () async {
    const viewer = '10000000-0000-4000-8000-000000000001';
    final requests = <(String, Map<String, dynamic>)>[];
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final rpc = request.url.pathSegments.last;
        requests.add((rpc, jsonDecode(request.body) as Map<String, dynamic>));
        final payload = switch (rpc) {
          'set_feed_comment_liked' => {
            'action_version': 5,
            'liked': true,
            'changed': true,
          },
          'submit_feed_content_report' => <String, Object?>{},
          _ => {
            'items': [
              {
                'id': 'comment',
                'root_id': 'root',
                'version': 2,
                'post_version': 3,
                'action_version': 4,
                'liked': false,
                'like_count': 8,
                'text': 'reply',
                'author': {
                  'id': 'author',
                  'avatar_storage_path': 'avatars/author.jpg',
                },
                'reply_to': {
                  'comment_id': 'parent',
                  'username': 'parent-handle',
                  'user_id': 'parent-account',
                },
              },
            ],
            'next_cursor': null,
          },
        };
        return http.Response(
          jsonEncode(payload),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await _signIn(client, viewer);
    final accounts = AccountSessionController(initialUserId: viewer);
    final repository = FeedRepository(client: client, accounts: accounts);
    final account = accounts.capture();
    await repository.getComments(
      'post',
      account,
      sort: FeedCommentSort.newFirst,
    );
    await repository.getComments('post', account, sort: FeedCommentSort.old);
    final page = await repository.getComments(
      'post',
      account,
      rootId: 'root',
      cursor: (sessionId: 'thread-cursor', position: 19),
    );
    final comment = page.comments.single;
    expect(comment.avatarPath, 'avatars/author.jpg');
    expect(comment.replyTo, (
      id: 'parent',
      username: 'parent-handle',
      userId: 'parent-account',
    ));
    expect(
      await repository.setCommentLiked(
        comment,
        comment.reaction,
        'react',
        account,
      ),
      (version: 5, liked: true, changed: true),
    );
    await repository.reportComment(
      comment.id,
      FeedReportReason.spam,
      'report',
      account,
    );
    final expected = [
      (
        'get_feed_comments',
        {
          'requested_post': 'post',
          'requested_sort': 'new',
          'requested_limit': 20,
        },
      ),
      (
        'get_feed_comments',
        {
          'requested_post': 'post',
          'requested_sort': 'old',
          'requested_limit': 20,
        },
      ),
      (
        'get_feed_comment_replies',
        {
          'requested_post': 'post',
          'requested_root': 'root',
          'requested_session': 'thread-cursor',
          'after_position': 19,
          'requested_limit': 20,
        },
      ),
      (
        'set_feed_comment_liked',
        {
          'requested_id': 'react',
          'requested_comment': 'comment',
          'requested_liked': true,
          'expected_version': 4,
          'expected_comment_version': 2,
          'expected_post_version': 3,
        },
      ),
      (
        'submit_feed_content_report',
        {
          'requested_id': 'report',
          'requested_type': 'comment',
          'requested_content': 'comment',
          'requested_reason': 'spam',
        },
      ),
    ];
    expect(
      requests.map((request) => [request.$1, request.$2]),
      expected.map((request) => [request.$1, request.$2]),
    );
  });

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
    await _signIn(client, viewer);
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

  test(
    'media files survive a repository restart and stay scoped to the viewer',
    () async {
      const viewer = '10000000-0000-4000-8000-000000000001';
      const other = '10000000-0000-4000-8000-000000000002';
      final directory = await Directory.systemTemp.createTemp(
        'yap-feed-media-',
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final cache = MediaCacheService(
        database: database,
        environment: 'test',
        cacheDirectoryProvider: () async => directory,
        supportDirectoryProvider: () async => directory,
      );
      addTearDown(() async {
        cache.dispose();
        await database.close();
        await directory.delete(recursive: true);
      });
      final requests = <String>[];
      final pendingDownload = Completer<void>();
      final downloadStarted = Completer<void>();
      final client = SupabaseClient(
        'http://127.0.0.1:1',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path.endsWith('/pending.jpg')) {
            downloadStarted.complete();
            await pendingDownload.future;
          }
          return http.Response.bytes(
            [255, 216, 42, 255, 217],
            200,
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _signIn(client, viewer);
      final accounts = AccountSessionController(initialUserId: viewer);
      FeedRepository repository() =>
          FeedRepository(client: client, accounts: accounts, mediaCache: cache);
      final first = repository();
      final account = accounts.capture();
      const photo = FeedPhoto(
        id: 'photo',
        thumbnailPath: 'fixture/thumb.jpg',
        path: 'fixture/full.jpg',
      );
      final post = FeedPost(
        id: 'post',
        authorId: 'a99ae948-e8cb-4080-b82e-3d11652af383',
        authorName: null,
        text: '',
        createdAt: DateTime.utc(2026),
        photos: const [photo],
        friendsOnly: true,
      );
      await Future.wait(
        List.generate(
          4,
          (_) => first.downloadThumbnail(
            photo,
            post: post,
            account: account,
            stillNeeded: () => true,
          ),
        ),
      );
      await first.downloadPhoto(
        photo,
        post: post,
        account: account,
        stillNeeded: () => true,
      );
      expect(requests, hasLength(2));
      final restarted = repository();
      await restarted.downloadThumbnail(
        photo,
        post: post,
        account: account,
        stillNeeded: () => true,
      );
      await restarted.downloadPhoto(
        photo,
        post: post,
        account: account,
        stillNeeded: () => true,
      );
      expect(requests, hasLength(2));
      final actions = FeedActionsCubit(
        restarted,
        account,
        () => accounts.isCurrent(account),
      );
      addTearDown(actions.close);
      final public = FeedPost(
        id: 'public',
        authorId: 'public-author',
        authorName: null,
        text: '',
        createdAt: DateTime.utc(2026),
        photos: const [photo],
      );
      var quote = post;
      for (final author in [
        'e71f448b-ad69-471d-98e3-6161ebc2324e',
        '244d2477-d007-4178-92d9-0e3bd3e44efb',
        '2835e454-7623-4771-8b18-98eba7c29413',
        '71bfe58e-0a33-4686-964f-708a56bdb100',
      ]) {
        quote = FeedPost(
          id: author,
          authorId: author,
          authorName: null,
          text: '',
          createdAt: DateTime.utc(2026),
          photos: const [photo],
          original: quote,
        );
      }
      for (final item in [public, quote]) {
        await first.downloadThumbnail(
          photo,
          post: item,
          account: account,
          stillNeeded: () => true,
        );
      }
      expect(requests, hasLength(4));
      expect(
        await cache.storageGroups(ownerUserId: viewer, bucket: 'feed-media'),
        hasLength(3),
      );
      await cache.storeBytes(
        ownerUserId: viewer,
        bucket: 'feed-media',
        storagePath: 'legacy.jpg',
        bytes: Uint8List.fromList([1]),
      );
      // A fresh actions scope has not rendered or tracked any of these posts.
      await actions.recheckFriendships((ids) async {
        expect(ids, {post.authorId});
        return {};
      });
      await accounts.drainCommits();
      expect(actions.canShow(post), isFalse);
      expect(actions.canShow(quote), isFalse);
      expect(actions.canShow(public), isTrue);
      expect(
        await cache.storageGroups(ownerUserId: viewer, bucket: 'feed-media'),
        hasLength(1),
      );
      expect(
        await cache.findStorageFile(
          ownerUserId: viewer,
          bucket: 'feed-media',
          storagePath: 'legacy.jpg',
          mimeType: 'image/jpeg',
        ),
        isNull,
      );
      await restarted.downloadThumbnail(
        photo,
        post: public,
        account: account,
        stillNeeded: () => true,
      );
      expect(requests, hasLength(4));
      await restarted.downloadThumbnail(
        photo,
        post: post,
        account: account,
        stillNeeded: () => true,
      );
      expect(requests, hasLength(5));
      const pendingPhoto = FeedPhoto(
        id: 'pending',
        thumbnailPath: 'pending.jpg',
      );
      final inFlightPost = FeedPost(
        id: 'late-post',
        authorId: 'late-author',
        authorName: null,
        text: '',
        createdAt: DateTime.utc(2026),
        friendsOnly: true,
        photos: const [pendingPhoto],
      );
      final beforeRevocation = await cache.storageGroups(
        ownerUserId: viewer,
        bucket: 'feed-media',
      );
      final late = restarted.downloadThumbnail(
        pendingPhoto,
        post: inFlightPost,
        account: account,
        stillNeeded: () => actions.canShow(inFlightPost),
      );
      final discard = expectLater(
        late,
        throwsA(isA<StaleAccountSessionException>()),
      );
      await downloadStarted.future;
      actions.friendshipRemoved(inFlightPost.authorId);
      pendingDownload.complete();
      await discard;
      await accounts.drainCommits();
      expect(
        await cache.storageGroups(ownerUserId: viewer, bucket: 'feed-media'),
        beforeRevocation,
      );
      expect(requests, hasLength(6));
      accounts.setAuthenticatedUser(other);
      await _signIn(client, other);
      await expectLater(
        first.downloadThumbnail(
          photo,
          post: post,
          account: account,
          stillNeeded: () => true,
        ),
        throwsA(isA<StaleAccountSessionException>()),
      );
      await restarted.downloadThumbnail(
        photo,
        post: post,
        account: accounts.capture(),
        stillNeeded: () => true,
      );
      expect(requests, hasLength(7));
    },
  );
}

Future<void> _signIn(SupabaseClient client, String userId) async {
  final claims = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': userId,
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
      'user': {'id': userId, 'aud': 'authenticated'},
    }),
  );
}
