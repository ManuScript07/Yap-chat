import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/app/local_pagination_launch.dart';

String key(String role) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
void main() {
  const owner = '10000000-0000-0000-0000-000000000001';
  LocalPaginationLaunch lab({
    String url = 'http://127.0.0.1:54321',
    String? apiKey,
    String user = owner,
    String token = 'local-refresh',
  }) => LocalPaginationLaunch(
    url: url,
    publishableKey: apiKey ?? key('anon'),
    ownerId: user,
    refreshToken: token,
  );
  test(
    'normal launch preserves its exact environment and needs no lab session',
    () {
      const empty = LocalPaginationLaunch(
        url: '',
        publishableKey: '',
        ownerId: '',
        refreshToken: '',
      );
      final base = {
        'APP_ENV': 'prod',
        'SUPABASE_URL': 'https://production.example',
      };
      expect(empty.enabled, false);
      expect(empty.apply(base, release: true), same(base));
    },
  );
  test(
    'local overrides force real local repositories without exposing refresh token in config',
    () {
      final result = lab().apply({
        'APP_ENV': 'prod',
        'SUPABASE_URL': 'https://production.example',
        'OTHER': 'preserved',
      }, release: false);
      expect(result['APP_ENV'], 'local');
      expect(result['SUPABASE_URL'], 'http://127.0.0.1:54321');
      expect(result['OTHER'], 'preserved');
      expect(result.values, isNot(contains('local-refresh')));
    },
  );
  for (final url in [
    'https://x.supabase.co',
    'http://192.168.1.2:54321',
    'http://127.0.0.1.evil.test',
    'http://127.0.0.1:54321/path',
    'http://user:pass@127.0.0.1:54321',
    'http://127.0.0.1:54321?x=1',
  ]) {
    test(
      'rejects non-local or ambiguous URL $url',
      () => expect(
        () => lab(url: url).apply({}, release: false),
        throwsStateError,
      ),
    );
  }
  test(
    'release never accepts lab settings',
    () => expect(() => lab().apply({}, release: true), throwsStateError),
  );
  test('rejects admin and secret keys', () {
    for (final value in [key('service_role'), 'sb_secret_fake', 'invalid']) {
      expect(
        () => lab(apiKey: value).apply({}, release: false),
        throwsStateError,
      );
    }
  });
  test('rejects incomplete or corrupted test identity', () {
    expect(() => lab(token: '').apply({}, release: false), throwsStateError);
    expect(
      () => lab(user: '-' * 36).apply({}, release: false),
      throwsStateError,
    );
  });
  test('supports public keys and the Android emulator loopback', () {
    expect(
      lab(
        url: 'http://10.0.2.2:54321',
        apiKey: 'sb_publishable_test',
      ).apply({}, release: false)['APP_ENV'],
      'local',
    );
  });
}
