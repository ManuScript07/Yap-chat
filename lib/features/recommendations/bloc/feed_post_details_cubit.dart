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
  FeedPostDetailsCubit(this.id, this.actions, FeedPost? initial)
    : super((post: initial, loading: false, confirmed: false, failed: false));

  final String id;
  final FeedActionsCubit actions;
  Future<void>? _request;

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
    try {
      final post = await actions.repository.getPost(id, actions.account);
      if (!_active) return;
      if (post != null) actions.recordProjection(post, requestedAt);
      final allowed = post != null && actions.canShow(post);
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
}
