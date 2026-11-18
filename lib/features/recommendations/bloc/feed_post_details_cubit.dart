import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_actions_cubit.dart';

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
    FeedPost? initial,
  ) {
    final cached = actions.publicationCache.readPost(id);
    final cachedPost = cached?.post;
    final usable = cachedPost != null && actions.canShow(cachedPost);
    return FeedPostDetailsCubit._(
      id,
      actions,
      initial ?? (usable ? cachedPost : null),
      usable ? cached?.expiresAt : null,
    );
  }

  FeedPostDetailsCubit._(
    this.id,
    this.actions,
    FeedPost? initial,
    this._snapshotExpiresAt,
  ) : super((post: initial, loading: false, confirmed: false, failed: false));

  final String id;
  final FeedActionsCubit actions;
  final DateTime? _snapshotExpiresAt;
  Future<void>? _request;
  Timer? _expiry;

  Future<void> load() =>
      _request ??= _read().whenComplete(() => _request = null);

  bool get _active => !isClosed && actions.active;

  Future<void> _read() async {
    if (!_active) return;
    emit((
      post: state.post,
      loading: true,
      confirmed: state.confirmed,
      failed: false,
    ));
    final requestedAt = actions.projectionVersion;
    final expires = _snapshotExpiresAt;
    if (!state.confirmed && state.post != null && expires != null) {
      _expiry ??= Timer(expires.difference(DateTime.now()), () {
        if (_active && !state.confirmed) {
          emit((
            post: null,
            loading: state.loading,
            confirmed: false,
            failed: state.failed,
          ));
        }
      });
    }
    try {
      final post = await actions.repository.getPost(id, actions.account);
      if (!_active) return;
      if (post != null) actions.recordProjection(post, requestedAt);
      final allowed = post != null && actions.canShow(post);
      _expiry?.cancel();
      _expiry = null;
      if (allowed) {
        actions.publicationCache.writePost(post);
      } else {
        actions.publicationCache.removePost(id);
      }
      emit((
        post: allowed ? post : null,
        loading: false,
        confirmed: allowed,
        failed: false,
      ));
    } catch (error) {
      if (!_active) return;
      final denied =
          error is PostgrestException &&
          const {'PT401', 'PT403', 'PT404', '42501'}.contains(error.code);
      if (denied) {
        _expiry?.cancel();
        _expiry = null;
        actions.publicationCache.removePost(id);
      }
      final retained = state.post;
      final allowed = !denied && retained != null && actions.canShow(retained);
      emit((
        post: allowed ? retained : null,
        loading: false,
        confirmed: allowed && state.confirmed,
        failed: !denied,
      ));
    }
  }

  @override
  Future<void> close() {
    _expiry?.cancel();
    return super.close();
  }
}
