import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/auth/abstract_auth_repository.dart';
import 'package:yap_chat/repositories/auth/oauth_attempt_coordinator.dart';

typedef OAuthSignInLauncher =
Future<bool> Function(
    OAuthProvider provider, {
    String? redirectTo,
    String? scopes,
    LaunchMode authScreenLaunchMode,
    Map<String, String>? queryParams,
    });

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required SupabaseClient client,
    required String redirectUrl,
    bool useAnonymousSignIn = false,
    OAuthSignInLauncher? oauthSignInLauncher,
    OAuthAttemptCoordinator? oauthAttemptCoordinator,
    AccountSessionController? accountSessionController,
  })
      : _client = client,
        _redirectUrl = redirectUrl,
        _useAnonymousSignIn = useAnonymousSignIn,
        _oauthAttemptCoordinator = oauthAttemptCoordinator,
        _accountSessionController = accountSessionController,
        _oauthSignInLauncher =
            oauthSignInLauncher ?? client.auth.signInWithOAuth;

  final SupabaseClient _client;
  final String _redirectUrl;
  final bool _useAnonymousSignIn;
  final OAuthSignInLauncher _oauthSignInLauncher;
  final OAuthAttemptCoordinator? _oauthAttemptCoordinator;
  final AccountSessionController? _accountSessionController;

  static const _yandexProvider = OAuthProvider('custom:yandex');
  static const _yandexQueryParams = <String, String>{'force_confirm': 'yes'};

  @override
  AuthSession? get currentSession => _mapSession(_client.auth.currentSession);

  @override
  bool get isSignInCallbackProcessing =>
      _oauthAttemptCoordinator?.isCallbackProcessing ?? false;

  @override
  Stream<AuthSession?> observeSession() {
    final initialSession = currentSession;
    var initialEventSkipped = false;

    return _client.auth.onAuthStateChange
        .transform(
      StreamTransformer<AuthState, AuthState>.fromHandlers(
        handleData: (authState, sink) {
          _accountSessionController?.setAuthenticatedUser(
            authState.session?.user.id,
          );
          if (authState.session != null) {
            unawaited(_oauthAttemptCoordinator?.completeAttempt());
          }
          sink.add(authState);
        },
        handleError: (error, stackTrace, sink) {
          unawaited(_oauthAttemptCoordinator?.completeAttempt());
          sink.addError(error, stackTrace);
        },
      ),
    )
        .map((authState) => _mapSession(authState.session))
        .where((session) {
      if (!initialEventSkipped && session == initialSession) {
        initialEventSkipped = true;
        return false;
      }
      return true;
    })
        .distinct();
  }

  @override
  Future<AuthAccountAccess> getAccountAccess() async {
    final response = await _client.rpc<List<dynamic>>('get_my_account_access');
    if (response.isEmpty) {
      throw StateError('The account access response is empty.');
    }
    final row = Map<String, dynamic>.from(response.first as Map);
    final username = (row['username'] as String?)?.trim();
    return AuthAccountAccess(
      isBanned: row['is_banned'] as bool? ?? false,
      username: username == null || username.isEmpty ? null : username,
    );
  }

  @override
  Future<void> signInWithYandex() async {
    if (_useAnonymousSignIn) {
      await _client.auth.signInAnonymously();
      return;
    }
    try {
      final redirectTo = kIsWeb
          ? null
          : _oauthAttemptCoordinator == null
          ? _redirectUrl
          : await _oauthAttemptCoordinator.beginAttempt(_redirectUrl);
      final launched = await _oauthSignInLauncher(
        _yandexProvider,
        redirectTo: redirectTo,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.inAppBrowserView,
        queryParams: _yandexQueryParams,
      );
      if (!launched) {
        throw StateError('Could not launch the Yandex OAuth browser.');
      }
    } catch (_) {
      await _oauthAttemptCoordinator?.cancelAttempt();
      rethrow;
    }
  }

  @override
  Future<void> cancelPendingSignIn() async {
    await _oauthAttemptCoordinator?.cancelAttempt();
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  AuthSession? _mapSession(Session? session) {
    final user = session?.user;
    if (user == null) return null;

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return AuthSession(
      userId: user.id,
      email:
      user.email ??
          _firstString(metadata, const ['email', 'default_email']),
      displayName: _firstString(metadata, const [
        'name',
        'full_name',
        'display_name',
        'real_name',
      ]),
      birthDate: _firstDate(metadata, const ['birth_date', 'birthday']),
      avatarUrl: _firstString(metadata, const [
        'avatar_url',
        'picture',
        'avatar',
      ]),
    );
  }

  String? _firstString(Map<String, dynamic> metadata, List<String> keys) {
    for (final key in keys) {
      final value = metadata[key];
      if (value is String && value
          .trim()
          .isNotEmpty) return value.trim();
    }
    return null;
  }

  DateTime? _firstDate(Map<String, dynamic> metadata, List<String> keys) {
    final value = _firstString(metadata, keys);
    return value == null ? null : DateTime.tryParse(value);
  }
}
