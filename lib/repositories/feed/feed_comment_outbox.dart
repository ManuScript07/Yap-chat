import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';

import 'feed_comment_outbox_store.dart';
import 'feed_post.dart';
import 'feed_post_snapshot_store.dart';
import 'feed_repository.dart';

export 'feed_comment_outbox_store.dart'
    show
        FeedCommentDelivery,
        FeedCommentFailure,
        FeedCommentOutboxEntry,
        FeedCommentOutboxFull;

/// One sender per app. Pages only observe durable operations for their post.
class FeedCommentOutbox {
  FeedCommentOutbox(
    AppDatabase db,
    this._accounts,
    this._repository,
    this._network,
    FeedPostSnapshotStore snapshots, {
    DateTime Function()? now,
  }) : _store = FeedCommentOutboxStore(db, _accounts, snapshots),
       _now = now ?? DateTime.now {
    _network?.addListener(_schedule);
    _accounts.generationChanges.addListener(_schedule);
  }

  static const maximumLength = 200;
  static const _storageRetryDelay = Duration(seconds: 5);
  final AccountSessionController _accounts;
  final IFeedPublicationRepository _repository;
  final ValueListenable<bool?>? _network;
  final FeedCommentOutboxStore _store;
  final DateTime Function() _now;
  final _deliveries = StreamController<FeedCommentDelivery>.broadcast(
    sync: true,
  );
  Stream<FeedCommentDelivery> get deliveries => _deliveries.stream;

  String? _userId;
  bool _foreground = true;
  bool _disposed = false;
  bool _reschedule = false;
  Future<void>? _running;
  Timer? _wakeUp;

  Stream<List<FeedCommentOutboxEntry>> watch(
    AccountSessionSnapshot account,
    String postId,
  ) => _store.watch(account, postId, _now);

  Future<void> enqueue(
    AccountSessionSnapshot account,
    String postId,
    String text, {
    required String? replyTo,
    required String? rootId,
  }) async {
    if (_disposed) throw const StaleAccountSessionException();
    if (text.trim().isEmpty || text.runes.length > maximumLength) {
      throw ArgumentError('Invalid comment length');
    }
    await _store.enqueue(
      account,
      postId,
      const Uuid().v4(),
      text,
      _now(),
      replyTo: replyTo,
      rootId: rootId,
    );
    _accounts.ensureCurrent(account);
    _schedule();
  }

  Future<void> discardFailed(AccountSessionSnapshot account, String id) async {
    await _store.discardFailed(account, id);
    _schedule();
  }

  Future<void> clearUser(String userId) => _store.clearUser(userId);

  void setAuthenticatedUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    _schedule();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _schedule();
  }

  bool get _canSend =>
      !_disposed &&
      _foreground &&
      _userId != null &&
      _userId == _accounts.userId &&
      _network?.value != false;

  void _schedule() {
    if (_disposed) return;
    _wakeUp?.cancel();
    _wakeUp = null;
    if (_running != null) {
      _reschedule = true;
      return;
    }
    if (!_canSend) return;
    final account = _accounts.capture();
    _running = _drain(account).whenComplete(() {
      _running = null;
      if (!_reschedule) return;
      _reschedule = false;
      _schedule();
    });
  }

  bool _canContinue(AccountSessionSnapshot account) =>
      _canSend && _accounts.isCurrent(account);

  void _scheduleWakeUp(AccountSessionSnapshot account, Duration delay) {
    if (!_canContinue(account)) return;
    _wakeUp = Timer(delay, _schedule);
  }

  Future<void> _drain(AccountSessionSnapshot account) async {
    try {
      while (_canContinue(account)) {
        final operation = await _store.next(account.userId);
        if (operation == null || !_canContinue(account)) return;
        final now = _now();
        final limit = await _store.rateLimitedUntil(account.userId, now);
        if (!_canContinue(account)) return;
        final due = operation.nextAttemptAt!;
        final wake = limit != null && limit > due ? limit : due;
        if (wake > now.microsecondsSinceEpoch) {
          _scheduleWakeUp(
            account,
            Duration(microseconds: wake - now.microsecondsSinceEpoch),
          );
          return;
        }
        await _send(account, operation);
      }
    } on StaleAccountSessionException {
      // A replacement session schedules its own queue.
    } catch (_) {
      // A local storage failure must leave the operation recoverable.
      _scheduleWakeUp(account, _storageRetryDelay);
    }
  }

  Future<void> _send(
    AccountSessionSnapshot account,
    FeedCommentOperation operation,
  ) async {
    final attempts = operation.attempts + 1;
    if (attempts > OutboxRetryPolicy.maxAutomaticAttempts) {
      await _store.defer(
        account,
        operation.id,
        attempts: operation.attempts,
        next: null,
        failure: FeedCommentFailure.exhausted,
      );
      return;
    }
    final delay = OutboxRetryPolicy.delayAfterFailure(
      attempts: attempts,
      operationId: operation.id,
      rateLimited: false,
    );
    await _store.defer(
      account,
      operation.id,
      attempts: attempts,
      next: _now().add(delay),
    );
    if (!_canContinue(account)) {
      if (!_disposed && _accounts.isCurrent(account)) {
        await _store.defer(
          account,
          operation.id,
          attempts: operation.attempts,
          next: _now(),
        );
      }
      return;
    }
    // Only transport and server errors are classified here. A failed local
    // receipt write falls through to the drain so the UUID stays replayable.
    final FeedCommentCreation receipt;
    try {
      receipt = await _repository.createComment(
        operation.postId,
        operation.id,
        operation.body,
        account,
        replyTo: operation.replyToId,
      );
      final comment = receipt.comment;
      if (comment.id != operation.id ||
          comment.threadId != (operation.rootId ?? operation.id) ||
          (comment.authorId != null && comment.authorId != account.userId)) {
        throw const FormatException('Unexpected comment receipt');
      }
    } catch (error) {
      if (_disposed || !_accounts.isCurrent(account)) return;
      await _recordFailure(account, operation, attempts, error);
      return;
    }
    if (_disposed || !_accounts.isCurrent(account)) return;
    await _store.acknowledge(account, operation, receipt, _now());
    if (!_disposed && _accounts.isCurrent(account)) {
      _deliveries.add((
        account: account,
        postId: operation.postId,
        receipt: receipt,
        failure: null,
      ));
    }
  }

  Future<void> _recordFailure(
    AccountSessionSnapshot account,
    FeedCommentOperation operation,
    int attempts,
    Object error,
  ) async {
    final code = error is PostgrestException ? error.code : null;
    final rateLimited = const {'42901', '429', 'PT429'}.contains(code);
    final transient =
        rateLimited ||
        error is TimeoutException ||
        error is http.ClientException ||
        error is AuthRetryableFetchException ||
        error is StaleAccountSessionException ||
        _transientCode(code);
    final exhausted = attempts >= OutboxRetryPolicy.maxAutomaticAttempts;
    final retryAt = transient
        ? _now().add(
            OutboxRetryPolicy.delayAfterFailure(
              attempts: attempts,
              operationId: operation.id,
              rateLimited: rateLimited,
            ),
          )
        : null;
    final failure = transient
        ? (exhausted ? FeedCommentFailure.exhausted : null)
        : switch (error) {
            PostgrestException(code: 'PT404', message: 'post_not_found') =>
              FeedCommentFailure.postUnavailable,
            PostgrestException(code: 'PT404', message: 'comment_not_found') ||
            PostgrestException(
              code: '22023',
              message: 'invalid_comment_thread',
            ) => FeedCommentFailure.replyUnavailable,
            _ => FeedCommentFailure.rejected,
          };
    final denied = failure == FeedCommentFailure.postUnavailable;
    await _store.defer(
      account,
      operation.id,
      attempts: attempts,
      next: exhausted ? null : retryAt,
      rateLimitedUntil: rateLimited ? retryAt : null,
      failure: failure,
      unavailablePostId: denied ? operation.postId : null,
    );
    if (denied && !_disposed && _accounts.isCurrent(account)) {
      _deliveries.add((
        account: account,
        postId: operation.postId,
        receipt: null,
        failure: failure,
      ));
    }
  }

  static bool _transientCode(String? code) =>
      code != null &&
      (code.startsWith('08') ||
          code.startsWith('PT5') ||
          code.startsWith('PGRST00') ||
          const {
            '40001',
            '40P01',
            '53300',
            '57P01',
            'PGRST301',
            'PGRST303',
          }.contains(code) ||
          (code.length == 3 && code.startsWith('5')));

  Future<void> dispose() async {
    _disposed = true;
    _network?.removeListener(_schedule);
    _accounts.generationChanges.removeListener(_schedule);
    _wakeUp?.cancel();
    await _running;
    await _deliveries.close();
  }
}
