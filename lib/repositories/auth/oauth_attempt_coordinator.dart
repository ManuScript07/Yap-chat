import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

typedef OAuthAttemptIdFactory = String Function();

/// Keeps a single mobile PKCE attempt active and rejects callbacks from older
/// browser tabs before they reach Supabase's one-slot PKCE verifier storage.
class OAuthAttemptCoordinator {
  OAuthAttemptCoordinator({
    required SharedPreferences preferences,
    required String namespace,
    OAuthAttemptIdFactory? idFactory,
  }) : _preferences = preferences,
       _storageKey = 'auth.oauth.active_attempt.$namespace',
       _idFactory = idFactory ?? const Uuid().v4,
       _activeAttemptId = preferences.getString(
         'auth.oauth.active_attempt.$namespace',
       );

  static const attemptQueryParameter = 'auth_attempt';

  final SharedPreferences _preferences;
  final String _storageKey;
  final OAuthAttemptIdFactory _idFactory;

  String? _activeAttemptId;
  bool _isCallbackProcessing = false;
  Future<void> _storageOperations = Future<void>.value();

  bool get isCallbackProcessing => _isCallbackProcessing;

  Future<String> beginAttempt(String redirectUrl) async {
    await _storageOperations;

    final attemptId = _idFactory();
    _activeAttemptId = attemptId;
    _isCallbackProcessing = false;
    final persistOperation = _preferences.setString(_storageKey, attemptId);
    _storageOperations = persistOperation.then<void>((_) {}).catchError((_) {});
    try {
      await persistOperation;
    } catch (_) {
      if (_activeAttemptId == attemptId) _activeAttemptId = null;
      rethrow;
    }

    final uri = Uri.parse(redirectUrl);
    return uri
        .replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            attemptQueryParameter: attemptId,
          },
        )
        .toString();
  }

  /// Called synchronously by Supabase's deep-link predicate.
  ///
  /// A callback is accepted at most once in the current process. The persisted
  /// attempt is deliberately retained until exchange succeeds or fails, so a
  /// process killed during the exchange can still recover on the next launch.
  bool tryAcceptCallback(Uri uri) {
    final attemptId = uri.queryParameters[attemptQueryParameter];
    if (!_hasAuthResponseParameter(uri) ||
        attemptId == null ||
        attemptId != _activeAttemptId ||
        _isCallbackProcessing) {
      return false;
    }

    _isCallbackProcessing = true;
    return true;
  }

  Future<void> completeAttempt() => _clearActiveAttempt();

  Future<void> cancelAttempt() => _clearActiveAttempt();

  Future<void> _clearActiveAttempt() {
    final attemptId = _activeAttemptId;
    _activeAttemptId = null;
    _isCallbackProcessing = false;
    if (attemptId == null) return Future<void>.value();

    final operation = _storageOperations.then((_) async {
      if (_preferences.getString(_storageKey) == attemptId) {
        await _preferences.remove(_storageKey);
      }
    });
    _storageOperations = operation.catchError((_) {});
    return operation;
  }
}

bool _hasAuthResponseParameter(Uri uri) {
  final fragmentParameters = Uri.splitQueryString(uri.fragment);
  bool has(String key) =>
      uri.queryParameters.containsKey(key) ||
      fragmentParameters.containsKey(key);

  return has('code') ||
      has('access_token') ||
      has('error') ||
      has('error_code') ||
      has('error_description');
}

bool isConfiguredAuthCallback(Uri uri, String redirectUrl) {
  final configured = Uri.parse(redirectUrl);
  return uri.scheme == configured.scheme &&
      uri.host == configured.host &&
      _normalizedPath(uri.path) == _normalizedPath(configured.path);
}

String _normalizedPath(String path) {
  if (path == '/' || path.isEmpty) return '';
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
