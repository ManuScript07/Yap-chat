import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/services/services.dart';

import 'feed_formatting.dart';
import 'feed_post.dart';

enum FeedTab {
  forYou('get_for_you_feed_v2'),
  nearby('get_nearby_feed'),
  friends('get_friends_feed');

  const FeedTab(this.rpc);

  final String rpc;
}

typedef FeedCursor = ({String sessionId, String? token, int? position});

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

abstract interface class IFeedPostRepository {
  Future<FeedPost?> getPost(String id, AccountSessionSnapshot account);
  Future<FeedFollowState> getFollow(
    String authorId,
    AccountSessionSnapshot account,
  );
  Future<FeedFollowState> setFollow(
    String authorId,
    FeedFollowState current,
    String requestId,
    AccountSessionSnapshot account,
  );
  Future<({int version, bool liked})> act(
    FeedDelivery delivery,
    FeedPostAction action,
    int version,
    String requestId,
    AccountSessionSnapshot account,
  );
  Future<void> report(
    String id,
    FeedReportReason reason,
    String requestId,
    AccountSessionSnapshot account,
  );
  Future<void> repost(
    String id,
    String requestId,
    AccountSessionSnapshot account,
  );
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

class FeedRepository implements IFeedRepository, IFeedPostRepository {
  FeedRepository({
    required this._client,
    required this._accounts,
    this._connection,
    this._diagnostics,
    this._mediaCache,
  });

  static const _timeout = Duration(seconds: 10);
  static const _maxThumbnailDownloads = 4;
  final SupabaseClient _client;
  final AccountSessionController _accounts;
  final AppConnectionStatus? _connection;
  final AppDiagnostics? _diagnostics;
  final MediaCacheService? _mediaCache;
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
        (response['items'] as List<dynamic>).map(
          (item) => _decodePost(
            item['post'] as Map<String, dynamic>,
            delivery: _delivery(item as Map<String, dynamic>),
          ),
        ),
      ),
    );
  }

  FeedDelivery? _delivery(Map<String, dynamic> row) {
    final id = row['delivery_id'];
    final expiresAt = DateTime.tryParse(
      row['delivery_expires_at'] as String? ?? '',
    );
    return id is String && expiresAt != null
        ? (id: id, expiresAt: expiresAt)
        : null;
  }

  FeedFollowState _follow(Map<String, dynamic> row) => (
    version: row['version'] as int,
    following: row['following'] as bool,
    canFollow: row['can_follow'] as bool,
  );

  FeedPost _decodePost(
    Map<String, dynamic> row, {
    FeedDelivery? delivery,
    int depth = 0,
  }) {
    final author = row['author'] as Map<String, dynamic>?;
    final displayName = (author?['display_name'] as String?)?.trim();
    final text = row['text'] as String;
    final location = row['location'] as Map<String, dynamic>?;
    final latitude = (location?['latitude'] as num?)?.toDouble();
    final longitude = (location?['longitude'] as num?)?.toDouble();
    final follow = row['author_relationship'] as Map<String, dynamic>?;
    final original = row['original'] as Map<String, dynamic>?;
    final reposts = row['reposted_by'] as List<dynamic>?;
    return FeedPost(
      id: row['id'] as String,
      authorId: row['author_id'] as String,
      authorName: displayName == null || displayName.isEmpty
          ? (author?['username'] as String?)
          : displayName,
      username: author?['username'] as String?,
      avatarUrl: author?['avatar_url'] as String?,
      avatarPath: author?['avatar_storage_path'] as String?,
      avatarRevision: author?['avatar_updated_at'] as String?,
      text: text,
      formatting: decodeFeedFormatting(text, row['formatting']),
      createdAt: DateTime.parse(row['created_at'] as String),
      edited: row['edited'] == true,
      viewCount: row['view_count'] as int? ?? 0,
      commentCount: row['comment_count'] as int? ?? 0,
      repostCount: row['repost_count'] as int? ?? 0,
      reaction: (
        version: row['action_version'] as int? ?? 0,
        liked: row['liked'] == true,
        likes: row['like_count'] as int? ?? 0,
      ),
      follow: follow == null ? null : _follow(follow),
      delivery: delivery,
      coordinates: latitude == null || longitude == null
          ? null
          : (latitude: latitude, longitude: longitude),
      nearby: location?['nearby'] == true,
      isQuote: row['is_repost'] == true,
      original: original == null || depth >= 4
          ? null
          : _decodePost(original, depth: depth + 1),
      repostedBy: reposts?.firstOrNull?['username'] as String?,
      reposted: row['my_repost'] != null,
      photos: List.unmodifiable(
        (row['photos'] as List<dynamic>).map(
          (photo) => FeedPhoto(
            id: photo['id'] as String,
            thumbnailPath: photo['thumbnail_path'] as String,
          ),
        ),
      ),
    );
  }

  Future<T> _postRpc<T>(
    String name,
    Map<String, dynamic> params,
    AccountSessionSnapshot account,
  ) async {
    _ensureAccount(account);
    final result = await observeSupabaseRpc(
      _connection,
      _diagnostics,
      name,
      () => _client
          .rpc<T>(name, params: params)
          .retry(enabled: false)
          .timeout(_timeout),
    );
    _ensureAccount(account);
    return result;
  }

  @override
  Future<FeedPost?> getPost(String id, AccountSessionSnapshot account) async {
    final row = await _postRpc<Map<String, dynamic>?>('get_feed_post', {
      'requested_id': id,
    }, account);
    return row == null ? null : _decodePost(row, delivery: _delivery(row));
  }

  @override
  Future<FeedFollowState> getFollow(
    String authorId,
    AccountSessionSnapshot account,
  ) async => _follow(
    await _postRpc<Map<String, dynamic>>('get_feed_author_follow_state', {
      'requested_author': authorId,
    }, account),
  );

  @override
  Future<FeedFollowState> setFollow(
    String authorId,
    FeedFollowState current,
    String requestId,
    AccountSessionSnapshot account,
  ) async {
    final response =
        await _postRpc<Map<String, dynamic>>('set_feed_author_followed', {
          'requested_id': requestId,
          'requested_author': authorId,
          'requested_following': !current.following,
          'expected_version': current.version,
        }, account);
    return (
      version: response['version'] as int,
      following: response['following'] as bool,
      canFollow: current.canFollow,
    );
  }

  @override
  Future<({int version, bool liked})> act(
    FeedDelivery delivery,
    FeedPostAction action,
    int version,
    String requestId,
    AccountSessionSnapshot account,
  ) async {
    final response = await _postRpc<Map<String, dynamic>>('apply_feed_action', {
      'requested_id': requestId,
      'requested_delivery': delivery.id,
      'requested_action': action == FeedPostAction.lessSimilar
          ? 'less_similar'
          : action.name,
      'expected_version': version,
    }, account);
    return (
      version: response['action_version'] as int,
      liked: response['liked'] as bool,
    );
  }

  @override
  Future<void> report(
    String id,
    FeedReportReason reason,
    String requestId,
    AccountSessionSnapshot account,
  ) async {
    await _postRpc<Object?>('submit_feed_content_report', {
      'requested_id': requestId,
      'requested_type': 'post',
      'requested_content': id,
      'requested_reason': reason.name,
    }, account);
  }

  Future<String?> loadAvatar(
    String path,
    AccountSessionSnapshot account,
  ) async {
    _ensureAccount(account);
    final result = await _mediaCache?.cacheStorageFile(
      ownerUserId: account.userId,
      bucket: 'avatars',
      storagePath: path,
      mimeType: 'image/jpeg',
    );
    _ensureAccount(account);
    return result;
  }

  @override
  Future<void> repost(
    String id,
    String requestId,
    AccountSessionSnapshot account,
  ) async {
    await _postRpc<Object?>('create_feed_repost', {
      'requested_id': requestId,
      'requested_original': id,
    }, account);
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
