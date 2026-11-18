import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/services/services.dart';

import 'feed_post.dart';
import 'feed_post_projection.dart';

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
    required FeedPost post,
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  });
}

abstract interface class IFeedPublicationRepository {
  Future<FeedCommentsPage> getComments(
    String id,
    AccountSessionSnapshot account, {
    FeedCommentsCursor? cursor,
    FeedCommentSort sort = FeedCommentSort.popular,
    String? rootId,
  });
  Future<FeedCommentCreation> createComment(
    String id,
    String requestId,
    String text,
    AccountSessionSnapshot account, {
    String? replyTo,
  });
  Future<FeedCommentLike> setCommentLiked(
    FeedComment comment,
    FeedReaction current,
    String requestId,
    AccountSessionSnapshot account,
  );
  Future<void> reportComment(
    String id,
    FeedReportReason reason,
    String requestId,
    AccountSessionSnapshot account,
  );
  Future<Uint8List> downloadPhoto(
    FeedPhoto photo, {
    required FeedPost post,
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  });
}

class FeedRepository
    implements
        IFeedRepository,
        IFeedPostRepository,
        IFeedPublicationRepository {
  FeedRepository({
    required this._client,
    required this._accounts,
    this._connection,
    this._diagnostics,
    this._mediaCache,
  });

  static const _timeout = Duration(seconds: 10);
  static const _mediaBucket = 'feed-media';
  static const _maxThumbnailDownloads = 4;
  final SupabaseClient _client;
  final AccountSessionController _accounts;
  final AppConnectionStatus? _connection;
  final AppDiagnostics? _diagnostics;
  final MediaCacheService? _mediaCache;
  final _thumbnails = <(int, String, String?), Future<Uint8List>>{};
  final _photos = <(int, String, String?), Future<Uint8List>>{};
  final _mediaGroups = Expando<String>();

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
          (item) => decodeFeedPost(
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
    if (row == null) {
      unawaited(evictMedia(account, postId: id));
      return null;
    }
    return decodeFeedPost(row, delivery: _delivery(row));
  }

  @override
  Future<FeedFollowState> getFollow(
    String authorId,
    AccountSessionSnapshot account,
  ) async => decodeFeedFollowState(
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
    required FeedPost post,
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) => _downloadMedia(
    photo.thumbnailPath,
    post,
    account,
    stillNeeded,
    _thumbnails,
    limit: _maxThumbnailDownloads,
    metric: 'feed_thumbnail',
  );

  @override
  Future<Uint8List> downloadPhoto(
    FeedPhoto photo, {
    required FeedPost post,
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) => _downloadMedia(
    photo.path ?? photo.thumbnailPath,
    post,
    account,
    stillNeeded,
    _photos,
    limit: 1,
    metric: 'feed_photo',
  );

  Future<Uint8List> _downloadMedia(
    String path,
    FeedPost post,
    AccountSessionSnapshot account,
    bool Function() stillNeeded,
    Map<(int, String, String?), Future<Uint8List>> inFlight, {
    required int limit,
    required String metric,
  }) async {
    final group = _mediaCache == null || kIsWeb
        ? null
        : _mediaGroups[post] ??= _feedMediaGroup(post);
    final key = (account.generation, path, group);
    while (stillNeeded() &&
        !inFlight.containsKey(key) &&
        inFlight.length >= limit) {
      await Future.any(
        inFlight.values.map(
          (download) => download.then<void>((_) {}, onError: (Object _) {}),
        ),
      );
    }
    if (!stillNeeded()) throw const StaleAccountSessionException();
    _ensureAccount(account);
    final pending = inFlight[key];
    if (pending != null) {
      final bytes = await pending;
      _ensureAccount(account);
      if (!stillNeeded()) throw const StaleAccountSessionException();
      return bytes;
    }
    final download = _download(path, group, account, metric, stillNeeded);
    inFlight[key] = download;
    try {
      final bytes = await download;
      _ensureAccount(account);
      if (!stillNeeded()) throw const StaleAccountSessionException();
      return bytes;
    } finally {
      inFlight.remove(key);
    }
  }

  Future<Uint8List> _download(
    String path,
    String? group,
    AccountSessionSnapshot account,
    String metric,
    bool Function() stillNeeded,
  ) async {
    final cache = _mediaCache;
    if (cache != null && group != null) {
      try {
        final local = await cache.findStorageFile(
          ownerUserId: account.userId,
          bucket: _mediaBucket,
          storagePath: path,
          mimeType: 'image/jpeg',
          cacheGroup: group,
        );
        if (local != null) {
          final bytes = await File(local).readAsBytes();
          _ensureAccount(account);
          if (bytes.isNotEmpty) return bytes;
        }
        if (stillNeeded()) {
          final legacy = await cache.findStorageFile(
            ownerUserId: account.userId,
            bucket: _mediaBucket,
            storagePath: path,
            mimeType: 'image/jpeg',
          );
          if (legacy != null) {
            final bytes = await File(legacy).readAsBytes();
            if (bytes.isNotEmpty) {
              await _storeMedia(
                cache,
                account,
                group,
                path,
                bytes,
                stillNeeded,
              );
              _ensureAccount(account);
              return bytes;
            }
          }
        }
      } on StaleAccountSessionException {
        rethrow;
      } catch (_) {
        // A missing or evicted file is a cache miss.
      }
    }
    _ensureAccount(account);
    final bytes = await measureRpc(
      _diagnostics,
      metric,
      () => _client.storage.from(_mediaBucket).download(path).timeout(_timeout),
    );
    _ensureAccount(account);
    if (cache != null && group != null && stillNeeded()) {
      await _storeMedia(cache, account, group, path, bytes, stillNeeded);
    }
    _ensureAccount(account);
    return bytes;
  }

  Future<void> _storeMedia(
    MediaCacheService cache,
    AccountSessionSnapshot account,
    String group,
    String path,
    Uint8List bytes,
    bool Function() stillNeeded,
  ) async {
    try {
      await _accounts.commit(account, () async {
        if (!stillNeeded()) return;
        await cache.storeBytes(
          ownerUserId: account.userId,
          bucket: _mediaBucket,
          storagePath: path,
          mimeType: 'image/jpeg',
          bytes: bytes,
          cacheGroup: group,
        );
      });
    } on StaleAccountSessionException {
      rethrow;
    } catch (_) {
      // The authorized bytes remain usable without a disk write.
    }
  }

  Future<Set<String>> cachedMediaFriends(AccountSessionSnapshot account) async {
    final cache = _mediaCache;
    if (cache == null || !_accounts.isCurrent(account)) return {};
    try {
      final groups = await cache.storageGroups(
        ownerUserId: account.userId,
        bucket: _mediaBucket,
      );
      if (!_accounts.isCurrent(account)) return {};
      return {
        for (final group in groups)
          if (_readFeedMediaGroup(group) case final scope?)
            for (final entry in scope.authors.entries)
              if (entry.value && entry.key != account.userId) entry.key,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> evictMedia(
    AccountSessionSnapshot account, {
    String? postId,
    Set<String> blocked = const {},
    Set<String> removedFriends = const {},
  }) async {
    final cache = _mediaCache;
    if (cache == null) return;
    try {
      await _accounts.commit(
        account,
        () => cache.removeStorageGroups(
          ownerUserId: account.userId,
          bucket: _mediaBucket,
          removeUngrouped: true,
          matches: (group) {
            final scope = _readFeedMediaGroup(group);
            return scope == null ||
                scope.postId == postId ||
                scope.authors.keys.any(blocked.contains) ||
                removedFriends.any((id) => scope.authors[id] == true);
          },
        ),
      );
    } catch (_) {
      // Access is checked separately from the file and logout clears the scope.
    }
  }

  @override
  Future<FeedCommentsPage> getComments(
    String id,
    AccountSessionSnapshot account, {
    FeedCommentsCursor? cursor,
    FeedCommentSort sort = FeedCommentSort.popular,
    String? rootId,
  }) async {
    final result = await _postRpc<Map<String, dynamic>>(
      rootId == null ? 'get_feed_comments' : 'get_feed_comment_replies',
      {
        'requested_post': id,
        'requested_root': ?rootId,
        if (rootId == null && sort != FeedCommentSort.popular)
          'requested_sort': sort == FeedCommentSort.newFirst ? 'new' : 'old',
        if (cursor != null) 'requested_session': cursor.sessionId,
        if (cursor != null) 'after_position': cursor.position,
        'requested_limit': 20,
      },
      account,
    );
    final next = result['next_cursor'] as Map<String, dynamic>?;
    return (
      comments: [
        for (final row in result['items'] as List<dynamic>) _comment(row),
      ],
      next: next == null
          ? null
          : (
              sessionId: next['session_id'] as String,
              position: next['after_position'] as int,
            ),
    );
  }

  @override
  Future<FeedCommentCreation> createComment(
    String id,
    String requestId,
    String text,
    AccountSessionSnapshot account, {
    String? replyTo,
  }) async {
    final row = await _postRpc<Map<String, dynamic>>('create_feed_comment', {
      'requested_id': requestId,
      'requested_post': id,
      'requested_text': text,
      'requested_reply_to': ?replyTo,
    }, account);
    final count = row['post_comment_count'];
    final revision = row['post_comment_count_revision'];
    return (
      comment: _comment(row),
      postCount: count is int && revision is int
          ? (count: count, revision: revision)
          : null,
    );
  }

  FeedComment _comment(Map<String, dynamic> row) {
    final author = row['author'] as Map<String, dynamic>?;
    final target = row['reply_to'] as Map<String, dynamic>?;
    final preview = row['reply_preview'] as Map<String, dynamic>?;
    return FeedComment(
      id: row['id'] as String,
      rootId: row['root_id'] as String?,
      authorId: author?['id'] as String?,
      authorName: (author?['display_name'] ?? author?['username']) as String?,
      username: author?['username'] as String?,
      avatarUrl: author?['avatar_url'] as String?,
      avatarPath: author?['avatar_storage_path'] as String?,
      avatarRevision: author?['avatar_updated_at'] as String?,
      text: row['text'] as String?,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      replyTo: target?['username'] is String && target?['comment_id'] is String
          ? (
              id: target!['comment_id'] as String,
              username: target['username'] as String,
              userId: target['user_id'] as String?,
            )
          : null,
      replyPreview: preview == null ? null : _comment(preview),
      replyCount: row['reply_count'] as int? ?? 0,
      commentVersion: row['version'] as int? ?? 0,
      postVersion: row['post_version'] as int? ?? 0,
      reaction: (
        version: row['action_version'] as int? ?? 0,
        liked: row['liked'] == true,
        likes: row['like_count'] as int? ?? 0,
      ),
    );
  }

  @override
  Future<FeedCommentLike> setCommentLiked(
    FeedComment comment,
    FeedReaction current,
    String requestId,
    AccountSessionSnapshot account,
  ) async {
    final row = await _postRpc<Map<String, dynamic>>('set_feed_comment_liked', {
      'requested_id': requestId,
      'requested_comment': comment.id,
      'requested_liked': !current.liked,
      'expected_version': current.version,
      'expected_comment_version': comment.commentVersion,
      'expected_post_version': comment.postVersion,
    }, account);
    return (
      version: row['action_version'] as int,
      liked: row['liked'] as bool,
      changed: row['changed'] == true,
    );
  }

  @override
  Future<void> reportComment(
    String id,
    FeedReportReason reason,
    String requestId,
    AccountSessionSnapshot account,
  ) async {
    await _postRpc<Object?>('submit_feed_content_report', {
      'requested_id': requestId,
      'requested_type': 'comment',
      'requested_content': id,
      'requested_reason': reason.name,
    }, account);
  }

  void _ensureAccount(AccountSessionSnapshot account) {
    _accounts.ensureCurrent(account);
    if (_client.auth.currentUser?.id != account.userId) {
      throw const StaleAccountSessionException();
    }
  }
}

String _feedMediaGroup(FeedPost post) {
  final authors = <String, bool>{};
  for (FeedPost? item = post; item != null; item = item.original) {
    authors[item.authorId] = item.friendsOnly || authors[item.authorId] == true;
  }
  final scope = [
    _packMediaId(post.id),
    for (final entry in authors.entries)
      '${entry.value ? 'f' : 'p'}${_packMediaId(entry.key)}',
  ];
  return _unpaddedBase64(utf8.encode(jsonEncode(scope)));
}

typedef _MediaScope = ({String postId, Map<String, bool> authors});

_MediaScope? _readFeedMediaGroup(String group) {
  try {
    final bytes = base64Url.decode(base64Url.normalize(group));
    final data = jsonDecode(utf8.decode(bytes));
    if (data case [final String postId, ...final authors]) {
      return (
        postId: _unpackMediaId(postId),
        authors: {
          for (final author in authors.cast<String>())
            _unpackMediaId(author.substring(1)): switch (author[0]) {
              'f' => true,
              'p' => false,
              _ => throw const FormatException('Unknown media access'),
            },
        },
      );
    }
  } catch (_) {
    // Unknown or damaged groups cannot be matched to an access scope.
  }
  return null;
}

final _mediaUuid = RegExp(
  r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$',
  caseSensitive: false,
);

// Six 16-byte IDs fit in one cache directory name even at maximum quote depth.
String _packMediaId(String id) => _mediaUuid.hasMatch(id)
    ? _unpaddedBase64(Uuid.parse(id, validate: false))
    : '~$id';

String _unpackMediaId(String id) => id.startsWith('~')
    ? id.substring(1)
    : Uuid.unparse(base64Url.decode(base64Url.normalize(id)));

String _unpaddedBase64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

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
    required FeedPost post,
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) async => throw StateError('The mock feed has no photos');
}
