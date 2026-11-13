import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_message_hydrator.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chat/conversation_sync_service.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';

void main() {
  test(
    'keeps open chats across background but scopes them to the account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final accountController = AccountSessionController(
        initialUserId: 'account-a',
      );
      final client = SupabaseClient('http://localhost', 'test-key');
      final remote = ChatRemoteDataSource(client: client);
      final mediaCache = MediaCacheService(database: database);
      addTearDown(mediaCache.dispose);
      final service = ConversationSyncService(
        cache: ChatCacheDataSource(
          database: database,
          userIdProvider: () => accountController.userId!,
        ),
        remote: remote,
        hydrator: ChatMessageHydrator(
          config: AppConfig(
            environment: AppEnvironment.prod,
            preferences: preferences,
            talker: Talker(),
            env: const {},
            database: database,
            accountSessionController: accountController,
          ),
          remote: remote,
          mediaCache: mediaCache,
        ),
        chatsCache: ChatsCacheDataSource(
          database: database,
          userIdProvider: () => accountController.userId!,
        ),
        accountSessionController: accountController,
      );

      final accountA = accountController.capture();
      service.openConversation('chat-a', session: accountA);
      expect(service.openConversationIds, {'chat-a'});
      expect(service.isConversationOpen('chat-a'), isTrue);

      // A lifecycle pause does not mutate the service, so the open chat remains.
      expect(service.openConversationIds, {'chat-a'});

      accountController.setAuthenticatedUser(null);
      accountController.setAuthenticatedUser('account-b');
      expect(service.openConversationIds, isEmpty);

      final accountB = accountController.capture();
      service.openConversation('chat-b', session: accountB);
      service.closeConversation('chat-a', session: accountA);
      expect(service.openConversationIds, {'chat-b'});
    },
  );
}
