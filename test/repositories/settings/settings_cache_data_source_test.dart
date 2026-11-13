import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/settings_cache_data_source.dart';

void main() {
  test(
    'nearby preference persists independently and streams only own account',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final cache = SettingsCacheDataSource(database: database);
      final values = <bool>[];
      final sub = cache.watchNearbyVisibility('a').listen(values.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cache.write('a', const SearchPrivacySettings(nearbyVisible: false));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cache.write('b', const SearchPrivacySettings(nearbyVisible: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await cache.read('a'))!.nearbyVisible, isFalse);
      expect(values, [true, false]);
      await cache.write('a', const SearchPrivacySettings());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(values, [true, false, true]);
    },
  );

  test('keeps account privacy settings isolated by account', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = SettingsCacheDataSource(database: database);

    await cache.write(
      'account-a',
      const SearchPrivacySettings(
        searchByUsername: false,
        lastSeenVisibility: LastSeenVisibility.nobody,
        sharePreciseLocation: false,
        shareDistance: false,
      ),
    );
    await cache.write(
      'account-b',
      const SearchPrivacySettings(
        searchByPhone: false,
        lastSeenVisibility: LastSeenVisibility.friends,
        sharePreciseLocation: true,
        shareDistance: false,
      ),
    );

    expect(
      await cache.read('account-a'),
      const SearchPrivacySettings(
        searchByUsername: false,
        lastSeenVisibility: LastSeenVisibility.nobody,
        sharePreciseLocation: false,
        shareDistance: false,
      ),
    );
    expect(
      await cache.read('account-b'),
      const SearchPrivacySettings(
        searchByPhone: false,
        lastSeenVisibility: LastSeenVisibility.friends,
        sharePreciseLocation: true,
        shareDistance: false,
      ),
    );

    await cache.replacePreciseLocationExclusions('account-a', {'friend-a'});
    await cache.replacePreciseLocationExclusions('account-b', {'friend-b'});
    expect(await cache.readPreciseLocationExclusions('account-a'), {
      'friend-a',
    });
    expect(await cache.readPreciseLocationExclusions('account-b'), {
      'friend-b',
    });

    await cache.writeAppLanguage('account-a', AppLanguage.russian);
    await cache.writeAppLanguage('account-b', AppLanguage.english);
    expect(await cache.readAppLanguage('account-a'), AppLanguage.russian);
    expect(await cache.readAppLanguage('account-b'), AppLanguage.english);

    await cache.clearUser('account-a');
    expect(await cache.read('account-a'), isNull);
    expect(await cache.readPreciseLocationExclusions('account-a'), isEmpty);
    expect(await cache.readAppLanguage('account-a'), isNull);
    expect(await cache.read('account-b'), isNotNull);
    expect(await cache.readPreciseLocationExclusions('account-b'), {
      'friend-b',
    });
    expect(await cache.readAppLanguage('account-b'), AppLanguage.english);
  });
}
