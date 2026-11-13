import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chat/message_reaction_coordinator.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';

void main() {
  late AppDatabase db;
  late AccountSessionController account;
  late ChatCacheDataSource cache;
  late _Remote remote;
  late MessageReactionCoordinator queue;
  late DateTime now;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    account = AccountSessionController(initialUserId: 'me');
    cache = ChatCacheDataSource(
      database: db,
      userIdProvider: () => account.userId!,
    );
    remote = _Remote();
    now = DateTime.now().toUtc();
    queue = MessageReactionCoordinator(
      cache: cache,
      remote: remote,
      account: account,
      chatsCache: ChatsCacheDataSource(
        database: db,
        userIdProvider: () => account.userId!,
      ),
      now: () => now,
    )..pause();
  });
  tearDown(() async {
    queue.pause();
    await account.drainCommits();
    await db.close();
  });
  final message = ChatMessage(
    id: 'message',
    chatId: 'chat',
    senderId: 'peer',
    text: 'hello',
    timestamp: DateTime(2026),
    isMine: false,
  );
  Future<void> due() async {
    now = now.add(const Duration(seconds: 1));
    await queue.resume();
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if ((await cache.readReactionQueue('me')).isEmpty) break;
    }
    queue.pause();
  }

  test(
    'coalesces choices, rejects fast taps, does not poll an empty queue',
    () async {
      expect(await queue.choose(message, ReactionCode.heart), isTrue);
      expect(await queue.choose(message, ReactionCode.fire), isFalse);
      now = now.add(const Duration(milliseconds: 150));
      expect(await queue.choose(message, ReactionCode.fire), isTrue);
      expect(remote.calls, isEmpty);
      expect(
        (await cache.readReactionState(
          'message',
          ownerUserId: 'me',
        )).codeFor('me'),
        ReactionCode.fire,
      );
      expect(
        (await cache.readReactionState(
          'message',
          ownerUserId: 'me',
          optimistic: false,
        )).reactions,
        isEmpty,
      );
      await due();
      expect(remote.calls, [ReactionCode.fire]);
      expect(await cache.readReactionQueue('me'), isEmpty);
      await queue.resume();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(remote.calls, hasLength(1));
    },
  );
  test(
    'explicit non-toggling choice is idempotent; a pill toggles it off',
    () async {
      await queue.choose(message, ReactionCode.heart, toggle: false);
      await due();
      now = now.add(const Duration(seconds: 1));
      expect(
        await queue.choose(message, ReactionCode.heart, toggle: false),
        isFalse,
      );
      expect(remote.calls, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      expect(await queue.choose(message, ReactionCode.heart), isTrue);
      await due();
      expect(remote.calls, [ReactionCode.heart, null]);
      expect(
        (await cache.readReactionState('message', ownerUserId: 'me')).reactions,
        isEmpty,
      );
    },
  );
  test('double tap toggles heart and replaces another choice', () async {
    expect(
      await queue.choose(message, ReactionCode.heart, toggle: true),
      isTrue,
    );
    await due();
    expect(
      await queue.choose(message, ReactionCode.heart, toggle: true),
      isTrue,
    );
    await due();
    expect(
      (await cache.readReactionState('message', ownerUserId: 'me')).reactions,
      isEmpty,
    );
    expect(await queue.choose(message, ReactionCode.fire), isTrue);
    await due();
    expect(
      await queue.choose(message, ReactionCode.heart, toggle: true),
      isTrue,
    );
    await due();
    expect(remote.calls, [
      ReactionCode.heart,
      null,
      ReactionCode.fire,
      ReactionCode.heart,
    ]);
  });
  test(
    'peer event preserves pending intent and rejects older snapshots',
    () async {
      await queue.choose(message, ReactionCode.fire);
      final peer = const MessageReactionState(
        version: 2,
        reactions: [MessageReaction(userId: 'peer', code: ReactionCode.like)],
        userRevisions: {'peer': 2},
      );
      await queue.accept('chat', 'message', peer);
      await queue.accept('chat', 'message', const MessageReactionState());
      final current = await cache.readReactionState(
        'message',
        ownerUserId: 'me',
      );
      expect(current.codeFor('me'), ReactionCode.fire);
      expect(current.codeFor('peer'), ReactionCode.like);
      expect(
        (await cache.readReactionState(
          'message',
          ownerUserId: 'me',
          optimistic: false,
        )).codeFor('me'),
        isNull,
      );
    },
  );
  test(
    'queue survives coordinator restart and delivers in a closed chat',
    () async {
      await queue.choose(message, ReactionCode.cry);
      queue.pause();
      queue = MessageReactionCoordinator(
        cache: cache,
        remote: remote,
        account: account,
        chatsCache: ChatsCacheDataSource(
          database: db,
          userIdProvider: () => account.userId!,
        ),
        now: () => now,
      )..pause();
      await due();
      expect(remote.calls, [ReactionCode.cry]);
    },
  );
  test(
    'failed delivery persists backoff and keeps optimistic reaction',
    () async {
      remote.error = StateError('offline');
      await queue.choose(message, ReactionCode.poop);
      now = now.add(const Duration(seconds: 1));
      await queue.resume();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      queue.pause();
      final pending = (await cache.readReactionQueue('me')).single;
      expect(pending.attempts, 1);
      expect(pending.nextAttemptAt.isAfter(now), isTrue);
      expect(
        (await cache.readReactionState(
          'message',
          ownerUserId: 'me',
        )).codeFor('me'),
        ReactionCode.poop,
      );
      now = pending.nextAttemptAt;
      remote.error = null;
      await due();
      expect(remote.ids.toSet(), hasLength(1));
      expect(remote.calls, hasLength(2));
    },
  );
  test('newer local choice survives an in-flight acknowledgment', () async {
    remote.gate = Completer<void>();
    await queue.choose(message, ReactionCode.heart);
    now = now.add(const Duration(seconds: 1));
    await queue.resume();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    now = now.add(const Duration(seconds: 1));
    await queue.choose(message, ReactionCode.fire);
    queue.pause();
    remote.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final pending = (await cache.readReactionQueue('me')).single;
    expect(pending.code, 'fire');
    expect(pending.expectedRevision, 1);
    expect(
      (await cache.readReactionState(
        'message',
        ownerUserId: 'me',
      )).codeFor('me'),
      ReactionCode.fire,
    );
    remote.gate = null;
    await due();
    expect(remote.calls, [ReactionCode.heart, ReactionCode.fire]);
  });
  test(
    'distant metadata does not pollute history; deletion clears intent',
    () async {
      await queue.hydrate([
        message.copyWith(
          reactionState: const MessageReactionState(
            version: 1,
            reactions: [
              MessageReaction(userId: 'peer', code: ReactionCode.heart),
            ],
          ),
        ),
      ]);
      expect(await cache.readMessages('chat', currentUserId: 'me'), isEmpty);
      await queue.choose(message, ReactionCode.like);
      await cache.removeMessages('chat', {'message'}, ownerUserId: 'me');
      await queue.accept(
        'chat',
        'message',
        const MessageReactionState(version: 3),
      );
      expect(await cache.readReactionQueue('me'), isEmpty);
      expect(
        (await cache.readReactionState('message', ownerUserId: 'me')).version,
        0,
      );
    },
  );
  test('old account event cannot write to the new account', () async {
    final old = account.capture();
    account.setAuthenticatedUser('other');
    await expectLater(
      queue.accept(
        'chat',
        'message',
        const MessageReactionState(version: 2),
        session: old,
      ),
      throwsA(isA<StaleAccountSessionException>()),
    );
    expect(
      (await cache.readReactionState('message', ownerUserId: 'other')).version,
      0,
    );
  });
  test(
    'rate limit backs off the whole queue instead of bursting other messages',
    () async {
      remote.error = StateError('42901 reaction_rate_limited');
      await queue.choose(message, ReactionCode.fire);
      await queue.choose(message.copyWith(id: 'second'), ReactionCode.heart);
      now = now.add(const Duration(seconds: 1));
      await queue.resume();
      await Future<void>.delayed(const Duration(milliseconds: 160));
      queue.pause();
      expect(remote.calls, hasLength(1));
      final pending = await cache.readReactionQueue('me');
      expect(pending, hasLength(2));
      expect(pending.where((p) => p.attempts == 1), hasLength(1));
      expect(
        pending.firstWhere((p) => p.attempts == 1).nextAttemptAt.isAfter(now),
        isTrue,
      );
    },
  );
  test(
    'terminal denial rolls back optimistic choice without an extra RPC',
    () async {
      remote.error = StateError('42501 conversation_blocked');
      await queue.choose(message, ReactionCode.like);
      await due();
      expect(remote.calls, hasLength(1));
      expect(await cache.readReactionQueue('me'), isEmpty);
      expect(
        (await cache.readReactionState('message', ownerUserId: 'me')).reactions,
        isEmpty,
      );
    },
  );
  test(
    'reaction cache changes update a watched message without replacing its body',
    () async {
      await cache.upsertMessages([message], ownerUserId: 'me');
      final emissions = <List<ChatMessage>>[];
      final subscription = cache
          .watchMessages('chat', currentUserId: 'me')
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await queue.choose(message, ReactionCode.cry);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(emissions.last.single.text, 'hello');
      expect(
        emissions.last.single.reactionState.codeFor('me'),
        ReactionCode.cry,
      );
      await due();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        emissions.last.single.reactionState.codeFor('me'),
        ReactionCode.cry,
      );
    },
  );
  test(
    'upgrading schema 24 preserves existing history and creates reaction tables',
    () async {
      final connection = sqlite.sqlite3.openInMemory();
      var migrated = AppDatabase.forTesting(
        NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
      );
      try {
        var migratedCache = ChatCacheDataSource(
          database: migrated,
          userIdProvider: () => 'me',
        );
        await migratedCache.upsertMessages([message], ownerUserId: 'me');
        await migrated.customStatement(
          'DROP TABLE cached_message_reaction_states',
        );
        await migrated.customStatement('DROP TABLE pending_message_reactions');
        await migrated.customStatement('PRAGMA user_version = 24');
        await migrated.close();
        migrated = AppDatabase.forTesting(
          NativeDatabase.opened(connection, closeUnderlyingOnClose: false),
        );
        migratedCache = ChatCacheDataSource(
          database: migrated,
          userIdProvider: () => 'me',
        );
        expect(
          (await migratedCache.readMessages(
            'chat',
            currentUserId: 'me',
          )).single.text,
          'hello',
        );
        expect(await migratedCache.readReactionQueue('me'), isEmpty);
        expect(
          (await migratedCache.readReactionState(
            'message',
            ownerUserId: 'me',
          )).version,
          0,
        );
      } finally {
        await migrated.close();
        connection.close();
      }
    },
  );
}

class _Remote extends ChatRemoteDataSource {
  _Remote() : super(client: SupabaseClient('http://localhost', 'test'));
  final calls = <ReactionCode?>[];
  final ids = <String>[];
  Object? error;
  Completer<void>? gate;
  @override
  Future<({bool applied, MessageReactionState state})> setReaction({
    required String chatId,
    required String messageId,
    required String operationId,
    required ReactionCode? code,
    required int expectedRevision,
  }) async {
    calls.add(code);
    ids.add(operationId);
    await gate?.future;
    if (error != null) throw error!;
    final version = expectedRevision + 1;
    return (
      applied: true,
      state: MessageReactionState(
        version: version,
        userRevisions: {'me': version},
        reactions: [
          if (code != null) MessageReaction(userId: 'me', code: code),
        ],
      ),
    );
  }
}
