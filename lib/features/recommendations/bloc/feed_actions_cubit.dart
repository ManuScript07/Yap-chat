import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/data/feed_media_frames.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_publication_cache.dart';

typedef FeedActionsState = ({
  Map<String, FeedFollowState> follows,
  Map<String, FeedReaction> reactions,
  Set<String> busy,
  Set<String> hidden,
  Set<String> blocked,
  Map<String, int> reposts,
  Map<String, FeedCommentCount> commentCounts,
  int accessVersion,
});

class FeedActionsCubit extends Cubit<FeedActionsState> {
  FeedActionsCubit(
    this.repository,
    this.account,
    this.isCurrent, {
    Duration Function()? elapsed,
    FeedPostSnapshotStore? postSnapshots,
    this.outbox,
  }) : publicationCache = FeedPublicationCache(
         store: postSnapshots,
         account: account,
       ),
       _elapsedOverride = elapsed,
       super((
         follows: const {},
         reactions: const {},
         busy: const {},
         hidden: const {},
         blocked: const {},
         reposts: const {},
         commentCounts: const {},
         accessVersion: 0,
       ));

  final IFeedPostRepository repository;
  final FeedCommentOutbox? outbox;
  final thumbnailFrames = FeedMediaFrames(maxBytes: 8 * 1024 * 1024);
  final FeedPublicationCache publicationCache;
  final _hiddenComments = <String>{};

  bool commentHidden(String id) => _hiddenComments.contains(id);

  void hideComment(String postId, String id) {
    _hiddenComments.add(id);
    publicationCache.updateComments(
      (_, page) => redactFeedCommentPage(page, comments: {id}),
      postId: postId,
    );
  }

  FeedCommentsPage redactComments(FeedCommentsPage page) =>
      _blocked.isEmpty && _hiddenComments.isEmpty
      ? page
      : redactFeedCommentPage(
          page,
          authors: _blocked,
          comments: _hiddenComments,
        );

  final AccountSessionSnapshot account;
  final bool Function() isCurrent;
  final _follows = <String, FeedFollowState>{};
  final _reactions = <String, FeedReaction>{};
  final _busy = <String>{};
  final _hidden = <String>{};
  final _reposts = <String, int>{};
  final _commentCounts = <String, FeedCommentCount>{};
  final _followWrites = <String, Object>{};
  final _recentToggles = <String, Duration>{};
  final _clock = Stopwatch()..start();
  final Duration Function()? _elapsedOverride;
  Duration get _elapsed => _elapsedOverride?.call() ?? _clock.elapsed;
  static const _toggleInterval = Duration(milliseconds: 350);
  Set<String> _blocked = const {};
  bool _detailOpening = false;
  bool _profileOpening = false;
  int _projectionVersion = 0;
  int _accessVersion = 0;
  int _lastReconnect = 0;
  bool _checkingFriends = false;
  final _projectionVersions = Expando<int>();
  final _friendshipChanges = <String, ({int changedAt, int removedAt})>{};
  final _blockedAt = <String, int>{};
  final _observedFriends = <String>{};

  bool get active => !isClosed && isCurrent();
  int get projectionVersion => _projectionVersion;

  bool canShow(FeedPost post) {
    if (!active) return false;
    for (FeedPost? item = post; item != null; item = item.original) {
      final blockedAt = _blockedAt[item.authorId];
      if (_hidden.contains(item.id) ||
          _blocked.contains(item.authorId) ||
          blockedAt != null && (_projectionVersions[item] ?? 0) < blockedAt ||
          item.friendsOnly && !_hasFriendAccess(item)) {
        return false;
      }
    }
    return true;
  }

  FeedCoordinates? coordinatesFor(FeedPost post) =>
      canShow(post) && _hasFriendAccess(post) ? post.coordinates : null;

  bool _hasFriendAccess(FeedPost post) =>
      post.authorId == account.userId ||
      (_projectionVersions[post] ?? 0) >=
          (_friendshipChanges[post.authorId]?.removedAt ?? 0);

  int commentCountFor(FeedPost post) {
    final count = state.commentCounts[post.id];
    return count != null && count.revision > (post.commentCountRevision ?? -1)
        ? count.count
        : post.commentCount;
  }

  void recordCommentCount(FeedPost post, FeedCommentCount count) {
    if (canShow(post)) recordDeliveredCommentCount(post.id, count);
  }

  void recordDeliveredCommentCount(String postId, FeedCommentCount count) {
    if (active &&
        !_hidden.contains(postId) &&
        _updateCommentCount(postId, count)) {
      _publish();
    }
  }

  bool _updateCommentCount(String id, FeedCommentCount count) {
    if (count.count < 0 ||
        count.revision <= (_commentCounts[id]?.revision ?? -1)) {
      return false;
    }
    _commentCounts.remove(id);
    _commentCounts[id] = count;
    return true;
  }

  void recordProjection(FeedPost post, int requestedAt) =>
      recordProjections([post], requestedAt);

  void recordProjections(Iterable<FeedPost> posts, int requestedAt) {
    if (!active) return;
    var countsChanged = false;
    for (final post in posts) {
      _recordProjectionAccess(post, requestedAt);
      for (FeedPost? item = post; item != null; item = item.original) {
        if (item.commentCountRevision case final revision? when canShow(item)) {
          if (_updateCommentCount(item.id, (
            count: item.commentCount,
            revision: revision,
          ))) {
            countsChanged = true;
          }
        }
      }
    }
    if (countsChanged) _publish();
  }

  void _recordProjectionAccess(FeedPost post, int requestedAt) {
    for (FeedPost? item = post; item != null; item = item.original) {
      final author = item.authorId;
      final sensitive =
          author != account.userId &&
          (item.friendsOnly || item.coordinates != null);
      // A response started before reconnection might contain an author absent
      // from the batch being rechecked. Require a new read for that projection.
      final missedCheck =
          sensitive &&
          requestedAt < _lastReconnect &&
          !_observedFriends.contains(author);
      _projectionVersions[item] = missedCheck ? -1 : requestedAt;
      if (sensitive &&
          _hasFriendAccess(item) &&
          requestedAt >= (_blockedAt[author] ?? 0)) {
        _observedFriends.add(author);
      }
    }
  }

  void hidePost(String id) {
    if (!active || !_hidden.add(id)) return;
    _publish();
    _evictMedia(postId: id);
  }

  bool beginDetail() {
    if (!active || _detailOpening) return false;
    _detailOpening = true;
    return true;
  }

  void endDetail() => _detailOpening = false;

  bool beginProfile() {
    if (!active || _profileOpening) return false;
    _profileOpening = true;
    return true;
  }

  void endProfile() => _profileOpening = false;

  void friendshipRemoved(String id) {
    if (!active) return;
    _markFriendshipRemoved(id);
    _publishAccessChange();
    _evictMedia(removedFriends: {id});
  }

  void _markFriendshipRemoved(String id) {
    final version = ++_projectionVersion;
    _friendshipChanges[id] = (changedAt: version, removedAt: version);
    _observedFriends.remove(id);
  }

  void friendshipAdded(String id) {
    if (!active) return;
    _friendshipChanges[id] = (
      changedAt: ++_projectionVersion,
      removedAt: _friendshipChanges[id]?.removedAt ?? 0,
    );
  }

  void peerBlocked(String id) {
    if (!active) return;
    _markPeerBlocked(id);
    _publishAccessChange();
    publicationCache.updateComments(
      (_, page) => redactFeedCommentPage(page, authors: {id}),
    );
    _evictMedia(blocked: {id});
  }

  void _markPeerBlocked(String id) {
    _followWrites.remove(id);
    _follows.remove(id);
    _markFriendshipRemoved(id);
    _blockedAt[id] = _projectionVersion;
  }

  Future<void> recheckFriendships(
    Future<Set<String>> Function(Set<String>) verify,
  ) async {
    if (!active) return;
    _lastReconnect = ++_projectionVersion;
    if (_checkingFriends) return;
    _checkingFriends = true;
    try {
      int reconnect;
      do {
        reconnect = _lastReconnect;
        final requestedAt = _projectionVersion;
        final authors = Set<String>.of(_observedFriends);
        final source = repository;
        if (source is FeedRepository) {
          authors.addAll(await source.cachedMediaFriends(account));
        }
        if (!active || reconnect != _lastReconnect) continue;
        if (authors.isEmpty) return;
        final Set<String> confirmed;
        try {
          confirmed = await verify(authors);
        } catch (_) {
          // A network failure gives no new access decision. Retain the last
          // confirmed projection and retry when the channel reconnects again.
          continue;
        }
        if (!active || reconnect != _lastReconnect) continue;
        final revoked = <String>{};
        for (final id in authors.difference(confirmed)) {
          if ((_friendshipChanges[id]?.changedAt ?? 0) > requestedAt) {
            continue;
          }
          _markFriendshipRemoved(id);
          revoked.add(id);
        }
        if (revoked.isNotEmpty) {
          _publishAccessChange();
          _evictMedia(removedFriends: revoked);
        }
      } while (active && reconnect != _lastReconnect);
    } finally {
      _checkingFriends = false;
    }
  }

  void _publishAccessChange() {
    _accessVersion++;
    _publish();
  }

  void setBlocked(Set<String> blocked) {
    if (!active ||
        _blocked.length == blocked.length && _blocked.containsAll(blocked)) {
      return;
    }
    final newlyBlocked = blocked.difference(_blocked);
    for (final id in newlyBlocked) {
      _markPeerBlocked(id);
    }
    _blocked = Set.unmodifiable(blocked);
    _publish();
    if (newlyBlocked.isNotEmpty) {
      publicationCache.updateComments(
        (_, page) => redactFeedCommentPage(page, authors: newlyBlocked),
      );
      _evictMedia(blocked: newlyBlocked);
    }
  }

  void _evictMedia({
    String? postId,
    Set<String> blocked = const {},
    Set<String> removedFriends = const {},
  }) {
    final source = repository;
    if (source is! FeedRepository) return;
    unawaited(
      source.evictMedia(
        account,
        postId: postId,
        blocked: blocked,
        removedFriends: removedFriends,
      ),
    );
  }

  FeedFollowState? followFor(FeedPost post) {
    final saved = state.follows[post.authorId];
    final incoming = post.follow;
    return saved != null &&
            (incoming == null || saved.version >= incoming.version)
        ? saved
        : incoming;
  }

  FeedReaction reactionFor(FeedPost post) {
    final saved = state.reactions[post.id];
    return saved != null && saved.version > post.reaction.version
        ? saved
        : post.reaction;
  }

  Future<void> toggleFollow(FeedPost post) async {
    final id = post.authorId;
    final current = followFor(post);
    if (id == account.userId ||
        current == null ||
        !current.canFollow && !current.following) {
      return;
    }
    await _run(post, 'author:$id', throttle: true, (requestId) async {
      final write = _followWrites[id] = Object();
      bool valid() => active && identical(_followWrites[id], write);
      try {
        final result = await _retry(
          () => repository.setFollow(id, current, requestId, account),
          canRetry: valid,
        );
        if (valid()) _follows[id] = result;
      } catch (error) {
        if (valid() && _shouldReconcile(error)) {
          try {
            final result = await repository.getFollow(id, account);
            if (valid()) _follows[id] = result;
          } catch (_) {
            // The next feed snapshot can reconcile the relationship.
          }
        }
        rethrow;
      } finally {
        if (valid()) _followWrites.remove(id);
      }
    });
  }

  Future<void> act(FeedPost post, {bool lessSimilar = false}) async {
    final delivery = post.delivery;
    if (delivery == null) return;
    await _run(post, post.id, throttle: !lessSimilar, (requestId) async {
      var current = reactionFor(post);
      var receipt = delivery;
      final action = lessSimilar
          ? FeedPostAction.lessSimilar
          : current.liked
          ? FeedPostAction.unlike
          : FeedPostAction.like;
      if (!receipt.expiresAt.isAfter(DateTime.now())) {
        if (lessSimilar) throw StateError('Recommendation delivery expired');
        final refreshed = await repository.getPost(post.id, account);
        if (!canShow(post)) return;
        if (refreshed?.delivery == null) {
          _hidden.add(post.id);
          return;
        }
        current = refreshed!.reaction;
        receipt = refreshed.delivery!;
        if (current.liked == (action == FeedPostAction.like)) {
          _reactions[post.id] = current;
          return;
        }
      }
      try {
        final result = await _retry(
          () => repository.act(
            receipt,
            action,
            current.version,
            requestId,
            account,
          ),
          canRetry: () => canShow(post),
        );
        if (!canShow(post)) return;
        final delta = result.liked == current.liked
            ? 0
            : result.liked
            ? 1
            : -1;
        _reactions[post.id] = (
          version: result.version,
          liked: result.liked,
          likes: (current.likes + delta).clamp(0, 1 << 53),
        );
        if (lessSimilar) _hidden.add(post.id);
      } catch (error) {
        if (active &&
            !_blocked.contains(post.authorId) &&
            _shouldReconcile(error)) {
          try {
            final refreshed = await repository.getPost(post.id, account);
            if (active && refreshed == null) _hidden.add(post.id);
            if (active &&
                !_blocked.contains(post.authorId) &&
                refreshed != null) {
              _reactions[post.id] = refreshed.reaction;
            }
          } catch (_) {
            // Keep the last acknowledged state.
          }
        }
        rethrow;
      }
    });
  }

  Future<void> report(FeedPost post, FeedReportReason reason) =>
      _run(post, post.id, (requestId) async {
        await _retry(
          () => repository.report(post.id, reason, requestId, account),
        );
        if (active) _hidden.add(post.id);
      });

  Future<void> repost(FeedPost post) => _run(post, post.id, (requestId) async {
    if (post.reposted || _reposts.containsKey(post.id)) return;
    await _retry(() => repository.repost(post.id, requestId, account));
    if (active) _reposts[post.id] = post.repostCount + 1;
  });

  Future<void> _run(
    FeedPost post,
    String key,
    Future<void> Function(String) run, {
    bool throttle = false,
  }) async {
    final now = _elapsed;
    _recentToggles.removeWhere((_, until) => until <= now);
    if (!active ||
        _blocked.contains(post.authorId) ||
        _hidden.contains(post.id) ||
        throttle && _recentToggles.containsKey(key) ||
        !_busy.add(key)) {
      return;
    }
    _publish();
    try {
      await run(const Uuid().v4());
    } finally {
      _busy.remove(key);
      if (active) {
        if (throttle) _recentToggles[key] = _elapsed + _toggleInterval;
        _publish();
      }
    }
  }

  Future<T> _retry<T>(
    Future<T> Function() send, {
    bool Function()? canRetry,
  }) async {
    try {
      return await send();
    } on TimeoutException {
      if (!active || canRetry?.call() == false) rethrow;
      return send();
    }
  }

  bool _shouldReconcile(Object error) =>
      error is TimeoutException ||
      error is PostgrestException &&
          (error.code == 'PT409' ||
              error.message == 'delivery_expired_or_invalidated');

  void _publish() {
    if (state.hidden.length != _hidden.length ||
        !identical(state.blocked, _blocked) ||
        state.accessVersion != _accessVersion) {
      thumbnailFrames.removeUnavailable(canShow);
      publicationCache.clear();
      publicationCache.removeUnavailablePosts(canShow);
    }
    _trim(_follows);
    _trim(_reactions);
    _trim(_reposts);
    _trim(_commentCounts);
    emit((
      follows: Map.unmodifiable(_follows),
      reactions: Map.unmodifiable(_reactions),
      busy: Set.unmodifiable(_busy),
      hidden: Set.unmodifiable(_hidden),
      blocked: _blocked,
      reposts: Map.unmodifiable(_reposts),
      commentCounts: Map.unmodifiable(_commentCounts),
      accessVersion: _accessVersion,
    ));
  }

  @override
  Future<void> close() {
    thumbnailFrames.clear();
    publicationCache.clear();
    _hiddenComments.clear();
    return super.close();
  }

  void _trim<T>(Map<String, T> values) {
    while (values.length > 500) {
      values.remove(values.keys.first);
    }
  }
}
