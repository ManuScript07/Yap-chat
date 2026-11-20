import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_actions_cubit.dart';

typedef FeedCommentsState = ({
  List<FeedComment> rows,
  FeedCommentSort sort,
  bool loading,
  bool failed,
  bool loaded,
  bool hasMore,
});

class _CommentPage {
  _CommentPage(this.sort, this.root, [CachedFeedComments? cached]) {
    if (cached != null) {
      rows.addEntries(cached.page.comments.map((row) => MapEntry(row.id, row)));
      started = true;
      cursor = cached.page.next;
      more = cursor != null;
      expiresAt = cached.expiresAt;
    }
  }

  final FeedCommentSort sort;
  final String? root;
  final rows = <String, FeedComment>{};
  FeedCommentsCursor? cursor;
  DateTime? expiresAt;
  DateTime? replacedFrom;
  Future<void>? pending;
  Future<void>? revalidation;
  bool started = false;
  bool loading = false;
  bool failed = false;
  bool failedRefresh = false;
  bool readingHead = false;
  bool silent = false;
  int request = 0;
  bool more = true;
  _CommentRefresh? replacement;
}

// The replacement cursor belongs only to the unpublished server order.
class _CommentRefresh {
  _CommentRefresh(this.startedAt);

  final Duration startedAt;
  final rows = <String, FeedComment>{};
  final cursors = <FeedCommentsCursor>{};
  FeedCommentsCursor? next;
}

class FeedCommentsCubit extends Cubit<FeedCommentsState> {
  FeedCommentsCubit(
    this.repository,
    this.actions,
    this._post, {
    this._networkAvailable,
    this._autoLoad = true,
  }) : super((
         rows: const [],
         sort: FeedCommentSort.popular,
         loading: false,
         failed: false,
         loaded: false,
         hasMore: true,
       ));

  final IFeedPublicationRepository repository;
  final FeedActionsCubit actions;
  final bool? Function()? _networkAvailable;
  final bool _autoLoad;
  FeedPost _post;
  final _roots = <FeedCommentSort, _CommentPage>{};
  final _threads = <String, _CommentPage>{};
  final _sent = <String, FeedComment>{};
  Map<String, FeedCommentOutboxEntry> _queued = const {};
  StreamSubscription<List<FeedCommentOutboxEntry>>? _outboxSubscription;
  final _reactions = <String, FeedReaction>{};
  final _busy = <String>{};
  final _recentActions = <String, Duration>{};
  final _clock = Stopwatch()..start();
  ({String text, String? replyTo, String id})? _pending;
  bool _ready = false;
  bool _hydrated = false;
  bool _restoring = false;
  Future<void>? _restoreRequest;
  bool _hasCachedPages = false;
  bool _submitting = false;
  int _revision = 0;
  Map<String?, String> Function()? visibleAnchors;
  Timer? _cacheExpiry;
  DateTime? _offlineUntil;
  FeedCommentSort _sort = FeedCommentSort.popular;

  bool get _cachedPostWritable =>
      actions.outbox != null && _offlineUntil?.isAfter(DateTime.now()) == true;
  bool get canDisplay => _ready || _hasCachedPages || _cachedPostWritable;
  bool get canMutate => _ready && _active;
  bool get canSubmit => _active && (_ready || _cachedPostWritable);
  bool get needsHeadRetry =>
      _root.failed && (!_root.started || _root.failedRefresh);
  bool get _active => canDisplay && !isClosed && actions.canShow(_post);
  _CommentPage get _root => _roots.putIfAbsent(_sort, () => _page(_sort, null));

  _CommentPage _page(FeedCommentSort sort, String? root) => _CommentPage(
    sort,
    root,
    actions.publicationCache.read((_post.id, sort, root)),
  );

  void updatePost(
    FeedPost post, {
    required bool confirmed,
    DateTime? offlineUntil,
  }) {
    _post = post;
    _offlineUntil = offlineUntil;
    if (!_hydrated) {
      _hydrated = true;
      _outboxSubscription = actions.outbox
          ?.watch(actions.account, post.id)
          .listen(_acceptOutbox, onError: (Object _) {});
      final cache = actions.publicationCache;
      _applySnapshots(cache.readForPost(post.id));
      if (cache.hasDisk) {
        _restoring = true;
        unawaited(_restoreRequest = _restore(post.id, _revision));
      }
    }
    if (_ready || !confirmed) return;
    _ready = true;
    _cacheExpiry?.cancel();
    if (_autoLoad && !_restoring && !_root.started) unawaited(next());
  }

  void _acceptOutbox(List<FeedCommentOutboxEntry> entries) {
    if (isClosed ||
        !actions.canShow(_post) ||
        entries.isEmpty && _queued.isEmpty) {
      return;
    }
    _queued = {for (final entry in entries) entry.id: entry};
    for (final entry in entries) {
      if (entry.receipt?.postCount case final count?) {
        actions.recordCommentCount(_post, count);
      }
      if (entry.rootId case final root?) {
        _threads.putIfAbsent(root, () => _page(FeedCommentSort.old, root));
      }
    }
    _publish();
  }

  Iterable<FeedComment> _outboxRows(_CommentPage page) sync* {
    for (final entry in _queued.values) {
      if (entry.rootId != page.root || page.rows.containsKey(entry.id)) {
        continue;
      }
      if (entry.confirmedAt case final confirmed?) {
        final replaced = page.replacedFrom;
        final comment = entry.receipt?.comment;
        if (comment != null &&
            (replaced == null || confirmed.isAfter(replaced)) &&
            !_isBlocked(comment) &&
            !actions.commentHidden(comment.id)) {
          yield comment;
        }
      } else {
        yield entry.pendingComment(actions.account.userId);
      }
    }
  }

  FeedCommentOutboxEntry? pendingEntry(FeedComment comment) {
    final entry = _queued[comment.id];
    if (entry == null || entry.confirmedAt != null) return null;
    final root = _root.rows[comment.threadId];
    if (root?.id == comment.id ||
        root?.replyPreview?.id == comment.id ||
        _threads[comment.threadId]?.rows.containsKey(comment.id) == true) {
      return null;
    }
    return entry;
  }

  Iterable<FeedCommentOutboxEntry> get detachedFailedReplies =>
      _queued.values.where(
        (entry) =>
            entry.failure != null &&
            entry.rootId != null &&
            !_root.rows.containsKey(entry.rootId),
      );

  Future<void> _restore(String id, int revision) async {
    final cached = await actions.publicationCache.restoreComments(id);
    if (isClosed ||
        revision != _revision ||
        id != _post.id ||
        !actions.canShow(_post)) {
      return;
    }
    _restoring = false;
    _applySnapshots(cached, remember: true);
    if (_autoLoad && _ready && !_root.started) unawaited(next());
  }

  Future<void> refresh({
    required bool interactive,
    Set<String> visibleThreads = const {},
    bool includeRoot = true,
  }) async {
    await _restoreRequest;
    if (!_active || !_ready) return;
    final root = _root;
    final expiry = root.expiresAt;
    if (!interactive &&
        !root.failed &&
        expiry != null &&
        actions.publicationCache.expiresFromNow().difference(expiry) <
            const Duration(seconds: 15)) {
      return;
    }
    await Future.wait([
      if (includeRoot)
        _load(root, refresh: true, silent: !interactive && root.started),
      for (final id in visibleThreads)
        if (_threads[id] case final page?) _load(page, refresh: true),
    ]);
  }

  void _applySnapshots(
    Map<FeedCommentCacheKey, CachedFeedComments> entries, {
    bool remember = false,
  }) {
    for (final entry in entries.entries) {
      final (_, sort, root) = entry.key;
      final current = root == null ? _roots[sort] : _threads[root];
      if (current != null && (current.started || current.loading)) continue;
      final snapshot = (
        page: actions.redactComments(entry.value.page),
        expiresAt: entry.value.expiresAt,
      );
      final page = _CommentPage(sort, root, snapshot);
      if (root == null) {
        _roots[sort] = page;
      } else {
        _threads[root] = page;
      }
      if (remember) {
        actions.publicationCache.rememberComments(entry.key, snapshot);
      }
      _hasCachedPages = true;
    }
    if (!_hasCachedPages) return;
    if (!_ready && !_root.started) _root.failed = true;
    _scheduleExpiry();
    _publish();
  }

  void _scheduleExpiry() {
    _cacheExpiry?.cancel();
    if (_ready || !_hasCachedPages) return;
    final now = DateTime.now();
    DateTime? earliest;
    for (final page in [..._roots.values, ..._threads.values]) {
      final expiry = page.expiresAt;
      if (expiry != null && (earliest == null || expiry.isBefore(earliest))) {
        earliest = expiry;
      }
    }
    if (earliest == null) return;
    _cacheExpiry = Timer(earliest.difference(now), () {
      if (!_active || _ready) return;
      final current = DateTime.now();
      bool expired(_, _CommentPage page) =>
          page.expiresAt?.isAfter(current) == false;
      _roots.removeWhere(expired);
      _threads.removeWhere(expired);
      if (!_root.started) _root.failed = true;
      _scheduleExpiry();
      _publish();
    });
  }

  bool available(FeedComment comment) =>
      _active &&
      comment.available &&
      pendingEntry(comment) == null &&
      !actions.commentHidden(comment.id) &&
      !actions.state.blocked.contains(comment.authorId);

  bool busy(FeedComment comment) => _busy.contains(comment.id);

  FeedReaction reactionFor(FeedComment comment) {
    final updated = _reactions[comment.id];
    return updated != null && updated.version > comment.reaction.version
        ? updated
        : comment.reaction;
  }

  void selectSort(FeedCommentSort sort) {
    if (!_active || sort == _sort) return;
    _sort = sort;
    final page = _root;
    if (page.started || page.loading) {
      _publish();
    } else {
      unawaited(_load(page));
    }
  }

  Future<void> next() => _active ? _load(_root) : Future.value();

  List<FeedComment> replies(FeedComment root) {
    final page = _threads[root.id];
    final preview = root.replyPreview;
    if (page == null) return [?preview];
    final rows = <String, FeedComment>{
      if (preview != null && !page.started) preview.id: preview,
      ...page.rows,
      for (final row in _sent.values)
        if (row.id != row.threadId &&
            row.threadId == root.id &&
            !page.rows.containsKey(row.id))
          row.id: row,
      for (final row in _outboxRows(page))
        if (row.id != preview?.id) row.id: row,
    };
    return rows.values.toList(growable: false);
  }

  bool isExpanded(String root) => _threads.containsKey(root);

  ({bool loading, bool failed, bool more}) threadStatus(String root) {
    final page = _threads[root];
    return (
      loading: page?.loading ?? false,
      failed: page?.failed ?? false,
      more: page?.more ?? true,
    );
  }

  Future<void> expand(String root) async {
    if (!_active) return;
    final page = _threads.putIfAbsent(
      root,
      () => _page(FeedCommentSort.old, root),
    );
    if (!page.started) await _load(page);
  }

  Future<void> nextReplies(String root) {
    final page = _threads[root];
    return page == null ? Future.value() : _load(page);
  }

  static bool _expiredCursor(Object error) =>
      error is PostgrestException &&
      (error.code == 'PT410' ||
          error.code == 'PT404' &&
              error.message == 'comment_session_not_found');

  Future<void> _load(
    _CommentPage page, {
    bool refresh = false,
    bool silent = false,
  }) {
    final fromStart = refresh || page.failedRefresh;
    if (!_active || _restoring || !page.more && !fromStart) {
      return Future.value();
    }
    if (page.pending != null && (!fromStart || page.readingHead)) {
      return page.pending!;
    }
    if (!_ready || _networkAvailable?.call() == false) {
      page.failed = true;
      page.failedRefresh = fromStart;
      _publish();
      return Future.value();
    }
    final request = ++page.request;
    page.readingHead = fromStart || page.cursor == null;
    page.silent = silent;
    return page.pending = _read(page, refresh: fromStart, request: request)
        .whenComplete(() {
          if (page.request == request) page.pending = null;
        });
  }

  Future<void> _read(
    _CommentPage page, {
    required bool refresh,
    required int request,
  }) async {
    final revision = _revision;
    final cursor = refresh ? null : page.cursor;
    final existingSent = _sent.keys.toSet();
    final startedAt = DateTime.now();
    bool current() => request == page.request && revision == _revision;
    page.loading = true;
    page.failed = false;
    page.failedRefresh = false;
    _publish();
    try {
      var replace = cursor == null;
      FeedCommentsPage? response;
      if (!replace) {
        try {
          response = await _getPage(page, cursor);
        } catch (error) {
          if (!_expiredCursor(error) ||
              !_active ||
              !current() ||
              _anchorFor(page) == null) {
            rethrow;
          }
          replace = true;
          page.readingHead = true;
        }
      }
      if (replace) {
        response = await _replace(page, current);
      }
      if (!_active || !current()) return;
      if (response == null) {
        page.failed = true;
        page.failedRefresh = true;
        return;
      }
      if (replace) {
        page.rows.clear();
        page.replacedFrom = startedAt;
        page.expiresAt = actions.publicationCache.expiresFromNow();
        _sent.removeWhere(
          (id, comment) =>
              existingSent.contains(id) &&
              (page.root == null
                  ? comment.id == comment.threadId
                  : comment.threadId == page.root),
        );
      }
      page.started = true;
      page.more = response.next != null && (replace || response.next != cursor);
      page.cursor = page.more ? response.next : null;
      for (final row in actions.redactComments(response).comments) {
        page.rows[row.id] = _withCurrentReaction(row);
      }
      if (page.expiresAt case final expires?) {
        final key = (_post.id, page.sort, page.root);
        FeedCommentsPage snapshot = (
          comments: page.rows.values.toList(growable: false),
          next: page.cursor,
        );
        for (final sent in _sent.values) {
          snapshot = _includeSentComment(key, snapshot, sent);
        }
        actions.publicationCache.write(
          key,
          snapshot,
          expiresAt: expires,
          allowed: () => current() && actions.canShow(_post),
        );
      }
    } catch (error) {
      if (current()) {
        _handleAccessError(error);
        final expired = _expiredCursor(error);
        if (expired) {
          page.cursor = null;
          page.replacement = null;
        }
        page.failed = true;
        page.failedRefresh = refresh || expired || page.replacement != null;
      }
    } finally {
      if (page.request == request) page.loading = false;
      if (current()) _publish();
    }
  }

  Future<FeedCommentsPage> _getPage(
    _CommentPage page,
    FeedCommentsCursor? cursor,
  ) => repository.getComments(
    _post.id,
    actions.account,
    cursor: cursor,
    sort: page.sort,
    rootId: page.root,
  );

  String? _anchorFor(_CommentPage page) {
    if (page.root == null && page.sort != _sort) return null;
    final id = visibleAnchors?.call()[page.root];
    return id != null && page.rows.containsKey(id) ? id : null;
  }

  Future<FeedCommentsPage?> _replace(
    _CommentPage page,
    bool Function() current,
  ) async {
    final pending = page.replacement;
    final now = _clock.elapsed;
    final replacement =
        pending != null && now - pending.startedAt < const Duration(minutes: 5)
        ? pending
        : _CommentRefresh(now);
    page.replacement = replacement;
    // Keep one cycle bounded even if a popular comment moves many pages.
    const pagesPerCycle = 5;
    for (var reads = 0; reads <= pagesPerCycle; reads++) {
      final anchor = _anchorFor(page);
      if (replacement.rows.isNotEmpty &&
          (anchor == null ||
              replacement.rows.containsKey(anchor) ||
              replacement.next == null ||
              replacement.rows.length >=
                  FeedPostSnapshotStore.maximumComments)) {
        page.replacement = null;
        return (
          comments: replacement.rows.values.toList(growable: false),
          next: replacement.next,
        );
      }
      if (reads == pagesPerCycle) return null;
      final cursor = replacement.next;
      final response = await _getPage(page, cursor);
      if (!_active || !current()) return null;
      for (final row in response.comments) {
        replacement.rows[row.id] = row;
      }
      final next = response.next;
      replacement.next = next != null && replacement.cursors.add(next)
          ? next
          : null;
      if (replacement.next == null) {
        page.replacement = null;
        return (
          comments: replacement.rows.values.toList(growable: false),
          next: null,
        );
      }
    }
    return null;
  }

  Future<void> _revalidateAfterConflict(_CommentPage page) =>
      page.revalidation ??= _revalidate(
        page,
      ).whenComplete(() => page.revalidation = null);

  Future<void> _revalidate(_CommentPage page) async {
    final revision = _revision;
    await page.pending;
    if (_active && revision == _revision) await _load(page, refresh: true);
  }

  void invalidateAccess() {
    if (!_active) return;
    _revision++;
    for (final page in [..._roots.values, ..._threads.values]) {
      page.replacement = null;
      final redacted = actions.redactComments((
        comments: page.rows.values.toList(),
        next: page.cursor,
      ));
      for (final row in redacted.comments) {
        page.rows[row.id] = row;
      }
    }
    _sent.removeWhere((_, comment) => _isBlocked(comment));
    _publish();
    if (_restoring) {
      unawaited(_restoreRequest = _restore(_post.id, _revision));
    } else if (_ready && _networkAvailable?.call() != false) {
      unawaited(_revalidateAfterConflict(_root));
    }
  }

  Future<bool> submit(String text, {FeedComment? replyTo}) async {
    if (!canSubmit ||
        _submitting ||
        text.trim().isEmpty ||
        text.runes.length > FeedCommentOutbox.maximumLength ||
        replyTo != null && !available(replyTo)) {
      return false;
    }
    _submitting = true;
    if (actions.outbox case final outbox?) {
      try {
        await outbox.enqueue(
          actions.account,
          _post.id,
          text,
          replyTo: replyTo?.id,
          rootId: replyTo?.threadId,
        );
        return true;
      } finally {
        _submitting = false;
      }
    }
    final pending = _pending;
    final target = replyTo?.id;
    final requestId =
        pending != null && pending.text == text && pending.replyTo == target
        ? pending.id
        : const Uuid().v4();
    _pending = (text: text, replyTo: target, id: requestId);
    final post = _post;
    try {
      final receipt = await repository.createComment(
        post.id,
        requestId,
        text,
        actions.account,
        replyTo: target,
      );
      if (actions.canShow(post)) {
        if (receipt.postCount case final count?) {
          actions.recordCommentCount(post, count);
        }
        actions.publicationCache.updateComments(
          (key, page) => _includeSentComment(key, page, receipt.comment),
          postId: post.id,
          postCount: receipt.postCount,
        );
      }
      if (!_active) return false;
      _pending = null;
      final comment = receipt.comment;
      _sent[comment.id] = comment;
      if (replyTo != null && !isExpanded(replyTo.threadId)) {
        unawaited(expand(replyTo.threadId));
      }
      _publish();
      return true;
    } catch (error) {
      _handleAccessError(error);
      rethrow;
    } finally {
      _submitting = false;
    }
  }

  Future<void> toggleLike(FeedComment comment) async {
    final now = _clock.elapsed;
    _recentActions.removeWhere((_, until) => until <= now);
    if (_recentActions.containsKey(comment.id) || !_begin(comment)) return;
    final current = reactionFor(comment);
    final page = comment.id == comment.threadId
        ? _root
        : _threads[comment.threadId] ?? _root;
    final id = const Uuid().v4();
    Future<FeedCommentLike> send() =>
        repository.setCommentLiked(comment, current, id, actions.account);
    try {
      final result = await _retry(send, comment);
      if (!actions.canShow(_post) || actions.commentHidden(comment.id)) return;
      final reaction = (
        version: result.version,
        liked: result.liked,
        likes: (current.likes + (result.changed ? (result.liked ? 1 : -1) : 0))
            .clamp(0, 0x7fffffff),
      );
      if (_active && available(comment)) _reactions[comment.id] = reaction;
      actions.publicationCache.updateComments(
        (_, saved) => mapFeedCommentPage(
          saved,
          (row) => _applyReaction(row, comment.id, reaction),
        ),
        postId: _post.id,
      );
    } catch (error) {
      _handleAccessError(error, comment: comment);
      if (error is PostgrestException && error.code == 'PT409') {
        await _revalidateAfterConflict(page);
      }
      rethrow;
    } finally {
      _recentActions[comment.id] =
          _clock.elapsed + const Duration(milliseconds: 350);
      _finish(comment);
    }
  }

  Future<void> report(FeedComment comment, FeedReportReason reason) async {
    if (comment.authorId == actions.account.userId || !_begin(comment)) return;
    final id = const Uuid().v4();
    try {
      await _retry(
        () => repository.reportComment(comment.id, reason, id, actions.account),
        comment,
      );
      if (actions.canShow(_post)) actions.hideComment(_post.id, comment.id);
    } catch (error) {
      _handleAccessError(error, comment: comment);
      rethrow;
    } finally {
      _finish(comment);
    }
  }

  bool _begin(FeedComment comment) {
    if (!_active || !_ready || !available(comment) || !_busy.add(comment.id)) {
      return false;
    }
    _publish();
    return true;
  }

  void _finish(FeedComment comment) {
    _busy.remove(comment.id);
    _publish();
  }

  Future<T> _retry<T>(Future<T> Function() send, FeedComment comment) async {
    try {
      return await send();
    } on TimeoutException {
      if (!_active || !available(comment)) rethrow;
      return send();
    }
  }

  bool _isBlocked(FeedComment comment) =>
      actions.state.blocked.contains(comment.authorId);

  FeedComment _withCurrentReaction(FeedComment row) {
    final own = row.available ? reactionFor(row) : row.reaction;
    final preview = row.replyPreview;
    final next = preview == null ? null : _withCurrentReaction(preview);
    return own == row.reaction && identical(next, preview)
        ? row
        : row.copyWith(reaction: own, replyPreview: next);
  }

  @override
  Future<void> close() {
    _cacheExpiry?.cancel();
    unawaited(_outboxSubscription?.cancel());
    visibleAnchors = null;
    return super.close();
  }

  void _handleAccessError(Object error, {FeedComment? comment}) {
    if (!_active || error is! PostgrestException || error.code != 'PT404') {
      return;
    }
    if (error.message == 'post_not_found') {
      actions.hidePost(_post.id);
    } else if (comment != null &&
        const {
          'comment_not_found',
          'report_target_not_found',
        }.contains(error.message)) {
      actions.hideComment(_post.id, comment.id);
    }
  }

  void _publish() {
    if (!_active) return;
    final root = _root;
    final sent = [
      ..._sent.values.where(
        (row) => row.id == row.threadId && !root.rows.containsKey(row.id),
      ),
      ..._outboxRows(root),
    ];
    emit((
      rows: List.unmodifiable([
        if (_sort != FeedCommentSort.old) ...sent.reversed,
        ...root.rows.values,
        if (_sort == FeedCommentSort.old) ...sent,
      ]),
      sort: _sort,
      loading: root.loading && !root.silent,
      failed: root.failed,
      loaded: root.started,
      hasMore: root.more,
    ));
  }
}

FeedComment _applyReaction(FeedComment row, String id, FeedReaction reaction) {
  if (row.id == id &&
      row.available &&
      reaction.version > row.reaction.version) {
    return row.copyWith(reaction: reaction);
  }
  final preview = row.replyPreview;
  if (preview == null) return row;
  final updated = _applyReaction(preview, id, reaction);
  return identical(updated, preview)
      ? row
      : row.copyWith(replyPreview: updated);
}

FeedCommentsPage _includeSentComment(
  FeedCommentCacheKey key,
  FeedCommentsPage page,
  FeedComment comment,
) {
  final (_, sort, root) = key;
  if (page.comments.any((row) => row.id == comment.id)) return page;
  if (root == null &&
      comment.id == comment.threadId &&
      sort != FeedCommentSort.old) {
    return (comments: [comment, ...page.comments], next: page.next);
  }
  if (page.next == null &&
      (root == comment.threadId ||
          root == null && comment.id == comment.threadId)) {
    return (comments: [...page.comments, comment], next: null);
  }
  return page;
}
