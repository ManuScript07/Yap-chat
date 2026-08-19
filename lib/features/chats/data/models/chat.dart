import 'package:equatable/equatable.dart';

enum ChatPreviewType { text, image, audio, location }

class Chat extends Equatable {
  final String id;
  final String peerId;
  final String peerUsername;
  final String userName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final String? lastMessageId;
  final String lastMessage;
  final ChatPreviewType lastMessageType;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final bool isLastMessageFromMe;
  final bool isMuted;

  const Chat({
    required this.id,
    this.peerId = '',
    this.peerUsername = '',
    required this.userName,
    this.avatarUrl,
    this.avatarStoragePath,
    this.lastMessageId,
    required this.lastMessage,
    this.lastMessageType = ChatPreviewType.text,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.isOnline,
    required this.isLastMessageFromMe,
    this.isMuted = false,
  });

  Chat copyWith({
    String? id,
    String? peerId,
    String? peerUsername,
    String? userName,
    String? avatarUrl,
    String? avatarStoragePath,
    String? lastMessageId,
    String? lastMessage,
    ChatPreviewType? lastMessageType,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
    bool? isLastMessageFromMe,
    bool? isMuted,
  }) {
    return Chat(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      peerUsername: peerUsername ?? this.peerUsername,
      userName: userName ?? this.userName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarStoragePath: avatarStoragePath ?? this.avatarStoragePath,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType,
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
    peerId,
    peerUsername,
    userName,
    avatarUrl,
    avatarStoragePath,
    lastMessageId,
    lastMessage,
    lastMessageType,
    lastMessageTime,
    unreadCount,
    isOnline,
    isLastMessageFromMe,
    isMuted,
  ];
}
