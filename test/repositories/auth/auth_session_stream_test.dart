import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/repositories/auth/auth_repository.dart';

const _userA = '11111111-1111-4111-8111-111111111111';
const _userB = '22222222-2222-4222-8222-222222222222';

Session _session(String userId, {String name = 'User'}) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': userId,
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
      'id': userId,
      'aud': 'authenticated',
      'user_metadata': {'name': name},
    },
  })!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late AuthRepository repository;
  late List<AuthSession?> sessions;
  late List<Object> errors;
  StreamSubscription<AuthSession?>? subscription;
  int requests = 0;
  int expectedRequests = 0;

  setUp(() {
    requests = 0;
    expectedRequests = 0;
    client = SupabaseClient(
      'http://127.0.0.1:1',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests++;
        if (request.url.path.endsWith('/logout')) {
          return http.Response('{}', 200);
        }
        throw StateError('This test must not access the network');
      }),
    );
    repository = AuthRepository(
      client: client,
      redirectUrl: 'yapchat://login-callback/',
    );
    sessions = [];
    errors = [];
  });

  tearDown(() async {
    await subscription?.cancel();
    subscription = null;
    await client.dispose();
    expect(requests, expectedRequests);
  });

  Future<void> observe() async {
    subscription = repository.observeSession().listen(
      sessions.add,
      onError: (Object error) => errors.add(error),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> notify(AuthChangeEvent event, {Session? session}) async {
    // Inject SDK events without calling Auth or Realtime endpoints.
    // ignore: invalid_use_of_internal_member
    client.auth.notifyAllSubscribers(event, session: session);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'restored session seeds distinct before initial event is dropped',
    () async {
      await client.auth.setInitialSession(
        jsonEncode(_session(_userA).toJson()),
      );
      await observe();
      expect(sessions, isEmpty);
      await notify(AuthChangeEvent.tokenRefreshed);
      await notify(AuthChangeEvent.signedIn);
      await notify(AuthChangeEvent.tokenRefreshed);
      expect(sessions, isEmpty);
    },
  );

  test('null startup does not suppress a subsequent real sign-in', () async {
    await notify(AuthChangeEvent.initialSession);
    await observe();
    await notify(AuthChangeEvent.signedIn, session: _session(_userA));
    expect(sessions.map((session) => session?.userId), [_userA]);
  });

  test(
    'sign-out and return to the startup account are not suppressed',
    () async {
      await client.auth.setInitialSession(
        jsonEncode(_session(_userA).toJson()),
      );
      await observe();
      // A real SDK sign-out clears currentSession; its endpoint is mocked.
      expectedRequests = 1;
      await client.auth.signOut(scope: SignOutScope.local);
      await Future<void>.delayed(Duration.zero);
      await client.auth.setInitialSession(
        jsonEncode(_session(_userA).toJson()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sessions.map((session) => session?.userId), [null, _userA]);
    },
  );

  test(
    'changed account and changed metadata are delivered once each',
    () async {
      await client.auth.setInitialSession(
        jsonEncode(_session(_userA).toJson()),
      );
      await observe();
      final changed = _session(_userA, name: 'Updated');
      await notify(AuthChangeEvent.userUpdated, session: changed);
      await notify(AuthChangeEvent.tokenRefreshed, session: changed);
      await notify(AuthChangeEvent.signedIn, session: _session(_userB));
      expect(sessions.map((session) => session?.userId), [_userA, _userB]);
      expect(sessions.first?.displayName, 'Updated');
    },
  );

  test(
    'an error does not clear the duplicate baseline or swallow changes',
    () async {
      await client.auth.setInitialSession(
        jsonEncode(_session(_userA).toJson()),
      );
      await observe();
      final failure = StateError('offline');
      // ignore: invalid_use_of_internal_member
      client.auth.notifyException(failure);
      await Future<void>.delayed(Duration.zero);
      await notify(AuthChangeEvent.tokenRefreshed);
      await notify(AuthChangeEvent.signedIn, session: _session(_userB));
      expect(errors, [failure]);
      expect(sessions.map((session) => session?.userId), [_userB]);
    },
  );

  test(
    'first changed event does not cause a later return to be dropped',
    () async {
      await client.auth.setInitialSession(
        jsonEncode(_session(_userA).toJson()),
      );
      // Capture A, but change the replay before the stream is subscribed.
      final stream = repository.observeSession();
      await client.auth.setInitialSession(
        jsonEncode(_session(_userB).toJson()),
      );
      subscription = stream.listen(sessions.add);
      await Future<void>.delayed(Duration.zero);
      await notify(AuthChangeEvent.signedIn, session: _session(_userA));
      expect(sessions.map((session) => session?.userId), [_userB, _userA]);
    },
  );

  test('refresh cannot reopen a locally restricted account boundary', () async {
    await client.auth.setInitialSession(jsonEncode(_session(_userA).toJson()));
    final boundary = AccountSessionController(initialUserId: _userA);
    repository = AuthRepository(
      client: client,
      redirectUrl: 'yapchat://login-callback/',
      accountSessionController: boundary,
    );
    await observe();
    boundary.setAuthenticatedUser(null);
    await notify(AuthChangeEvent.tokenRefreshed);
    expect(boundary.userId, isNull);
    await notify(
      AuthChangeEvent.userUpdated,
      session: _session(_userA, name: 'Changed'),
    );
    expect(boundary.userId, isNull);
    await notify(AuthChangeEvent.signedIn, session: _session(_userB));
    expect(boundary.userId, _userB);
  });
}
