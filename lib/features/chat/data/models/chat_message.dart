import 'package:equatable/equatable.dart';

enum MessageStatus { sending, sent, read, error }

enum MessageType { text, image, location }

class ChatMessage extends Equatable {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isMine;
  final MessageStatus status;
  final MessageType type;
  final List<String> mediaUrls;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.isMine,
    this.status = MessageStatus.sent,
    this.type = MessageType.text,
    this.mediaUrls = const [],
  });

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? text,
    DateTime? timestamp,
    bool? isMine,
    MessageStatus? status,
    MessageType? type,
    List<String>? mediaUrls,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isMine: isMine ?? this.isMine,
      status: status ?? this.status,
      type: type ?? this.type,
      mediaUrls: mediaUrls ?? this.mediaUrls,
    );
  }

  @override
  List<Object?> get props => [
        id,
        chatId,
        senderId,
        text,
        timestamp,
        isMine,
        status,
        type,
        mediaUrls,
      ];
}
