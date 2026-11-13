import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/repositories/auth/auth_repository.dart';

const _userId = '11111111-1111-4111-8111-111111111111';

Session _session(Map<String, dynamic> metadata) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': _userId,
            'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          }),
        ),
      )
      .replaceAll('=', '');
  return Session.fromJson({
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
    'refresh_token': 'test-refresh',
    'token_type': 'bearer',
    'user': {
      'id': _userId,
      'aud': 'authenticated',
      'email': 'yandex-user@example.test',
      'user_metadata': metadata,
    },
  })!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late AuthRepository repository;
  var requests = 0;

  setUp(() {
    requests = 0;
    client = SupabaseClient(
      'http://127.0.0.1:1',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) async {
        requests++;
        throw StateError('Mapping metadata must not access the network');
      }),
    );
    repository = AuthRepository(
      client: client,
      redirectUrl: 'yapchat://login-callback/',
    );
  });

  tearDown(() async {
    await client.dispose();
    expect(requests, 0);
  });

  Future<void> restore(Map<String, dynamic> metadata) =>
      client.auth.setInitialSession(jsonEncode(_session(metadata).toJson()));

  for (final key in ['birth_date', 'birthdate', 'birthday']) {
    test('restores a full date from $key without a request', () async {
      await restore({key: '2007-02-28'});
      expect(repository.currentSession?.birthDate, DateTime(2007, 2, 28));
      expect(repository.currentSession?.email, 'yandex-user@example.test');
    });
  }

  test('keeps existing alias priority and accepts leap days', () async {
    await restore({
      'birth_date': '2000-02-29',
      'birthdate': '2007-02-28',
      'birthday': '2001-01-01',
    });
    expect(repository.currentSession?.birthDate, DateTime(2000, 2, 29));
  });

  test('uses the next valid alias when an earlier value is unusable', () async {
    await restore({
      'birth_date': '0000-02-28',
      'birthdate': '2007-02-31',
      'birthday': ' 2000-02-29 ',
    });
    expect(repository.currentSession?.birthDate, DateTime(2000, 2, 29));
  });

  for (final value in <Object?>[
    null,
    '',
    'not-a-date',
    '0000-02-28',
    '2007-00-28',
    '2007-02-00',
    '2007-02-29',
    '2007-02-31',
    '2007-13-01',
    '2007-2-28',
    '2007-02-28T00:00:00Z',
    '9999-01-01',
    2007,
  ]) {
    test('does not invent a birth date from $value', () async {
      await restore({'birthdate': value});
      expect(repository.currentSession?.birthDate, isNull);
    });
  }

  test(
    'new birthday metadata reaches the stream once, not every refresh',
    () async {
      final sessions = <AuthSession?>[];
      final subscription = repository.observeSession().listen(sessions.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      final session = _session({'birthdate': '2007-02-28'});
      // ignore: invalid_use_of_internal_member
      client.auth.notifyAllSubscribers(
        AuthChangeEvent.signedIn,
        session: session,
      );
      await Future<void>.delayed(Duration.zero);
      // ignore: invalid_use_of_internal_member
      client.auth.notifyAllSubscribers(
        AuthChangeEvent.tokenRefreshed,
        session: session,
      );
      await Future<void>.delayed(Duration.zero);
      expect(sessions, hasLength(1));
      expect(sessions.single?.birthDate, DateTime(2007, 2, 28));
    },
  );
}
