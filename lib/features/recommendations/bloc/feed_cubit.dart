import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_state.dart';
import 'feed_actions_cubit.dart';

/// The screen owns one timeline per tab. Only the selected timeline can start
/// new work, and a refresh supersedes any in-flight continuation.
class FeedCubit extends Cubit<FeedState> {
  FeedCubit({
    required this.tab,
    required this.repository,
    required this.isCurrentAccount,
    required this.account,
    this.actions,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const FeedState());

  static const _freshFor = Duration(minutes: 1);
  static const _refreshCooldown = Duration(seconds: 2);
  static const _emptyPageBudget = 3;

  final FeedTab tab;
  final IFeedRepository repository;
  final AccountSessionSnapshot account;
  final FeedActionsCubit? actions;
  final bool Function() isCurrentAccount;
  final DateTime Function() _now;
  final _posts = <FeedPost>[];
  final _indexes = <String, int>{};
  FeedRows _rows = const FeedRows.empty();
  Set<String> _expandedIds = const {};
  final _seenCursors = <FeedCursor>{};
  Set<String> _blockedAuthors = const {};

  FeedCursor? _cursor;
  DateTime? _expiresAt;
  DateTime? _headLoadedAt;
  DateTime? _lastRefresh;
  Future<void>? _refresh;
  Future<void>? _append;
  Object? _failure;
  bool _failedRefresh = false;
  bool _active = false;
  bool _loaded = false;
  bool _restricted = false;
  bool _serverRequiresLocation = false;
  bool _restart = false;
  bool _refreshOnReturn = false;
  int _generation = 0;

  bool get _canContinue => _cursor != null || _restart;

  void hidePosts(Set<String> ids) =>
      _removePosts((post) => ids.contains(post.id));

  void removeInaccessiblePosts() => _removePosts((post) => !_canShow(post));

  bool _canShow(FeedPost post) =>
      !_blockedAuthors.contains(post.authorId) &&
      (actions?.canShow(post) ?? true);

  void _removePosts(bool Function(FeedPost) shouldRemove) {
    if (isClosed) return;
    final count = _posts.length;
    _posts.removeWhere(shouldRemove);
    if (_posts.length == count) return;
    _indexes.clear();
    for (final (index, post) in _posts.indexed) {
      _indexes[post.id] = index;
    }
    _pruneExpanded();
    _snapshotRows();
    _publish();
  }

  void deactivate() => _active = false;

  Future<void> activate({required bool atTop}) {
    if (isClosed) return Future.value();
    _active = true;
    final headLoadedAt = _headLoadedAt;
    if (_refreshOnReturn ||
        !_loaded && _failure == null ||
        atTop &&
            headLoadedAt != null &&
            _now().difference(headLoadedAt) >= _freshFor) {
      _refreshOnReturn = false;
      return refresh();
    }
    return Future.value();
  }

  Future<void> refresh({bool force = false}) {
    if (!_canStart) return Future.value();
    final pending = _refresh;
    if (pending != null) return pending;
    final now = _now();
    final previous = _lastRefresh;
    if (!force &&
        previous != null &&
        now.difference(previous) < _refreshCooldown) {
      return Future.value();
    }
    _lastRefresh = now;
    _append = null;
    final generation = ++_generation;
    return _run(generation, replacing: true, startsAtHead: true);
  }

  Future<void> loadMore({bool retry = false}) {
    if (!_canStart ||
        _refresh != null ||
        !_canContinue ||
        _failure != null && !retry) {
      return Future.value();
    }
    final pending = _append;
    if (pending != null) return pending;
    final expiry = _expiresAt;
    final startsAtHead = _restart || expiry != null && !_now().isBefore(expiry);
    return _run(_generation, replacing: false, startsAtHead: startsAtHead);
  }

  Future<void> retry() => _failedRefresh || !_canContinue
      ? refresh(force: true)
      : loadMore(retry: true);

  bool get _canStart =>
      !isClosed && _active && !_restricted && isCurrentAccount();
  bool _isCurrent(int generation) =>
      !isClosed && generation == _generation && isCurrentAccount();

  Future<void> _run(
    int generation, {
    required bool replacing,
    required bool startsAtHead,
  }) {
    _failure = null;
    _failedRefresh = false;
    final operation = Future<void>.microtask(() async {
      try {
        if (_isCurrent(generation) && _active) {
          await _fetchPages(
            generation,
            replacing: replacing,
            startsAtHead: startsAtHead,
          );
        }
      } finally {
        if (_isCurrent(generation)) {
          if (replacing) {
            _refresh = null;
          } else {
            _append = null;
          }
          _publish();
        }
      }
    });
    if (replacing) {
      _refresh = operation;
    } else {
      _append = operation;
    }
    _publish();
    return operation;
  }

  Future<void> _fetchPages(
    int generation, {
    required bool replacing,
    required bool startsAtHead,
  }) async {
    var cursor = startsAtHead ? null : _cursor;
    var replaceRows = replacing;
    var restarted = startsAtHead;
    for (var request = 0; request < _emptyPageBudget; request++) {
      final FeedPageResult page;
      final accessVersion = actions?.projectionVersion;
      try {
        page = await repository.fetch(tab, account: account, cursor: cursor);
      } catch (error) {
        if (!_isCurrent(generation)) return;
        if (error == FeedFailure.sessionInvalidated) _clearRows();
        if ((error == FeedFailure.sessionExpired ||
                error == FeedFailure.sessionInvalidated) &&
            !restarted) {
          restarted = true;
          cursor = null;
          _restart = true;
          if (_active) continue;
        }
        if (error is StaleAccountSessionException ||
            error == FeedFailure.accessDenied) {
          _clearRows();
          _cursor = null;
          _restart = false;
        }
        if (error == FeedFailure.locationRequired && tab == FeedTab.nearby) {
          _serverRequiresLocation = true;
          _restricted = true;
          _cursor = null;
          _restart = false;
        }
        _failure = error;
        _failedRefresh = replacing;
        return;
      }
      if (!_isCurrent(generation)) return;
      if (accessVersion != null) {
        actions!.recordProjections(page.posts, accessVersion);
      }

      final atHead = cursor == null;
      if (atHead) {
        _seenCursors.clear();
        _headLoadedAt = _now();
      }
      final next = page.nextCursor;
      _cursor = next != null && next != cursor && _seenCursors.add(next)
          ? next
          : null;
      _expiresAt = page.expiresAt;
      _restart = false;
      _loaded = true;
      if (replaceRows &&
          _cursor != null &&
          _active &&
          request + 1 < _emptyPageBudget &&
          !page.posts.any(_canShow)) {
        cursor = _cursor;
        continue;
      }
      final changed = _apply(page.posts, replace: replaceRows);
      replaceRows = false;
      if (changed || _cursor == null || !_active) return;
      cursor = _cursor;
    }
  }

  bool _apply(List<FeedPost> incoming, {required bool replace}) {
    final previousLength = _posts.length;
    if (replace) {
      _posts.clear();
      _indexes.clear();
    }
    for (final post in incoming) {
      if (!_canShow(post) || _indexes.containsKey(post.id)) {
        continue;
      }
      _indexes[post.id] = _posts.length;
      _posts.add(post);
    }
    if (replace) _pruneExpanded();
    final changed = replace
        ? previousLength != 0 || _posts.isNotEmpty
        : _posts.length != previousLength;
    if (changed) _snapshotRows();
    return _posts.isNotEmpty && changed;
  }

  void updateBlockedAuthors(Set<String> blocked) {
    if (isClosed) return;
    final changed = !setEquals(_blockedAuthors, blocked);
    _blockedAuthors = Set.unmodifiable(blocked);
    if (changed) removeInaccessiblePosts();
  }

  void _invalidateNearbyRequest() {
    _generation++;
    _refresh = null;
    _append = null;
    _cursor = null;
    _restart = false;
    _loaded = false;
    _lastRefresh = null;
    _refreshOnReturn = true;
    _publish();
  }

  void setLocationAllowed(bool allowed, {bool newerPublication = false}) {
    if (isClosed) return;
    if (newerPublication) _serverRequiresLocation = false;
    if (allowed && _serverRequiresLocation) return;
    if (_restricted == !allowed) return;
    _restricted = !allowed;
    if (!allowed) {
      _failure = FeedFailure.locationRequired;
      _invalidateNearbyRequest();
    } else {
      _failure = null;
      _lastRefresh = null;
      _refreshOnReturn = true;
    }
  }

  Future<void> locationUpdated() {
    setLocationAllowed(true, newerPublication: true);
    _refreshOnReturn = !_active;
    return refresh(force: true);
  }

  void _clearRows() {
    if (_posts.isEmpty) return;
    _posts.clear();
    _indexes.clear();
    _expandedIds = const {};
    _rows = const FeedRows.empty();
    _publish();
  }

  void toggleExpanded(String postId) {
    if (isClosed || !_indexes.containsKey(postId)) return;
    final expanded = {..._expandedIds};
    if (!expanded.remove(postId)) expanded.add(postId);
    _expandedIds = Set.unmodifiable(expanded);
    _publish();
  }

  void _pruneExpanded() {
    if (_expandedIds.every(_indexes.containsKey)) return;
    _expandedIds = Set.unmodifiable(_expandedIds.where(_indexes.containsKey));
  }

  void _snapshotRows() => _rows = FeedRows(_posts, _indexes);

  void _publish() => emit(
    FeedState(
      rows: _rows,
      expandedIds: _expandedIds,
      loading: _refresh != null || _append != null,
      appending: _append != null,
      loaded: _loaded,
      canContinue: _canContinue,
      failure: _failure,
    ),
  );
}
