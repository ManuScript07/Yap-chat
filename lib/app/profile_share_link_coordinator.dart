import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/core/services/profile_share_link.dart';

/// Holds a verified profile link until an authenticated app shell is ready.
///
/// Resolving a username is deliberately deferred: an app link may arrive while
/// the user is still completing OAuth, and the resolver is an authenticated
/// server endpoint. The pending value is a public username, never a token or
/// profile payload.
class ProfileShareLinkCoordinator {
  ProfileShareLinkCoordinator({
    required SharedPreferences preferences,
    required Future<Uri?> Function() initialUri,
    required Stream<Uri> uriStream,
    required bool Function() isAuthenticated,
    required Future<String?> Function(String username) resolveUserId,
    required Future<bool> Function(String userId) openProfile,
    required void Function(Object error, StackTrace stackTrace, String message)
    onError,
  }) : _preferences = preferences,
       _initialUri = initialUri,
       _uriStream = uriStream,
       _isAuthenticated = isAuthenticated,
       _resolveUserId = resolveUserId,
       _openProfile = openProfile,
       _onError = onError;

  static const _pendingUsernameKey = 'pending_profile_share_link_username';

  final SharedPreferences _preferences;
  final Future<Uri?> Function() _initialUri;
  final Stream<Uri> _uriStream;
  final bool Function() _isAuthenticated;
  final Future<String?> Function(String username) _resolveUserId;
  final Future<bool> Function(String userId) _openProfile;
  final void Function(Object error, StackTrace stackTrace, String message)
  _onError;

  StreamSubscription<Uri>? _subscription;
  String? _pendingUsername;
  bool _isResolving = false;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _pendingUsername = _readPersistedUsername();
    _subscription = _uriStream.listen(
      _acceptUri,
      onError: (Object error, StackTrace stackTrace) =>
          _onError(error, stackTrace, 'Profile share link stream failed'),
    );
    try {
      final initial = await _initialUri();
      if (initial != null) _acceptUri(initial);
    } catch (error, stackTrace) {
      _onError(error, stackTrace, 'Initial profile share link read failed');
    }
    _drainIfPossible();
  }

  void onAuthenticationOrForegroundChanged() => _drainIfPossible();

  Future<void> dispose() async => _subscription?.cancel();

  void _acceptUri(Uri uri) {
    final username = ProfileShareLink.tryParse(uri);
    if (username == null) return;
    _pendingUsername = username;
    unawaited(_preferences.setString(_pendingUsernameKey, username));
    _drainIfPossible();
  }

  String? _readPersistedUsername() {
    final username = _preferences.getString(_pendingUsernameKey);
    return username == null
        ? null
        : ProfileShareLink.tryCreate(username) == null
        ? null
        : username;
  }

  void _drainIfPossible() {
    if (_isResolving || !_isAuthenticated() || _pendingUsername == null) return;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    final username = _pendingUsername;
    if (username == null || !_isAuthenticated() || _isResolving) return;
    _isResolving = true;
    try {
      final userId = await _resolveUserId(username);
      if (!_isAuthenticated() || _pendingUsername != username) return;
      if (userId == null || await _openProfile(userId)) {
        _pendingUsername = null;
        await _preferences.remove(_pendingUsernameKey);
      }
    } catch (error, stackTrace) {
      // Keep the link for the next resume. This is important when the app was
      // opened from a browser before the network became available.
      _onError(error, stackTrace, 'Profile share link resolution failed');
    } finally {
      _isResolving = false;
    }
  }
}
