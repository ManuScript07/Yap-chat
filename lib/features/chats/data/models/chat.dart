import 'package:equatable/equatable.dart';

class Chat extends Equatable {
  final String id;
  final String userName;
  final String? avatarUrl;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final bool isLastMessageFromMe;
  final bool isMuted;

  const Chat({
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

  Chat copyWith({
    String? id,
    String? userName,
    String? avatarUrl,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
    bool? isLastMessageFromMe,
    bool? isMuted,
  }) {
    return Chat(
      id: id ?? this.id,
      userName: userName ?? this.userName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      isLastMessageFromMe: isLastMessageFromMe ?? this.isLastMessageFromMe,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userName,
    avatarUrl,
    lastMessage,
    lastMessageTime,
    unreadCount,
    isOnline,
    isLastMessageFromMe,
    isMuted,
  ];
}
