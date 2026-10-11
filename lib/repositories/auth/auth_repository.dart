import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/auth/abstract_auth_repository.dart';
import 'package:yap_chat/repositories/auth/auth_account_access_cache_data_source.dart';
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
    AuthAccountAccessCacheDataSource? accountAccessCache,
    AppDiagnostics? diagnostics,
  }) : _client = client,
       _redirectUrl = redirectUrl,
       _useAnonymousSignIn = useAnonymousSignIn,
       _oauthAttemptCoordinator = oauthAttemptCoordinator,
       _accountSessionController = accountSessionController,
       _accountAccessCache = accountAccessCache,
       _diagnostics = diagnostics,
       _oauthSignInLauncher =
           oauthSignInLauncher ?? client.auth.signInWithOAuth;

  final SupabaseClient _client;
  final String _redirectUrl;
  final bool _useAnonymousSignIn;
  final OAuthSignInLauncher _oauthSignInLauncher;
  final OAuthAttemptCoordinator? _oauthAttemptCoordinator;
  final AccountSessionController? _accountSessionController;
  final AuthAccountAccessCacheDataSource? _accountAccessCache;
  final AppDiagnostics? _diagnostics;

  static const _yandexProvider = OAuthProvider('custom:yandex');
  static const _yandexQueryParams = <String, String>{'force_confirm': 'yes'};
  static final _birthDatePattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

  @override
  AuthSession? get currentSession => _mapSession(_client.auth.currentSession);

  @override
  bool get isSignInCallbackProcessing =>
      _oauthAttemptCoordinator?.isCallbackProcessing ?? false;

  @override
  Stream<AuthSession?> observeSession() {
    final initialSession = currentSession;
    var initialEventHandled = false;
    var observedUserId = initialSession?.userId;

    return _client.auth.onAuthStateChange
        .transform(
          StreamTransformer<AuthState, AuthState>.fromHandlers(
            handleData: (authState, sink) {
              final userId = authState.session?.user.id;
              // Same-account refreshes must not reopen a local account boundary
              // that AuthBloc has closed after a confirmed ban or deletion.
              if (userId != observedUserId) {
                observedUserId = userId;
                _accountSessionController?.setAuthenticatedUser(userId);
              }
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
        // Seed duplicate detection with the replayed session before dropping
        // it: AuthBloc already handles currentSession explicitly at startup.
        .distinct()
        .where((session) {
          if (!initialEventHandled) {
            initialEventHandled = true;
            return session != initialSession;
          }
          return true;
        });
  }

  @override
  Future<AuthAccountAccess> getAccountAccess() async {
    final response = await measureRpc(
      _diagnostics,
      'get_my_account_access',
      () => _client.rpc<List<dynamic>>('get_my_account_access'),
    );
    if (response.isEmpty) {
      throw StateError('The account access response is empty.');
    }
    final row = Map<String, dynamic>.from(response.first as Map);
    final username = (row['username'] as String?)?.trim();
    final supportEmail = (row['support_email'] as String?)?.trim();
    final scheduledFor = DateTime.tryParse(
      row['deletion_scheduled_for'] as String? ?? '',
    )?.toUtc();
    return AuthAccountAccess(
      isBanned: row['is_banned'] as bool? ?? false,
      isDeletionPending: row['is_deletion_pending'] as bool? ?? false,
      isDeletionExpired: row['is_deletion_expired'] as bool? ?? false,
      deletionScheduledFor: scheduledFor,
      username: username == null || username.isEmpty ? null : username,
      supportEmail: supportEmail == null || supportEmail.isEmpty
          ? null
          : supportEmail,
    );
  }

  @override
  Future<AuthAccountAccess?> getCachedAccountAccess(String userId) async =>
      _accountAccessCache?.read(userId);

  @override
  Future<void> cacheAccountAccess(
    String userId,
    AuthAccountAccess access,
  ) async {
    await _accountAccessCache?.write(userId, access);
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
  Future<DateTime?> requestAccountDeletion(AccountDeletionSurvey survey) async {
    final response = await _client.functions.invoke(
      'request-account-deletion',
      body: {
        'reasons': survey.apiReasons,
        'feedback': survey.feedback,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return DateTime.tryParse(data['scheduled_for'] as String? ?? '')?.toUtc();
  }

  @override
  Future<void> restoreAccountDeletion() async {
    await _client.functions.invoke('restore-account-deletion');
  }

  @override
  Future<void> signOut({bool preserveAccountAccess = false}) async {
    final userId = currentSession?.userId;
    try {
      await _client.auth.signOut();
    } finally {
      if (userId != null && !preserveAccountAccess) {
        await _accountAccessCache?.clear(userId);
      }
    }
  }

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
      birthDate: _firstBirthDate(metadata, const [
        'birth_date',
        'birthdate',
        'birthday',
      ]),
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
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  DateTime? _firstBirthDate(Map<String, dynamic> metadata, List<String> keys) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final key in keys) {
      final rawValue = metadata[key];
      if (rawValue is! String) continue;
      final value = rawValue.trim();
      if (!_birthDatePattern.hasMatch(value)) {
        continue;
      }
      final year = int.parse(value.substring(0, 4));
      final month = int.parse(value.substring(5, 7));
      final day = int.parse(value.substring(8, 10));
      final date = DateTime.tryParse(value);
      // Yandex may omit date components; DateTime also normalizes impossible
      // dates (e.g. February 31). Neither is a usable date of birth.
      if (year > 0 &&
          date != null &&
          date.year == year &&
          date.month == month &&
          date.day == day &&
          !date.isAfter(today)) {
        return date;
      }
    }
    return null;
  }
}
