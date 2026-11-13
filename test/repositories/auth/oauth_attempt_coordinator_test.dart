import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/repositories/auth/oauth_attempt_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late List<String> attemptIds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    attemptIds = ['attempt-a', 'attempt-b', 'attempt-c'];
  });

  OAuthAttemptCoordinator createCoordinator() => OAuthAttemptCoordinator(
    preferences: preferences,
    namespace: 'test',
    idFactory: () => attemptIds.removeAt(0),
  );

  test(
    'accepts only the current callback and rejects duplicate delivery',
    () async {
      final coordinator = createCoordinator();
      final redirect = await coordinator.beginAttempt(
        'yapchat://login-callback/',
      );
      final callback = Uri.parse('$redirect&code=authorization-code');

      expect(coordinator.tryAcceptCallback(callback), isTrue);
      expect(coordinator.isCallbackProcessing, isTrue);
      expect(coordinator.tryAcceptCallback(callback), isFalse);

      await coordinator.completeAttempt();
      expect(coordinator.isCallbackProcessing, isFalse);
    },
  );

  test('does not consume a callback without an auth result', () async {
    final coordinator = createCoordinator();
    final redirect = await coordinator.beginAttempt(
      'yapchat://login-callback/',
    );

    expect(coordinator.tryAcceptCallback(Uri.parse(redirect)), isFalse);
    expect(
      coordinator.tryAcceptCallback(Uri.parse('$redirect&code=valid')),
      isTrue,
    );
  });

  test('a new attempt supersedes the still-open browser attempt', () async {
    final coordinator = createCoordinator();
    final oldRedirect = await coordinator.beginAttempt(
      'yapchat://login-callback/',
    );
    final currentRedirect = await coordinator.beginAttempt(
      'yapchat://login-callback/',
    );

    expect(
      coordinator.tryAcceptCallback(Uri.parse('$oldRedirect&code=old')),
      isFalse,
    );
    expect(
      coordinator.tryAcceptCallback(Uri.parse('$currentRedirect&code=new')),
      isTrue,
    );
  });

  test('restores an active attempt after an app process restart', () async {
    final firstProcess = createCoordinator();
    final redirect = await firstProcess.beginAttempt(
      'yapchat://login-callback/',
    );

    final restoredProcess = createCoordinator();
    expect(
      restoredProcess.tryAcceptCallback(Uri.parse('$redirect&code=restored')),
      isTrue,
    );
  });

  test('accepts a matching provider error callback', () async {
    final coordinator = createCoordinator();
    final redirect = await coordinator.beginAttempt(
      'yapchat://login-callback/',
    );
    final errorCallback = Uri.parse('$redirect&error=access_denied');

    expect(coordinator.tryAcceptCallback(errorCallback), isTrue);
    expect(coordinator.isCallbackProcessing, isTrue);
  });

  test('matches only the configured callback location', () {
    const redirect = 'yapchat://login-callback/';

    expect(
      isConfiguredAuthCallback(
        Uri.parse('yapchat://login-callback?code=value'),
        redirect,
      ),
      isTrue,
    );
    expect(
      isConfiguredAuthCallback(
        Uri.parse('yapchat://another-host/?code=value'),
        redirect,
      ),
      isFalse,
    );
  });
}
