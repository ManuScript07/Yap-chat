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
    return findSnapshot(messageId)?.messages;
  }

  FocusedHistoryWindowSnapshot? findSnapshot(String messageId) {
    _removeExpired();
    for (final entry in _windows.entries.toList(growable: false).reversed) {
      if (entry.value.snapshot.messages.any(
        (message) => message.id == messageId,
      )) {
        // Recently used windows survive eviction before older ones.
        _windows.remove(entry.key);
        _windows[entry.key] = entry.value;
        return entry.value.snapshot;
      }
    }
    return null;
  }

  void remember(
    String anchorId,
    List<ChatMessage> messages, {
    bool usesLocalHistory = false,
  }) {
    if (messages.isEmpty) return;
    _removeExpired();
    _windows.remove(anchorId);
    _windows[anchorId] = _CachedWindow(
      FocusedHistoryWindowSnapshot(
        messages: List<ChatMessage>.unmodifiable(messages),
        usesLocalHistory: usesLocalHistory,
      ),
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
      _windows[key] = _CachedWindow(
        FocusedHistoryWindowSnapshot(
          messages: [
            for (final message in entry.snapshot.messages)
              message.id == messageId &&
                      message.reactionState.version <= state.version
                  ? message.copyWith(reactionState: state)
                  : message,
          ],
          usesLocalHistory: entry.snapshot.usesLocalHistory,
        ),
        entry.loadedAt,
      );
    }
  }

  void _removeExpired() {
    final now = _now();
    _windows.removeWhere((_, entry) => now.difference(entry.loadedAt) >= _ttl);
  }
}

class _CachedWindow {
  const _CachedWindow(this.snapshot, this.loadedAt);

  final FocusedHistoryWindowSnapshot snapshot;
  final DateTime loadedAt;
}

/// Retain the cursor source as well as rows: a SQLite hit must continue via
/// cache-first history pagination, not become a remote-only reply window.
class FocusedHistoryWindowSnapshot {
  const FocusedHistoryWindowSnapshot({
    required this.messages,
    required this.usesLocalHistory,
  });

  final List<ChatMessage> messages;
  final bool usesLocalHistory;
}
