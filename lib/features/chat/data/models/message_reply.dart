import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chat/data/models/chat_message.dart';

class MessageReply extends Equatable {
  const MessageReply({
    required this.messageId,
    required this.senderId,
    required this.isMine,
    required this.type,
    required this.text,
  });

  factory MessageReply.fromMessage(ChatMessage message) {
    return MessageReply(
      messageId: message.id,
      senderId: message.senderId,
      isMine: message.isMine,
      type: message.type,
      text: message.text,
    );
  }

  final String messageId;
  final String senderId;
  final bool isMine;
  final MessageType type;
  final String text;

  @override
  List<Object?> get props => [messageId, senderId, isMine, type, text];
}
