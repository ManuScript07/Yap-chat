import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/user_data_cleanup_coordinator.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/repositories/chat/abstract_local_media_repository.dart';

void main() {
  test('keeps a durable marker until account cleanup succeeds', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final localMedia = _CleanupLocalMediaRepository();
    final coordinator = UserDataCleanupCoordinator(
      preferences: preferences,
      environment: 'test',
      accountSessionController: AccountSessionController(
        initialUserId: 'account-a',
      ),
      localMediaRepository: localMedia,
      mediaCache: MediaCacheService(database: database),
      talker: Talker(),
    );

    await coordinator.markPending('account-a');
    expect(coordinator.isPending('account-a'), isTrue);

    await coordinator.resumePendingCleanup();

    expect(localMedia.clearedUsers, ['account-a']);
    expect(coordinator.isPending('account-a'), isFalse);
  });

  test('retains a marker when account cleanup fails', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final coordinator = UserDataCleanupCoordinator(
      preferences: preferences,
      environment: 'test',
      accountSessionController: AccountSessionController(),
      localMediaRepository: _CleanupLocalMediaRepository(shouldFail: true),
      mediaCache: MediaCacheService(database: database),
      talker: Talker(),
    );

    await coordinator.markPending('account-a');
    await coordinator.resumePendingCleanup();

    expect(coordinator.isPending('account-a'), isTrue);
  });
}

class _CleanupLocalMediaRepository implements ILocalMediaRepository {
  _CleanupLocalMediaRepository({this.shouldFail = false});

  final bool shouldFail;
  final List<String> clearedUsers = [];

  @override
  Future<void> clearUser(String ownerUserId) async {
    if (shouldFail) throw StateError('cleanup failed');
    clearedUsers.add(ownerUserId);
  }

  @override
  Future<void> clearPendingChatId() async {}

  @override
  Future<void> collectGarbage() async {}

  @override
  Future<String?> consumePendingChatId() async => null;

  @override
  Future<String?> consumePendingMedia() async => null;

  @override
  Future<void> deleteMedia(String path) async {}

  @override
  List<String> getRecentMediaPaths() => const [];

  @override
  Future<String?> persistMedia(String sourcePath) async => null;

  @override
  Future<void> savePendingChatId(String chatId) async {}

  @override
  Future<void> savePendingMedia(String path) async {}
}
