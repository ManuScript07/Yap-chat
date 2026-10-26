import 'chat.dart';

/// An account-wide badge total plus optional addressed summaries.
/// The total excludes muted/hidden conversations, including ones off-page.
class ChatUnreadState {
  ChatUnreadState({required List<Chat> chats, required this.unreadTotal})
    : chats = List.unmodifiable(chats);

  final List<Chat> chats;
  final int unreadTotal;
}
