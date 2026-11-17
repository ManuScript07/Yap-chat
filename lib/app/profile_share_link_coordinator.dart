import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/core/services/profile_share_link.dart';
import 'package:yap_chat/core/services/feed_post_link.dart';

/// Holds public profile and publication links until the auth shell is ready.
class ProfileShareLinkCoordinator {
  ProfileShareLinkCoordinator({
    required this._preferences,
    required this._initialUri,
    required this._uriStream,
    required this._isAuthenticated,
    required this._resolveUserId,
    required this._openProfile,
    this._openPost,
    required this._onError,
  });

  static const _pendingUsernameKey = 'pending_profile_share_link_username';
  static const _pendingPostKey = 'pending_feed_share_link_post';

  final SharedPreferences _preferences;
  final Future<Uri?> Function() _initialUri;
  final Stream<Uri> _uriStream;
  final bool Function() _isAuthenticated;
  final Future<String?> Function(String username) _resolveUserId;
  final Future<bool> Function(String userId) _openProfile;
  final Future<bool> Function(String id)? _openPost;
  final void Function(Object error, StackTrace stackTrace, String message)
  _onError;

  StreamSubscription<Uri>? _subscription;
  String? _pendingUsername;
  String? _pendingPost;
  bool _isResolving = false;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _pendingUsername = _readPersistedUsername();
    final post = _preferences.getString(_pendingPostKey);
    if (_openPost != null && post != null && FeedPostLink.isValidId(post)) {
      _pendingPost = post;
    }
    var receivedLiveLink = false;
    _subscription = _uriStream.listen(
      (uri) => receivedLiveLink = _acceptUri(uri) || receivedLiveLink,
      onError: (Object error, StackTrace stackTrace) =>
          _onError(error, stackTrace, 'Profile share link stream failed'),
    );
    try {
      final initial = await _initialUri();
      if (initial != null && !receivedLiveLink) _acceptUri(initial);
    } catch (error, stackTrace) {
      _onError(error, stackTrace, 'Initial profile share link read failed');
    }
    _drainIfPossible();
  }

  void onAuthenticationOrForegroundChanged() => _drainIfPossible();

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
  }

  bool _acceptUri(Uri uri) {
    if (_disposed) return false;
    final id = FeedPostLink.tryParse(uri);
    if (_openPost != null && id != null) {
      _pendingPost = id;
      unawaited(_preferences.setString(_pendingPostKey, id));
      _drainIfPossible();
      return true;
    }
    final username = ProfileShareLink.tryParse(uri);
    if (username == null) return false;
    _pendingUsername = username;
    unawaited(_preferences.setString(_pendingUsernameKey, username));
    _drainIfPossible();
    return true;
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
    if (_disposed ||
        _isResolving ||
        !_isAuthenticated() ||
        _pendingUsername == null && _pendingPost == null) {
      return;
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    final username = _pendingUsername;
    final post = _pendingPost;
    _isResolving = true;
    try {
      if (post != null && _openPost != null) {
        if (await _openPost(post) && !_disposed && _pendingPost == post) {
          _pendingPost = null;
          await _preferences.remove(_pendingPostKey);
        }
        return;
      }
      if (username == null) return;
      final userId = await _resolveUserId(username);
      if (_disposed || !_isAuthenticated() || _pendingUsername != username) {
        return;
      }
      if (userId == null || await _openProfile(userId)) {
        if (_disposed || _pendingUsername != username) return;
        _pendingUsername = null;
        await _preferences.remove(_pendingUsernameKey);
      }
    } catch (error, stackTrace) {
      // Keep the link for the next resume. This is important when the app was
      // opened from a browser before the network became available.
      _onError(error, stackTrace, 'Share link resolution failed');
    } finally {
      _isResolving = false;
      final newPost = _pendingPost != null && _pendingPost != post;
      final newProfile =
          _pendingPost == null &&
          _pendingUsername != null &&
          (_pendingUsername != username || post != null);
      if (newPost || newProfile) _drainIfPossible();
    }
  }
}
