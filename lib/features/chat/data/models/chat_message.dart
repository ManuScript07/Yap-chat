import 'package:equatable/equatable.dart';

enum MessageStatus { sending, sent, read, error }

class ChatMessage extends Equatable {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isMine;
  final MessageStatus status;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.isMine,
    this.status = MessageStatus.sent,
  });

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? text,
    DateTime? timestamp,
    bool? isMine,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isMine: isMine ?? this.isMine,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [id, chatId, senderId, text, timestamp, isMine, status];
}
