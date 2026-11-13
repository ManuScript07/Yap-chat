import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  for (final count in [6, 11]) {
    test(
      '$count images report only fully queued batches and retry the remainder',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final account = AccountSessionController(initialUserId: 'owner');
        final cache = _FailingCache(db);
        final chats = ChatsCacheDataSource(
          database: db,
          userIdProvider: () => 'owner',
        );
        final media = MediaCacheService(database: db);
        addTearDown(media.dispose);
        final config = AppConfig(
          environment: AppEnvironment.local,
          preferences: await SharedPreferences.getInstance(),
          talker: Talker(settings: TalkerSettings(enabled: false)),
          env: const {},
          database: db,
          accountSessionController: account,
        );
        final remote = ChatRemoteDataSource(
          client: SupabaseClient('http://localhost', 'test-key'),
        );
        final sync = ConversationSyncService(
          cache: cache,
          remote: remote,
          hydrator: ChatMessageHydrator(
            config: config,
            remote: remote,
            mediaCache: media,
          ),
          chatsCache: chats,
          accountSessionController: account,
        );
        final repository = ChatRepository(
          config: config,
          cache: cache,
          remote: remote,
          mediaProcessor: const ChatMediaProcessor(),
          mediaCache: media,
          syncService: sync,
          chatsCache: chats,
          localMediaRepository: _Media(),
          accountSessionController: account,
        );
        addTearDown(repository.pauseNetwork);
        await repository.pauseNetwork();
        await chats.replaceAll([
          Chat(
            id: 'chat',
            userName: 'Peer',
            lastMessage: '',
            lastMessageTime: DateTime(2026),
            unreadCount: 0,
            isOnline: false,
            isLastMessageFromMe: false,
          ),
        ]);
        final paths = [for (var i = 0; i < count; i++) '/local/photo-$i.jpg'];
        PartialImageSendException? partial;
        try {
          await repository.sendImages('chat', paths, replyToMessageId: 'reply');
          fail('Expected second batch failure');
        } on PartialImageSendException catch (error) {
          partial = error;
        }
        expect(partial.queuedPaths, paths.take(5));
        expect(partial.remainingPaths, paths.skip(5));
        expect(partial.cause, isA<StateError>());
        final first = await cache.readPendingOperations();
        expect(first, hasLength(1));
        final firstId = first.single.id;
        expect(first.single.payload['image_paths'], paths.take(5).toList());
        expect(first.single.payload['reply_to_message_id'], 'reply');
        await repository.sendImages('chat', partial.remainingPaths);
        final all = await cache.readPendingOperations();
        expect(all, hasLength((count / 5).ceil()));
        expect(all.first.id, firstId);
        final queued = all
            .expand((op) => (op.payload['image_paths'] as List).cast<String>())
            .toList();
        expect(queued, paths);
        expect(queued.toSet(), hasLength(count));
        expect(
          all.skip(1).every((op) => op.payload['reply_to_message_id'] == null),
          true,
        );
        expect(await db.select(db.cachedMessages).get(), hasLength(all.length));
      },
    );
  }
}

class _FailingCache extends ChatCacheDataSource {
  _FailingCache(AppDatabase db)
    : super(database: db, userIdProvider: () => 'owner');
  int images = 0;
  @override
  Future<void> upsertMessage(
    ChatMessage message, {
    bool isPending = false,
    String? ownerUserId,
  }) {
    if (message.type == MessageType.image && ++images == 2) {
      throw StateError('local write refused');
    }
    return super.upsertMessage(
      message,
      isPending: isPending,
      ownerUserId: ownerUserId,
    );
  }
}

class _Media implements ILocalMediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
