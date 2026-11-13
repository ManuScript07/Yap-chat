import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/settings.dart';

void main() {
  for (final brokenCache in [false, true]) {
    test(
      'confirmed hide reaches observers even with cache failure=$brokenCache',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final remote = _Remote();
        final cache = brokenCache
            ? _BrokenCache(database: db)
            : SettingsCacheDataSource(database: db);
        final session = AccountSessionController(initialUserId: 'a');
        final repo = SettingsRepository(
          cache: cache,
          remote: remote,
          accountSessionController: session,
        );
        final values = <bool>[];
        final sub = repo.watchNearbyVisibility().listen(values.add);
        addTearDown(sub.cancel);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await repo.updateSearchPrivacySetting(
          SearchPrivacySettingKey.nearby,
          false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(values.last, isFalse);
        session.setAuthenticatedUser('b');
        await repo.updateSearchPrivacySetting(
          SearchPrivacySettingKey.nearby,
          true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          values.last,
          isFalse,
          reason: 'old account observer must not receive new account events',
        );
      },
    );
  }
  test(
    'old background settings response cannot undo confirmed hiding',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = SettingsCacheDataSource(database: db);
      final remote = _Remote()..readGate = Completer<SearchPrivacySettings>();
      final repo = SettingsRepository(
        cache: cache,
        remote: remote,
        accountSessionController: AccountSessionController(initialUserId: 'a'),
      );
      final pending = repo.refreshSearchPrivacySettings();
      await repo.updateSearchPrivacySetting(
        SearchPrivacySettingKey.nearby,
        false,
      );
      remote.readGate!.complete(const SearchPrivacySettings());
      expect((await pending).nearbyVisible, isFalse);
      expect((await cache.read('a'))!.nearbyVisible, isFalse);
    },
  );
}

class _Remote extends SettingsRemoteDataSource {
  _Remote() : super(client: SupabaseClient('http://localhost:54321', 'test'));
  Completer<SearchPrivacySettings>? readGate;
  @override
  Future<SearchPrivacySettings> fetchSearchPrivacySettings() =>
      readGate?.future ?? Future.value(const SearchPrivacySettings());
  @override
  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  ) async => const SearchPrivacySettings().withValue(key, value);
}

class _BrokenCache extends SettingsCacheDataSource {
  const _BrokenCache({required super.database});
  @override
  Future<void> write(
    String ownerUserId,
    SearchPrivacySettings settings,
  ) async => throw StateError('disk full');
}
