import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/core/services/services.dart';

void main() {
  const owner = 'owner';
  final now = DateTime.utc(2026, 9, 7, 12);

  late AppDatabase database;
  late ChatCacheDataSource cache;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    cache = ChatCacheDataSource(
      database: database,
      userIdProvider: () => owner,
    );
  });

  tearDown(() => database.close());

  test('selects only due heads while keeping each chat FIFO', () async {
    await cache.putPendingOperation(_operation('a-old', 'chat-a', now));
    await cache.putPendingOperation(
      _operation('a-new', 'chat-a', now.add(const Duration(seconds: 1))),
    );
    await cache.putPendingOperation(_operation('b', 'chat-b', now));

    final due = await cache.readDuePendingOperations(
      dueAt: now.add(const Duration(seconds: 2)),
    );

    expect(due.map((operation) => operation.id), ['a-old', 'b']);
    expect(await cache.readNextPendingAttemptAt(), now);
  });

  test(
    'delays a later message in the same chat but not another chat',
    () async {
      await cache.putPendingOperation(_operation('a-old', 'chat-a', now));
      await cache.putPendingOperation(
        _operation('a-new', 'chat-a', now.add(const Duration(seconds: 1))),
      );
      await cache.putPendingOperation(_operation('b', 'chat-b', now));
      await cache.markPendingFailure(
        'a-old',
        StateError('offline'),
        attempts: 1,
        nextAttemptAt: now.add(const Duration(seconds: 5)),
      );

      final due = await cache.readDuePendingOperations(
        dueAt: now.add(const Duration(seconds: 2)),
      );

      expect(due.map((operation) => operation.id), ['b']);
      expect(
        await cache.readNextPendingAttemptAt(),
        now,
        reason: 'chat-b remains immediately deliverable',
      );
    },
  );

  test(
    'keeps an exhausted message for an explicit retry and resets it',
    () async {
      await cache.putPendingOperation(_operation('failed', 'chat', now));
      await cache.markPendingFailure(
        'failed',
        StateError('offline'),
        attempts: OutboxRetryPolicy.maxAutomaticAttempts,
        nextAttemptAt: null,
      );

      expect(await cache.readDuePendingOperations(dueAt: now), isEmpty);
      expect(await cache.readNextPendingAttemptAt(), isNull);

      final requeued = await cache.requeuePendingOperation(
        'failed',
        nextAttemptAt: now,
      );

      expect(requeued, isNotNull);
      expect(requeued!.attempts, 0);
      expect(requeued.lastError, isNull);
      expect(
        (await cache.readDuePendingOperations(dueAt: now)).single.id,
        'failed',
      );
    },
  );

  test(
    'persists attempt timestamps without changing the scheduled time',
    () async {
      await cache.putPendingOperation(_operation('message', 'chat', now));
      final attemptedAt = now.add(const Duration(seconds: 2));

      expect(
        await cache.markPendingAttemptStarted(
          'message',
          attemptedAt: attemptedAt,
        ),
        isTrue,
      );

      final operation = await cache.readPendingOperation('message');
      expect(operation!.lastAttemptAt, attemptedAt);
      expect(operation.nextAttemptAt, now);
    },
  );

  test(
    'uses bounded exponential backoff and protects a rate-limited sender',
    () {
      final first = OutboxRetryPolicy.delayAfterFailure(
        attempts: 1,
        operationId: 'one',
        rateLimited: false,
      );
      final second = OutboxRetryPolicy.delayAfterFailure(
        attempts: 2,
        operationId: 'two',
        rateLimited: false,
      );
      final capped = OutboxRetryPolicy.delayAfterFailure(
        attempts: 20,
        operationId: 'three',
        rateLimited: false,
      );
      final rateLimited = OutboxRetryPolicy.delayAfterFailure(
        attempts: 1,
        operationId: 'four',
        rateLimited: true,
      );

      expect(first.inMilliseconds, inInclusiveRange(4000, 6000));
      expect(second.inMilliseconds, inInclusiveRange(9000, 11000));
      expect(
        capped.inMilliseconds,
        lessThanOrEqualTo(const Duration(minutes: 30).inMilliseconds),
      );
      expect(
        rateLimited.inMilliseconds,
        greaterThanOrEqualTo(const Duration(minutes: 1).inMilliseconds),
      );
    },
  );
}

PendingMessageOperation _operation(
  String id,
  String chatId,
  DateTime createdAt,
) => PendingMessageOperation(
  id: id,
  chatId: chatId,
  type: 'text',
  payload: const {'text': 'hello'},
  createdAt: createdAt,
  nextAttemptAt: createdAt,
);
