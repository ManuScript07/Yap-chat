/// The server refused to create or explicitly reopen a conversation.
/// Existing visible conversations and incoming messages remain available.
class ChatLimitReachedException implements Exception {
  const ChatLimitReachedException();

  static const maximum = 100;

  @override
  String toString() => 'ChatLimitReachedException';
}
