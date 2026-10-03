import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';

enum ChatStatus { initial, loading, success, failure }

class ChatState extends Equatable {
  final ChatStatus status;
  final List<ChatMessage> messages;
  final bool isSending;
  final int audioSendFailureCount;
  final String chatId;
  final Set<String> initialMessageIds;
  final ChatMessage? replyToMessage;
  final bool isLoadingMore;
  final bool hasMoreMessages;
  final Chat? resolvedChat;

  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.isSending = false,
    this.audioSendFailureCount = 0,
    this.chatId = '',
    this.initialMessageIds = const {},
    this.replyToMessage,
    this.isLoadingMore = false,
    this.hasMoreMessages = true,
    this.resolvedChat,
  });

  ChatState copyWith({
    ChatStatus? status,
    List<ChatMessage>? messages,
    bool? isSending,
    int? audioSendFailureCount,
    String? chatId,
    Set<String>? initialMessageIds,
    ChatMessage? replyToMessage,
    bool clearReplyToMessage = false,
    bool? isLoadingMore,
    bool? hasMoreMessages,
    Chat? resolvedChat,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      audioSendFailureCount:
          audioSendFailureCount ?? this.audioSendFailureCount,
      chatId: chatId ?? this.chatId,
      initialMessageIds: initialMessageIds ?? this.initialMessageIds,
      replyToMessage: clearReplyToMessage
          ? null
          : replyToMessage ?? this.replyToMessage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      resolvedChat: resolvedChat ?? this.resolvedChat,
    );
  }

  @override
  List<Object?> get props => [
    status,
    messages,
    isSending,
    audioSendFailureCount,
    chatId,
    initialMessageIds,
    replyToMessage,
    isLoadingMore,
    hasMoreMessages,
    resolvedChat,
  ];
}
