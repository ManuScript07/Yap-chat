import 'package:equatable/equatable.dart';

enum ChatPreviewType { text, image, audio, location }

class Chat extends Equatable {
  static const _draftIdPrefix = 'direct-draft:';

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
  final DateTime? lastSeenAt;
  final bool showsLastSeen;
  final bool isLastMessageFromMe;
  final bool isMuted;
  final bool blockedByMe;
  final bool blockedByPeer;
  final bool peerIsGloballyBanned;

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
    this.lastSeenAt,
    this.showsLastSeen = true,
    required this.isLastMessageFromMe,
    this.isMuted = false,
    this.blockedByMe = false,
    this.blockedByPeer = false,
    this.peerIsGloballyBanned = false,
  });

  factory Chat.directDraft({
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    String? peerAvatarUrl,
    String? peerAvatarStoragePath,
  }) => Chat(
    id: '$_draftIdPrefix$peerId',
    peerId: peerId,
    peerUsername: peerUsername,
    userName: peerDisplayName,
    avatarUrl: peerAvatarUrl,
    avatarStoragePath: peerAvatarStoragePath,
    lastMessage: '',
    lastMessageTime: DateTime.fromMillisecondsSinceEpoch(0),
    unreadCount: 0,
    isOnline: false,
    isLastMessageFromMe: false,
  );

  bool get isDraft => id.startsWith(_draftIdPrefix);

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
    DateTime? lastSeenAt,
    bool? showsLastSeen,
    bool? isLastMessageFromMe,
    bool? isMuted,
    bool? blockedByMe,
    bool? blockedByPeer,
    bool? peerIsGloballyBanned,
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
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      showsLastSeen: showsLastSeen ?? this.showsLastSeen,
      isLastMessageFromMe: isLastMessageFromMe ?? this.isLastMessageFromMe,
      isMuted: isMuted ?? this.isMuted,
      blockedByMe: blockedByMe ?? this.blockedByMe,
      blockedByPeer: blockedByPeer ?? this.blockedByPeer,
      peerIsGloballyBanned:
          peerIsGloballyBanned ?? this.peerIsGloballyBanned,
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
    lastSeenAt,
    showsLastSeen,
    isLastMessageFromMe,
    isMuted,
    blockedByMe,
    blockedByPeer,
    peerIsGloballyBanned,
    isDraft,
  ];
}
