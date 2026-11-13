import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/services/services.dart';

enum FeedTab {
  forYou('get_for_you_feed_v2'),
  nearby('get_nearby_feed'),
  friends('get_friends_feed');

  const FeedTab(this.rpc);

  final String rpc;
}

typedef FeedCursor = ({String sessionId, String? token, int? position});

class FeedPhoto {
  const FeedPhoto({required this.id, required this.thumbnailPath});

  final String id;
  final String thumbnailPath;
}

class FeedPost {
  const FeedPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.photos = const [],
  });

  final String id;
  final String authorId;
  final String? authorName;
  final String text;
  final DateTime createdAt;
  final List<FeedPhoto> photos;
}

class FeedPageResult {
  const FeedPageResult({required this.posts, this.nextCursor, this.expiresAt});

  final List<FeedPost> posts;
  final FeedCursor? nextCursor;
  final DateTime? expiresAt;
}

enum FeedFailure implements Exception {
  sessionExpired,
  sessionInvalidated,
  locationRequired,
  accessDenied,
}

abstract interface class IFeedRepository {
  Future<FeedPageResult> fetch(
    FeedTab tab, {
    required AccountSessionSnapshot account,
    FeedCursor? cursor,
  });

  Future<Uint8List> downloadThumbnail(
    FeedPhoto photo, {
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  });
}

class FeedRepository implements IFeedRepository {
  FeedRepository({
    required this._client,
    required this._accounts,
    this._connection,
    this._diagnostics,
  });

  static const _timeout = Duration(seconds: 10);
  static const _maxThumbnailDownloads = 4;
  final SupabaseClient _client;
  final AccountSessionController _accounts;
  final AppConnectionStatus? _connection;
  final AppDiagnostics? _diagnostics;
  final _thumbnails = <(int, String), Future<Uint8List>>{};

  @override
  Future<FeedPageResult> fetch(
    FeedTab tab, {
    required AccountSessionSnapshot account,
    FeedCursor? cursor,
  }) async {
    _ensureAccount(account);
    final personalized = tab == FeedTab.forYou;
    final sessionId =
        cursor?.sessionId ?? (personalized ? const Uuid().v4() : null);
    final params = <String, dynamic>{
      'requested_session': sessionId,
      'requested_limit': 20,
      if (personalized)
        'requested_cursor': cursor?.token
      else
        'after_position': cursor?.position ?? -1,
    };
    final Map<String, dynamic> response;
    try {
      response = await observeSupabaseRpc(
        _connection,
        _diagnostics,
        tab.rpc,
        () => _client
            .rpc<Map<String, dynamic>>(tab.rpc, params: params)
            .timeout(_timeout),
      );
    } on PostgrestException catch (error) {
      _ensureAccount(account);
      if (error.code == 'PT412' && tab == FeedTab.nearby) {
        throw FeedFailure.locationRequired;
      }
      if (cursor != null && error.code == 'PT409') {
        throw FeedFailure.sessionInvalidated;
      }
      if (cursor != null && const {'PT404', 'PT410'}.contains(error.code)) {
        throw FeedFailure.sessionExpired;
      }
      if (const {
        '42501',
        'PT401',
        'PT403',
        'PGRST301',
        'PGRST302',
      }.contains(error.code)) {
        throw FeedFailure.accessDenied;
      }
      rethrow;
    }
    _ensureAccount(account);
    return _decodePage(response, tab, sessionId);
  }

  FeedPageResult _decodePage(
    Map<String, dynamic> response,
    FeedTab tab,
    String? requestedSession,
  ) {
    final session = response['session_id'] as String;
    final rawCursor = response['next_cursor'];
    if (requestedSession != null && session != requestedSession) {
      throw const FormatException('Unexpected feed session');
    }
    final FeedCursor? next;
    if (rawCursor == null) {
      next = null;
    } else if (tab == FeedTab.forYou) {
      next = (sessionId: session, token: rawCursor as String, position: null);
    } else {
      final cursor = rawCursor as Map<String, dynamic>;
      if (cursor['session_id'] != session) {
        throw const FormatException(
          'Feed cursor belongs to a different session',
        );
      }
      next = (
        sessionId: session,
        token: null,
        position: cursor['after_position'] as int,
      );
    }
    return FeedPageResult(
      nextCursor: next,
      expiresAt: DateTime.parse(response['expires_at'] as String),
      posts: List.unmodifiable(
        (response['items'] as List<dynamic>).map((item) {
          final post =
              (item as Map<String, dynamic>)['post'] as Map<String, dynamic>;
          final author = post['author'] as Map<String, dynamic>?;
          final displayName = (author?['display_name'] as String?)?.trim();
          return FeedPost(
            id: post['id'] as String,
            authorId: post['author_id'] as String,
            authorName: displayName == null || displayName.isEmpty
                ? (author?['username'] as String?)
                : displayName,
            text: post['text'] as String,
            createdAt: DateTime.parse(post['created_at'] as String),
            photos: List.unmodifiable(
              (post['photos'] as List<dynamic>).map((item) {
                final photo = item as Map<String, dynamic>;
                return FeedPhoto(
                  id: photo['id'] as String,
                  thumbnailPath: photo['thumbnail_path'] as String,
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  @override
  Future<Uint8List> downloadThumbnail(
    FeedPhoto photo, {
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) async {
    final key = (account.generation, photo.thumbnailPath);
    while (stillNeeded() &&
        !_thumbnails.containsKey(key) &&
        _thumbnails.length >= _maxThumbnailDownloads) {
      await Future.any(
        _thumbnails.values.map(
          (download) => download.then<void>((_) {}, onError: (Object _) {}),
        ),
      );
    }
    if (!stillNeeded()) throw const StaleAccountSessionException();
    _ensureAccount(account);
    final pending = _thumbnails[key];
    if (pending != null) return pending;
    final download = _download(photo, account);
    _thumbnails[key] = download;
    try {
      return await download;
    } finally {
      _thumbnails.remove(key);
    }
  }

  Future<Uint8List> _download(
    FeedPhoto photo,
    AccountSessionSnapshot account,
  ) async {
    final bytes = await measureRpc(
      _diagnostics,
      'feed_thumbnail',
      () => _client.storage
          .from('feed-media')
          .download(photo.thumbnailPath)
          .timeout(_timeout),
    );
    _ensureAccount(account);
    return bytes;
  }

  void _ensureAccount(AccountSessionSnapshot account) {
    _accounts.ensureCurrent(account);
    if (_client.auth.currentUser?.id != account.userId) {
      throw const StaleAccountSessionException();
    }
  }
}

class MockFeedRepository implements IFeedRepository {
  const MockFeedRepository();

  @override
  Future<FeedPageResult> fetch(
    FeedTab tab, {
    required AccountSessionSnapshot account,
    FeedCursor? cursor,
  }) async => const FeedPageResult(posts: []);

  @override
  Future<Uint8List> downloadThumbnail(
    FeedPhoto photo, {
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) async => throw StateError('The mock feed has no photos');
}
