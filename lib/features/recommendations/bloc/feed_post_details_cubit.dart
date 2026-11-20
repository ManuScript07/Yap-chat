import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_actions_cubit.dart';
import 'feed_comments_cubit.dart';

typedef FeedPostDetailsState = ({
  FeedPost? post,
  bool loading,
  bool confirmed,
  bool failed,
});

class FeedPostDetailsCubit extends Cubit<FeedPostDetailsState> {
  factory FeedPostDetailsCubit(
    String id,
    FeedActionsCubit actions,
    FeedPost? initial, {
    ValueListenable<bool?>? networkAvailability,
    IFeedPublicationRepository? publicationRepository,
  }) {
    final cached = actions.publicationCache.readPost(id);
    final cachedPost = cached?.post;
    final usable = cachedPost != null && actions.canShow(cachedPost);
    return FeedPostDetailsCubit._(
      id,
      actions,
      initial ?? (usable ? cachedPost : null),
      usable ? cached?.expiresAt : null,
      networkAvailability,
      publicationRepository,
    );
  }

  FeedPostDetailsCubit._(
    this.id,
    this.actions,
    FeedPost? initial,
    this._snapshotExpiresAt,
    this._networkAvailability,
    this._publicationRepository,
  ) : super((post: initial, loading: false, confirmed: false, failed: false)) {
    _lastNetworkAvailability = _networkAvailability?.value;
    _networkAvailability?.addListener(_networkChanged);
    if (initial != null) _updateComments(initial, confirmed: false);
  }

  final String id;
  final FeedActionsCubit actions;
  final ValueListenable<bool?>? _networkAvailability;
  final IFeedPublicationRepository? _publicationRepository;
  final refreshProgress = ValueNotifier(false);
  final _visibleThreads = <String>{};
  final _clock = Stopwatch()..start();
  Duration? _lastInteractive;
  FeedCommentsCubit? _comments;
  FeedCommentsCubit? get comments => _comments;
  bool? _lastNetworkAvailability;
  DateTime? _snapshotExpiresAt;
  Future<void>? _request;
  Timer? _expiry;
  int _readGeneration = 0;

  Future<void> load({Set<String>? visibleThreads, bool accessOnly = false}) {
    if (!_active) return Future.value();
    final pending = _request;
    if (visibleThreads != null) {
      final last = _lastInteractive;
      if (pending == null &&
          last != null &&
          _clock.elapsed - last < const Duration(milliseconds: 500)) {
        return Future.value();
      }
      _visibleThreads.addAll(visibleThreads);
      refreshProgress.value = true;
    }
    if (pending != null) return pending;
    final completion = Completer<void>();
    _request = completion.future;
    completion.complete(
      _refresh(accessOnly).whenComplete(() {
        _request = null;
        _visibleThreads.clear();
        if (_active && refreshProgress.value) {
          _lastInteractive = _clock.elapsed;
          refreshProgress.value = false;
        }
      }),
    );
    return completion.future;
  }

  Future<void> _refresh(bool accessOnly) async {
    if (!await _read() || !_active) return;
    final threadIds = Set<String>.of(_visibleThreads);
    final replies = comments;
    if (replies == null) return;
    if (!accessOnly || refreshProgress.value || !replies.state.loaded) {
      await replies.refresh(
        interactive: refreshProgress.value,
        visibleThreads: threadIds,
      );
    }
    if (!_active) return;
    final remaining = _visibleThreads.difference(threadIds);
    if (remaining.isNotEmpty) {
      await replies.refresh(
        interactive: true,
        visibleThreads: remaining,
        includeRoot: false,
      );
    }
  }

  void _updateComments(FeedPost post, {required bool confirmed}) {
    final repository = _publicationRepository;
    if (repository == null) return;
    final cubit = _comments ??= FeedCommentsCubit(
      repository,
      actions,
      post,
      networkAvailable: () => _networkAvailability?.value,
      autoLoad: false,
    );
    cubit.updatePost(post, confirmed: confirmed);
  }

  void _discardComments() {
    final previous = _comments;
    _comments = null;
    unawaited(previous?.close());
  }

  bool get _active => !isClosed && actions.active;

  void _networkChanged() {
    final previouslyUnavailable = _lastNetworkAvailability == false;
    _lastNetworkAvailability = _networkAvailability?.value;
    if (previouslyUnavailable && _lastNetworkAvailability == true) {
      unawaited(_recheckAfterReconnect());
    }
  }

  Future<void> _recheckAfterReconnect() async {
    await _request;
    if (_active &&
        _lastNetworkAvailability == true &&
        state.failed &&
        !state.confirmed) {
      await load(accessOnly: true);
    }
  }

  Future<bool> _read() async {
    if (!_active) return false;
    emit((
      post: state.post,
      loading: true,
      confirmed: state.confirmed,
      failed: state.failed && refreshProgress.value,
    ));
    final requestedAt = actions.projectionVersion;
    final generation = ++_readGeneration;
    final restoring = state.post == null ? _restore(generation) : null;
    _scheduleExpiry();
    try {
      final post = await actions.repository.getPost(id, actions.account);
      if (!_active) return false;
      if (post != null) actions.recordProjection(post, requestedAt);
      final allowed = post != null && actions.canShow(post);
      _expiry?.cancel();
      _expiry = null;
      if (allowed) {
        actions.publicationCache.writePost(
          post,
          allowed: () => actions.canShow(post),
        );
        _updateComments(post, confirmed: true);
      } else {
        actions.publicationCache.removePost(id);
        _discardComments();
      }
      emit((
        post: allowed ? post : null,
        loading: false,
        confirmed: allowed,
        failed: false,
      ));
      return allowed;
    } catch (error) {
      if (!_active) return false;
      final denied =
          error is PostgrestException &&
          const {'PT401', 'PT403', 'PT404', '42501'}.contains(error.code);
      if (denied) {
        _expiry?.cancel();
        _expiry = null;
        actions.publicationCache.removePost(id);
        _discardComments();
      } else {
        await restoring;
        if (!_active) return false;
      }
      final retained = state.post;
      final allowed = !denied && retained != null && actions.canShow(retained);
      emit((
        post: allowed ? retained : null,
        loading: false,
        confirmed: allowed && state.confirmed,
        failed: !denied,
      ));
      return false;
    }
  }

  Future<void> _restore(int generation) async {
    final snapshot = await actions.publicationCache.restorePost(id);
    if (snapshot == null ||
        !_active ||
        generation != _readGeneration ||
        !state.loading ||
        state.post != null ||
        !actions.canShow(snapshot.post)) {
      return;
    }
    _snapshotExpiresAt = snapshot.expiresAt;
    actions.publicationCache.rememberPost(snapshot);
    _updateComments(snapshot.post, confirmed: false);
    emit((post: snapshot.post, loading: true, confirmed: false, failed: false));
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    final expires = _snapshotExpiresAt;
    if (state.confirmed || state.post == null || expires == null) return;
    _expiry ??= Timer(expires.difference(DateTime.now()), () {
      _expiry = null;
      if (_active && !state.confirmed) {
        _discardComments();
        emit((
          post: null,
          loading: state.loading,
          confirmed: false,
          failed: state.failed,
        ));
      }
    });
  }

  @override
  Future<void> close() {
    _networkAvailability?.removeListener(_networkChanged);
    _expiry?.cancel();
    _discardComments();
    refreshProgress.dispose();
    return super.close();
  }
}
