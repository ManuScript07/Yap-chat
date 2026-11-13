import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/repositories/auth/auth_repository.dart';
import 'package:yap_chat/repositories/auth/oauth_attempt_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Yandex OAuth uses an in-app browser and requests account choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-publishable-key',
      );
      addTearDown(client.dispose);

      OAuthProvider? capturedProvider;
      String? capturedRedirectTo;
      LaunchMode? capturedLaunchMode;
      Map<String, String>? capturedQueryParams;

      final repository = AuthRepository(
        client: client,
        redirectUrl: 'yapchat://login-callback/',
        oauthAttemptCoordinator: OAuthAttemptCoordinator(
          preferences: preferences,
          namespace: 'test',
          idFactory: () => 'attempt-id',
        ),
        oauthSignInLauncher:
            (
              provider, {
              redirectTo,
              scopes,
              authScreenLaunchMode = LaunchMode.platformDefault,
              queryParams,
            }) async {
              capturedProvider = provider;
              capturedRedirectTo = redirectTo;
              capturedLaunchMode = authScreenLaunchMode;
              capturedQueryParams = queryParams;
              return true;
            },
      );

      await repository.signInWithYandex();

      expect(capturedProvider, const OAuthProvider('custom:yandex'));
      final redirect = Uri.parse(capturedRedirectTo!);
      expect(redirect.scheme, 'yapchat');
      expect(redirect.host, 'login-callback');
      expect(
        redirect.queryParameters[OAuthAttemptCoordinator.attemptQueryParameter],
        'attempt-id',
      );
      expect(capturedLaunchMode, LaunchMode.inAppBrowserView);
      expect(capturedQueryParams, const {'force_confirm': 'yes'});
    },
  );

  test('failed browser launch invalidates its callback attempt', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final coordinator = OAuthAttemptCoordinator(
      preferences: preferences,
      namespace: 'test',
      idFactory: () => 'failed-attempt',
    );
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-publishable-key',
    );
    addTearDown(client.dispose);

    final repository = AuthRepository(
      client: client,
      redirectUrl: 'yapchat://login-callback/',
      oauthAttemptCoordinator: coordinator,
      oauthSignInLauncher:
          (
            provider, {
            redirectTo,
            scopes,
            authScreenLaunchMode = LaunchMode.platformDefault,
            queryParams,
          }) async => false,
    );

    await expectLater(repository.signInWithYandex(), throwsStateError);
    expect(
      coordinator.tryAcceptCallback(
        Uri.parse(
          'yapchat://login-callback/?auth_attempt=failed-attempt&code=code',
        ),
      ),
      isFalse,
    );
  });
}
