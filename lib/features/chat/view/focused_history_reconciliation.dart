import 'package:flutter/foundation.dart';
import 'package:yap_chat/features/chat/data/models/chat_message.dart';

/// Rechecks the part of an open history window covered by a server response.
/// A shifted 60-message page is not, by itself, a change to the open window.
/// Returns null when no already-loaded message changed.
List<ChatMessage>? reconcileFocusedHistory(
  List<ChatMessage> loaded,
  List<ChatMessage> refreshed,
) {
  if (loaded.isEmpty || refreshed.isEmpty) return null;

  final newest = refreshed.first;
  final oldest = refreshed.last;
  final refreshedById = {for (final message in refreshed) message.id: message};
  final reconciled = <ChatMessage>[];
  var changed = false;

  for (final message in loaded) {
    final covered =
        _compareCursor(message, newest) <= 0 &&
        _compareCursor(message, oldest) >= 0;
    if (!covered) {
      reconciled.add(message);
      continue;
    }

    final current = refreshedById[message.id];
    if (current == null) {
      // The server no longer exposes this message to the current user.
      changed = true;
      continue;
    }
    if (current != message) changed = true;
    reconciled.add(current);
  }

  return changed ? reconciled : null;
}

int _compareCursor(ChatMessage first, ChatMessage second) {
  final timestamp = first.timestamp.compareTo(second.timestamp);
  return timestamp != 0 ? timestamp : first.id.compareTo(second.id);
}

bool sameFocusedMediaSource(ChatMessage first, ChatMessage second) =>
    first.type == second.type &&
    listEquals(first.mediaStoragePaths, second.mediaStoragePaths) &&
    first.audioStoragePath == second.audioStoragePath;

/// Keep a hydrated local file while using fresh read/reply metadata from RPC.
ChatMessage withFocusedCachedMedia(ChatMessage current, ChatMessage hydrated) {
  if (!sameFocusedMediaSource(current, hydrated)) return current;
  return switch (current.type) {
    MessageType.image => current.copyWith(mediaUrls: hydrated.mediaUrls),
    MessageType.audio => current.copyWith(audioUrl: hydrated.audioUrl),
    _ => current,
  };
}
