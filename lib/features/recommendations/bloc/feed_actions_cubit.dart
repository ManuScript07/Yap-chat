import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

typedef FeedActionsState = ({
  Map<String, FeedFollowState> follows,
  Map<String, FeedReaction> reactions,
  Set<String> busy,
  Set<String> hidden,
  Set<String> blocked,
  Map<String, int> reposts,
  String? revokedAuthor,
});

class FeedActionsCubit extends Cubit<FeedActionsState> {
  FeedActionsCubit(
    this.repository,
    this.account,
    this.isCurrent, {
    Duration Function()? elapsed,
  }) : _elapsedOverride = elapsed,
       super((
         follows: const {},
         reactions: const {},
         busy: const {},
         hidden: const {},
         blocked: const {},
         reposts: const {},
         revokedAuthor: null,
       ));

  final IFeedPostRepository repository;
  final AccountSessionSnapshot account;
  final bool Function() isCurrent;
  final _follows = <String, FeedFollowState>{};
  final _reactions = <String, FeedReaction>{};
  final _busy = <String>{};
  final _hidden = <String>{};
  final _reposts = <String, int>{};
  final _followWrites = <String, Object>{};
  final _recentToggles = <String, Duration>{};
  final _clock = Stopwatch()..start();
  final Duration Function()? _elapsedOverride;
  Duration get _elapsed => _elapsedOverride?.call() ?? _clock.elapsed;
  static const _toggleInterval = Duration(milliseconds: 350);
  Set<String> _blocked = const {};
  bool _detailOpening = false;
  String? _revokedAuthor;

  bool get active => !isClosed && isCurrent();
  bool canShow(FeedPost post) =>
      active && !_blocked.contains(post.authorId) && !_hidden.contains(post.id);

  void hidePost(String id) {
    if (active && _hidden.add(id)) _publish();
  }

  bool beginDetail() {
    if (!active || _detailOpening) return false;
    _detailOpening = true;
    return true;
  }

  void endDetail() => _detailOpening = false;

  void revalidateAuthor(String id) {
    if (!active) return;
    _followWrites.remove(id);
    _follows.remove(id);
    _revokedAuthor = id;
    _publish();
    _revokedAuthor = null;
  }

  void setBlocked(Set<String> blocked) {
    if (!active ||
        _blocked.length == blocked.length && _blocked.containsAll(blocked)) {
      return;
    }
    _blocked = Set.unmodifiable(blocked);
    _follows.removeWhere((id, _) => blocked.contains(id));
    _followWrites.removeWhere((id, _) => blocked.contains(id));
    _publish();
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
    _trim(_follows);
    _trim(_reactions);
    _trim(_reposts);
    emit((
      follows: Map.unmodifiable(_follows),
      reactions: Map.unmodifiable(_reactions),
      busy: Set.unmodifiable(_busy),
      hidden: Set.unmodifiable(_hidden),
      blocked: _blocked,
      reposts: Map.unmodifiable(_reposts),
      revokedAuthor: _revokedAuthor,
    ));
  }

  void _trim<T>(Map<String, T> values) {
    while (values.length > 500) {
      values.remove(values.keys.first);
    }
  }
}
