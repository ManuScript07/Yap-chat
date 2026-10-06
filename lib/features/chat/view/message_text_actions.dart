import 'package:yap_chat/core/services/profile_share_link.dart';
import 'package:yap_chat/features/chat/data/message_text_entity.dart';
import 'package:yap_chat/repositories/friends/abstract_friends_repository.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';

enum MessageTextActionResult { opened, unavailable, failed, ignored }

/// Uses the existing privacy-aware discovery and profile routes. No background
/// lookups, new clients, timers or subscriptions. The page owns this handler.
class MessageTextActions {
  MessageTextActions({
    required this._friends,
    required this._profiles,
    required this._openLink,
    required this._openProfile,
    required this._isActive,
    required this._currentUserId,
    required this._onError,
    DateTime Function()? clock,
    this._timeout = const Duration(seconds: 12),
  }) : _clock = clock ?? DateTime.now;

  final IFriendsRepository _friends;
  final IProfileRepository _profiles;
  final Future<bool> Function(Uri) _openLink;
  final Future<void> Function(String) _openProfile;
  final bool Function() _isActive;
  final String _currentUserId;
  final void Function(Object, StackTrace) _onError;
  final DateTime Function() _clock;
  final Duration _timeout;
  bool _busy = false;
  DateTime? _lastStartedAt;

  Future<MessageTextActionResult> activate(MessageTextEntity entity) async {
    final now = _clock();
    if (_busy ||
        !_isActive() ||
        (_lastStartedAt != null &&
            now.difference(_lastStartedAt!) <
                const Duration(milliseconds: 350))) {
      return MessageTextActionResult.ignored;
    }
    _busy = true;
    _lastStartedAt = now;
    try {
      String? userId;
      switch (entity.type) {
        case MessageTextEntityType.link:
          final uri = Uri.tryParse(entity.target);
          if (uri == null ||
              !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            return MessageTextActionResult.unavailable;
          }
          final username = ProfileShareLink.tryParse(uri);
          if (username == null) {
            final opened = await _openLink(uri).timeout(_timeout);
            return opened
                ? MessageTextActionResult.opened
                : MessageTextActionResult.failed;
          }
          userId = await _profiles
              .resolveSharedProfileUsername(username)
              .timeout(_timeout);
        case MessageTextEntityType.username:
          final candidates = await _friends
              .searchUsers('@${entity.target}')
              .timeout(_timeout);
          // Never navigate to a fuzzy/prefix match supplied by another source.
          for (final candidate in candidates) {
            if (candidate.username.toLowerCase() == entity.target) {
              userId = candidate.id;
              break;
            }
          }
        case MessageTextEntityType.phone:
          final snapshot = await _friends
              .refreshPhoneMatch(entity.target)
              .timeout(_timeout);
          userId = snapshot.matches[entity.target]?.id;
      }
      if (!_isActive()) return MessageTextActionResult.ignored;
      if (userId == null || userId.isEmpty || userId == _currentUserId) {
        return MessageTextActionResult.unavailable;
      }
      await _openProfile(userId);
      return MessageTextActionResult.opened;
    } catch (error, stack) {
      _onError(error, stack);
      return _isActive()
          ? MessageTextActionResult.failed
          : MessageTextActionResult.ignored;
    } finally {
      _busy = false;
    }
  }
}
