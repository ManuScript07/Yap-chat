import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chat/data/data.dart';

enum ChatStatus { initial, loading, success, failure }

class ChatState extends Equatable {
  final ChatStatus status;
  final List<ChatMessage> messages;
  final bool isSending;
  final String chatId;
  final Set<String> initialMessageIds;

  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.isSending = false,
    this.chatId = '',
    this.initialMessageIds = const {},
  });

  ChatState copyWith({
    ChatStatus? status,
    List<ChatMessage>? messages,
    bool? isSending,
    String? chatId,
    Set<String>? initialMessageIds,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      chatId: chatId ?? this.chatId,
      initialMessageIds: initialMessageIds ?? this.initialMessageIds,
    );
  }

  @override
  List<Object?> get props => [status, messages, isSending, chatId, initialMessageIds];
}
