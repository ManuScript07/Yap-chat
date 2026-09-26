import 'package:yap_chat/features/chat/data/data.dart';

/// A temporary distant-history viewport, not the contiguous Drift timeline.
/// Keep enough rows on both sides for smooth scrolling while retaining the
/// boundary messages as valid server cursors for pages trimmed out of memory.
const focusedHistoryMessageLimit = 240;

enum FocusedHistoryGrowth { older, newer }

({List<ChatMessage> messages, bool trimmed}) boundFocusedHistory(
  List<ChatMessage> messages,
  FocusedHistoryGrowth growth, {
  int limit = focusedHistoryMessageLimit,
}) {
  assert(limit > 0);
  if (messages.length <= limit) {
    return (messages: messages, trimmed: false);
  }
  return (
    messages: List<ChatMessage>.unmodifiable(
      growth == FocusedHistoryGrowth.older
          ? messages.skip(messages.length - limit)
          : messages.take(limit),
    ),
    trimmed: true,
  );
}
