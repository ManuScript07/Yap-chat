import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_actions_cubit.dart';

typedef FeedCommentsState = ({
  List<FeedComment> rows,
  bool loading,
  bool failed,
  bool hasMore,
});

class FeedCommentsCubit extends Cubit<FeedCommentsState> {
  FeedCommentsCubit(this.repository, this.actions, this.post)
    : super((rows: const [], loading: false, failed: false, hasMore: true));

  final IFeedPublicationRepository repository;
  final FeedActionsCubit actions;
  final FeedPost post;
  final _rows = <String, FeedComment>{};
  final _sent = <String, FeedComment>{};
  FeedCommentsCursor? _cursor;
  (String, String)? _pending;
  bool _submitting = false;
  bool _loading = false;
  bool _failed = false;
  bool _more = true;
  int _revision = 0;

  bool get _active => !isClosed && actions.canShow(post);

  Future<void> next() async {
    if (!_active || _loading || !_more) return;
    final revision = _revision;
    _loading = true;
    _failed = false;
    _publish();
    try {
      final page = await repository.getComments(
        post.id,
        actions.account,
        cursor: _cursor,
      );
      if (!_active || revision != _revision) return;
      _more = page.next != null && page.next != _cursor;
      _cursor = page.next;
      for (final row in page.comments) {
        if (actions.state.blocked.contains(row.authorId)) continue;
        _rows.putIfAbsent(row.id, () => row);
      }
    } catch (error) {
      _handleAccessError(error);
      if (revision == _revision) {
        if (error is PostgrestException && error.code == 'PT410') {
          _cursor = null;
        }
        _failed = true;
      }
    } finally {
      _loading = false;
      if (revision == _revision) {
        _publish();
      } else if (_active) {
        unawaited(next());
      }
    }
  }

  void invalidateAccess() {
    if (!_active) return;
    _revision++;
    _rows.clear();
    _cursor = null;
    _more = true;
    if (_loading) {
      _publish();
    } else {
      unawaited(next());
    }
  }

  Future<bool> submit(String text) async {
    if (!_active ||
        _submitting ||
        text.trim().isEmpty ||
        text.runes.length > 200) {
      return false;
    }
    _submitting = true;
    final pending = _pending;
    final requestId = pending?.$1 == text ? pending!.$2 : const Uuid().v4();
    _pending = (text, requestId);
    try {
      final comment = await repository.createComment(
        post.id,
        requestId,
        text,
        actions.account,
      );
      if (!_active) return false;
      _pending = null;
      _sent[comment.id] = comment;
      _publish();
      return true;
    } catch (error) {
      _handleAccessError(error);
      rethrow;
    } finally {
      _submitting = false;
    }
  }

  void _handleAccessError(Object error) {
    if (_active &&
        error is PostgrestException &&
        error.code == 'PT404' &&
        error.message == 'post_not_found') {
      actions.hidePost(post.id);
    }
  }

  void _publish() {
    if (!_active) return;
    emit((
      rows: List.unmodifiable([
        ..._sent.values.toList().reversed,
        for (final row in _rows.values)
          if (!_sent.containsKey(row.id)) row,
      ]),
      loading: _loading,
      failed: _failed,
      hasMore: _more,
    ));
  }
}
