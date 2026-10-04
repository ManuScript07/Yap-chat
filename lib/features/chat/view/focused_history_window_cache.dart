import 'dart:collection';

import 'package:yap_chat/features/chat/data/data.dart';

/// Short-lived metadata only. Media files remain owned by the shared file cache.
/// This cache belongs to one open chat page and never survives a page disposal.
class FocusedHistoryWindowCache {
  FocusedHistoryWindowCache({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _ttl = Duration(minutes: 2);
  static const _maxWindows = 2;

  final DateTime Function() _now;
  final LinkedHashMap<String, _CachedWindow> _windows = LinkedHashMap();

  List<ChatMessage>? find(String messageId) {
    _removeExpired();
    for (final entry in _windows.entries.toList(growable: false).reversed) {
      if (entry.value.messages.any((message) => message.id == messageId)) {
        // Recently used windows survive eviction before older ones.
        _windows.remove(entry.key);
        _windows[entry.key] = entry.value;
        return entry.value.messages;
      }
    }
    return null;
  }

  void remember(String anchorId, List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    _removeExpired();
    _windows.remove(anchorId);
    _windows[anchorId] = _CachedWindow(
      List<ChatMessage>.unmodifiable(messages),
      _now(),
    );
    while (_windows.length > _maxWindows) {
      _windows.remove(_windows.keys.first);
    }
  }

  void clear() => _windows.clear();

  void updateReaction(String messageId, MessageReactionState state) {
    for (final key in _windows.keys.toList()) {
      final entry = _windows[key]!;
      _windows[key] = _CachedWindow([
        for (final message in entry.messages)
          message.id == messageId &&
                  message.reactionState.version <= state.version
              ? message.copyWith(reactionState: state)
              : message,
      ], entry.loadedAt);
    }
  }

  void _removeExpired() {
    final now = _now();
    _windows.removeWhere((_, entry) => now.difference(entry.loadedAt) >= _ttl);
  }
}

class _CachedWindow {
  const _CachedWindow(this.messages, this.loadedAt);

  final List<ChatMessage> messages;
  final DateTime loadedAt;
}
