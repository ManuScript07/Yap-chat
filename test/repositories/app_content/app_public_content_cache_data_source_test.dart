import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/app_content/app_public_content_cache_data_source.dart';

void main() {
  const key = 'app_public_content.prod';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists the manifest together with its local download time', () async {
    final preferences = await SharedPreferences.getInstance();
    final source = AppPublicContentCacheDataSource(
      preferences: preferences,
      environment: 'prod',
    );
    final fetchedAt = DateTime.utc(2026, 9, 8, 12);

    await source.write(
      const AppPublicContent(supportEmail: 'support@example.com'),
      fetchedAt: fetchedAt,
    );

    final cached = await source.read();
    expect(cached?.content.supportEmail, 'support@example.com');
    expect(cached?.fetchedAt, fetchedAt);
  });

  test('keeps the legacy cache readable but marks it stale', () async {
    SharedPreferences.setMockInitialValues({
      key: '{"supportEmail":"support@example.com"}',
    });
    final source = AppPublicContentCacheDataSource(
      preferences: await SharedPreferences.getInstance(),
      environment: 'prod',
    );

    final cached = await source.read();

    expect(cached?.content.supportEmail, 'support@example.com');
    expect(cached?.fetchedAt, isNull);
  });

  test('removes a malformed manifest cache entry', () async {
    SharedPreferences.setMockInitialValues({key: 'not-json'});
    final preferences = await SharedPreferences.getInstance();
    final source = AppPublicContentCacheDataSource(
      preferences: preferences,
      environment: 'prod',
    );

    expect(await source.read(), isNull);
    expect(preferences.containsKey(key), isFalse);
  });
}
