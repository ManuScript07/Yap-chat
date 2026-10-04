import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chat/pending_message_retry_policy.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';

/// One durable, coalescing queue for the account, including closed chats.
/// Message sends retain their own FIFO and media lifecycle.
class MessageReactionCoordinator {
  MessageReactionCoordinator({
    required ChatCacheDataSource cache,
    required ChatRemoteDataSource remote,
    required AccountSessionController account,
    required ChatsCacheDataSource chatsCache,
    DateTime Function()? now,
    void Function(Object, StackTrace)? onError,
  }) : _cache = cache,
       _remote = remote,
       _account = account,
       _chats = chatsCache,
       _now = now ?? DateTime.now,
       _onError = onError;
  final ChatCacheDataSource _cache;
  final ChatRemoteDataSource _remote;
  final AccountSessionController _account;
  final ChatsCacheDataSource _chats;
  final DateTime Function() _now;
  final void Function(Object, StackTrace)? _onError;
  final _changes = StreamController<MessageReactionChange>.broadcast();
  final Map<String, DateTime> _lastTap = {};
  final Map<String, Future<void>> _choices = {};
  Timer? _timer;
  Future<void>? _draining;
  bool _paused = false;
  int _scheduleSerial = 0;
  DateTime? _nextDispatchAt;
  String? _dispatchOwner;
  Stream<MessageReactionChange> get changes => _changes.stream;

  Future<bool> choose(
    ChatMessage message,
    ReactionCode code, {
    bool toggle = true,
  }) async {
    final scope = _account.capture();
    if (message.isLocalOnly ||
        message.status == MessageStatus.sending ||
        message.status == MessageStatus.error) {
      return false;
    }
    final key = '${scope.generation}:${scope.userId}:${message.id}';
    final now = _now();
    if (_lastTap[key] case final last?) {
      if (now.difference(last) < const Duration(milliseconds: 120)) {
        return false;
      }
    }
    _lastTap[key] = now;
    if (_lastTap.length > 512) _lastTap.remove(_lastTap.keys.first);
    final previous = _choices[key] ?? Future<void>.value();
    var accepted = false;
    final operation = previous.catchError((Object _) {}).then((_) async {
      if (!_account.isCurrent(scope) ||
          await _chats.isDeliveryBlocked(
            message.chatId,
            ownerUserId: scope.userId,
          )) {
        return;
      }
      await _account.commit(scope, () async {
        final current = await _cache.readReactionState(
          message.id,
          ownerUserId: scope.userId,
        );
        final desired = toggle && current.codeFor(scope.userId) == code
            ? null
            : code;
        final pending = await _cache.readPendingReaction(
          message.id,
          ownerUserId: scope.userId,
        );
        if (pending == null && current.codeFor(scope.userId) == desired) return;
        final confirmed = await _cache.readReactionState(
          message.id,
          ownerUserId: scope.userId,
          optimistic: false,
        );
        await _cache.enqueueReaction(
          ownerUserId: scope.userId,
          chatId: message.chatId,
          messageId: message.id,
          operationId: const Uuid().v4(),
          code: desired,
          expectedRevision: confirmed.userRevisions[scope.userId] ?? 0,
          dueAt: _now().toUtc().add(const Duration(milliseconds: 450)),
        );
        _changes.add(
          MessageReactionChange(
            message.chatId,
            message.id,
            current.withChoice(scope.userId, desired),
          ),
        );
        accepted = true;
      });
    });
    _choices[key] = operation;
    try {
      await operation;
    } finally {
      if (identical(_choices[key], operation)) _choices.remove(key);
    }
    await _arm();
    return accepted;
  }

  Future<void> accept(
    String chatId,
    String messageId,
    MessageReactionState state, {
    AccountSessionSnapshot? session,
  }) async {
    final scope = session ?? _account.capture();
    await _account.commit(scope, () async {
      await _cache.storeReactionState(
        chatId,
        messageId,
        state,
        ownerUserId: scope.userId,
      );
      _changes.add(
        MessageReactionChange(
          chatId,
          messageId,
          await _cache.readReactionState(messageId, ownerUserId: scope.userId),
        ),
      );
    });
  }

  Future<List<ChatMessage>> hydrate(
    List<ChatMessage> messages, {
    AccountSessionSnapshot? session,
  }) async {
    final scope = session ?? _account.capture();
    if (messages.isEmpty) return messages;
    await _account.commit(
      scope,
      () => _cache.storeReactionStates(messages.first.chatId, {
        for (final message in messages) message.id: message.reactionState,
      }, ownerUserId: scope.userId),
    );
    final result = await _cache.mergeReactionStates(
      messages,
      ownerUserId: scope.userId,
    );
    _account.ensureCurrent(scope);
    return result;
  }

  Future<void> acceptBatch(
    String chatId,
    Map<String, MessageReactionState> states, {
    required AccountSessionSnapshot session,
  }) async {
    await _account.commit(
      session,
      () => _cache.storeReactionStates(
        chatId,
        states,
        ownerUserId: session.userId,
      ),
    );
    for (final id in states.keys) {
      final effective = await _cache.readReactionState(
        id,
        ownerUserId: session.userId,
      );
      _account.ensureCurrent(session);
      _changes.add(MessageReactionChange(chatId, id, effective));
    }
  }

  void pause() {
    _paused = true;
    _scheduleSerial++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> resume() async {
    _paused = false;
    await _arm();
  }

  Future<void> _arm() async {
    final serial = ++_scheduleSerial;
    _timer?.cancel();
    _timer = null;
    if (_paused || _draining != null || _account.userId == null) return;
    final scope = _account.capture();
    final queue = await _cache.readReactionQueue(scope.userId);
    if (serial != _scheduleSerial ||
        _paused ||
        !_account.isCurrent(scope) ||
        queue.isEmpty ||
        _draining != null) {
      return;
    }
    if (_dispatchOwner != scope.userId) {
      _dispatchOwner = scope.userId;
      _nextDispatchAt = null;
    }
    var scheduledFor = queue.first.nextAttemptAt;
    if (_nextDispatchAt case final next?) {
      if (next.isAfter(scheduledFor)) scheduledFor = next;
    }
    final delay = scheduledFor.difference(_now().toUtc());
    _timer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_runScheduled()),
    );
  }

  Future<void> _runScheduled() async {
    try {
      await _drain();
    } on StaleAccountSessionException {
      // Logout invalidates the scheduled operation.
    } catch (error, stack) {
      _onError?.call(error, stack);
    }
  }

  Future<void> _drain() async {
    if (_draining case final active?) return active;
    final operation = _deliverDue();
    _draining = operation;
    try {
      await operation;
    } finally {
      _draining = null;
    }
    await _arm();
  }

  Future<void> _deliverDue() async {
    if (_paused || _account.userId == null) return;
    final scope = _account.capture();
    for (final operation in await _cache.readReactionQueue(scope.userId)) {
      if (_paused || !_account.isCurrent(scope)) return;
      if (operation.nextAttemptAt.isAfter(_now().toUtc())) continue;
      try {
        if (await _chats.isDeliveryBlocked(
          operation.chatId,
          ownerUserId: scope.userId,
        )) {
          await _complete(operation, scope);
          continue;
        }
        _nextDispatchAt = _now().toUtc().add(const Duration(seconds: 1));
        final result = await _remote
            .setReaction(
              chatId: operation.chatId,
              messageId: operation.messageId,
              operationId: operation.operationId,
              code: ReactionCode.parse(operation.code),
              expectedRevision: operation.expectedRevision,
            )
            .timeout(const Duration(seconds: 15));
        await _account.commit(scope, () async {
          await _cache.storeReactionState(
            operation.chatId,
            operation.messageId,
            result.state,
            ownerUserId: scope.userId,
          );
          await _cache.finishReactionOperation(operation);
          // A newer local choice made while this RPC ran must use its response
          // as the base. Never let this acknowledgment remove that choice.
          await _cache.rebasePendingReaction(
            operation.messageId,
            scope.userId,
            result.state.userRevisions[scope.userId] ?? 0,
          );
        });
        await _publish(operation, scope);
        _nextDispatchAt = _now().toUtc().add(const Duration(seconds: 1));
        return;
      } on StaleAccountSessionException {
        return;
      } catch (error) {
        if (!_account.isCurrent(scope)) return;
        final terminal =
            error.toString().contains('42501') ||
            error.toString().contains('22023') ||
            error.toString().contains('account_') ||
            operation.attempts + 1 >=
                PendingMessageRetryPolicy.maxAutomaticAttempts;
        if (terminal) {
          await _complete(operation, scope);
        } else {
          final delay = PendingMessageRetryPolicy.delayAfterFailure(
            attempts: operation.attempts + 1,
            operationId: operation.operationId,
            rateLimited: error.toString().contains('42901'),
          );
          if (error.toString().contains('42901')) {
            // Back off the entire queue, not just this message. Otherwise a
            // modified/busy UI could drain a hundred rate-limited RPCs at once.
            _nextDispatchAt = _now().toUtc().add(delay);
          }
          await _account.commit(
            scope,
            () => _cache.deferReactionOperation(
              operation,
              _now().toUtc().add(delay),
            ),
          );
        }
        _nextDispatchAt ??= _now().toUtc().add(const Duration(seconds: 1));
        return;
      }
    }
  }

  Future<void> _complete(
    PendingMessageReaction operation,
    AccountSessionSnapshot scope,
  ) async {
    await _account.commit(
      scope,
      () => _cache.finishReactionOperation(operation),
    );
    await _publish(operation, scope);
  }

  Future<void> _publish(
    PendingMessageReaction operation,
    AccountSessionSnapshot scope,
  ) async {
    final state = await _cache.readReactionState(
      operation.messageId,
      ownerUserId: scope.userId,
    );
    if (_account.isCurrent(scope)) {
      _changes.add(
        MessageReactionChange(operation.chatId, operation.messageId, state),
      );
    }
  }
}
