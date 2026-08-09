class Chat {
  final String id;
  final String userName;
  final String? avatarUrl;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final bool isLastMessageFromMe;
  final bool isMuted;

  Chat({
    required this.id,
    required this.userName,
    this.avatarUrl,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.isOnline,
    required this.isLastMessageFromMe,
    this.isMuted = false,
  });
}
