import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/repositories/chat/local_media_repository.dart';

void main() {
  late Directory temporary;
  late Directory documents;
  late AppDatabase database;
  late SharedPreferences preferences;
  late String? currentUserId;
  late LocalMediaRepository repository;
  late AccountSessionController accountSessionController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    temporary = await Directory.systemTemp.createTemp('yap-local-media-test');
    documents = Directory('${temporary.path}/documents');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    currentUserId = 'alice';
    accountSessionController = AccountSessionController(
      initialUserId: currentUserId,
    );
    repository = LocalMediaRepository(
      preferences: preferences,
      database: database,
      ownerUserIdProvider: () => currentUserId,
      environment: 'test',
      accountSessionController: accountSessionController,
      documentsDirectoryProvider: () async => documents,
    );
  });

  tearDown(() async {
    await database.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('isolates recent media and cleanup by owner', () async {
    final alicePath = await repository.persistMedia(
      await _source(temporary, 1),
    );
    expect(alicePath, isNotNull);

    currentUserId = 'bob';
    accountSessionController.setAuthenticatedUser(currentUserId);
    expect(repository.getRecentMediaPaths(), isEmpty);
    final bobPath = await repository.persistMedia(await _source(temporary, 2));
    expect(bobPath, isNotNull);

    currentUserId = 'alice';
    accountSessionController.setAuthenticatedUser(currentUserId);
    expect(repository.getRecentMediaPaths(), [alicePath]);
    await repository.clearUser('alice');
    expect(await File(alicePath!).exists(), isFalse);

    currentUserId = 'bob';
    accountSessionController.setAuthenticatedUser(currentUserId);
    expect(repository.getRecentMediaPaths(), [bobPath]);
    expect(await File(bobPath!).exists(), isTrue);
  });

  test(
    'keeps evicted source while an outbox operation references it',
    () async {
      final protectedPath = await repository.persistMedia(
        await _source(temporary, 0),
      );
      await database
          .into(database.pendingChatOperations)
          .insert(
            PendingChatOperationsCompanion.insert(
              ownerUserId: 'alice',
              id: 'pending-message',
              chatId: 'chat',
              type: 'image',
              payloadJson: jsonEncode({
                'image_paths': [protectedPath],
              }),
              createdAt: DateTime.now().toUtc(),
            ),
          );

      for (
        var index = 1;
        index <= LocalMediaRepository.maxRecentMediaCount;
        index++
      ) {
        await repository.persistMedia(await _source(temporary, index));
      }
      await repository.collectGarbage();
      expect(repository.getRecentMediaPaths(), hasLength(50));
      expect(repository.getRecentMediaPaths(), isNot(contains(protectedPath)));
      expect(await File(protectedPath!).exists(), isTrue);

      await database.delete(database.pendingChatOperations).go();
      await repository.collectGarbage();
      expect(await File(protectedPath).exists(), isFalse);
    },
  );
}

Future<String> _source(Directory directory, int index) async {
  final file = File('${directory.path}/source-$index.jpg');
  await file.writeAsBytes([index & 0xff, 1, 2, 3]);
  return file.path;
}
