import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_message_hydrator.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';

void main() {
  test(
    'restores an already cached chat image without a storage download',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final temporary = await Directory.systemTemp.createTemp(
        'yap-hydrator-test',
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      addTearDown(() async {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final mediaCache = MediaCacheService(
        database: database,
        environment: 'test',
        cacheDirectoryProvider: () async =>
            Directory('${temporary.path}/cache'),
        supportDirectoryProvider: () async =>
            Directory('${temporary.path}/support'),
      );
      addTearDown(mediaCache.dispose);
      const storagePath = 'chat/owner/message/0.jpg';
      final cachedPath = await mediaCache.storeBytes(
        ownerUserId: 'owner',
        bucket: 'chat-images',
        storagePath: storagePath,
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );
      final account = AccountSessionController(initialUserId: 'owner');
      final remote = ChatRemoteDataSource(
        client: SupabaseClient('http://localhost', 'test-key'),
      );
      final hydrator = ChatMessageHydrator(
        config: AppConfig(
          environment: AppEnvironment.local,
          preferences: preferences,
          talker: Talker(),
          env: const {},
          database: database,
          accountSessionController: account,
        ),
        remote: remote,
        mediaCache: mediaCache,
      );

      final hydrated = await hydrator.hydrate(
        ChatMessage(
          id: 'message',
          chatId: 'chat',
          senderId: 'peer',
          text: '',
          timestamp: DateTime.utc(2026),
          isMine: false,
          type: MessageType.image,
          mediaStoragePaths: const [storagePath],
        ),
        ownerUserId: 'owner',
      );

      expect(hydrated.mediaUrls, [cachedPath]);
      expect(await File(hydrated.mediaUrls.single).readAsBytes(), [1, 2, 3]);
    },
  );
}
