import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/settings.dart';

void main() {
  test(
    'upgrading v29 keeps cached settings and defaults nearby to visible',
    () async {
      final dir = await Directory.systemTemp.createTemp('nearby-privacy-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.sqlite');
      final original = AppDatabase.forTesting(NativeDatabase(file));
      await SettingsCacheDataSource(database: original).write(
        'a',
        const SearchPrivacySettings(
          searchByUsername: false,
          shareDistance: false,
        ),
      );
      await original.customStatement(
        'ALTER TABLE cached_search_privacy_settings DROP COLUMN nearby_visible',
      );
      await original.customStatement('PRAGMA user_version = 29');
      await original.close();
      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(upgraded.close);
      final cache = SettingsCacheDataSource(database: upgraded);
      final settings = await cache.read('a');
      expect(
        settings,
        const SearchPrivacySettings(
          searchByUsername: false,
          shareDistance: false,
        ),
      );
      await cache.write('a', settings!.copyWith(nearbyVisible: false));
      expect((await cache.read('a'))!.nearbyVisible, isFalse);
    },
  );
}
