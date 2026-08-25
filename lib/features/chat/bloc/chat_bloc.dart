import 'dart:async';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chat/bloc/chat_event.dart';
import 'package:yap_chat/features/chat/bloc/chat_state.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final IChatRepository _chatRepository;
  final IChatsRepository _chatsRepository;
  String? _draftPeerId;
  Future<Chat>? _directChatFuture;
  StreamSubscription? _messagesSubscription;

  ChatBloc({
    required IChatRepository chatRepository,
    required IChatsRepository chatsRepository,
    required Chat initialChat,
  }) : _chatRepository = chatRepository,
       _chatsRepository = chatsRepository,
       _draftPeerId = initialChat.isDraft ? initialChat.peerId : null,
       super(
         ChatState(
           status: initialChat.isDraft
               ? ChatStatus.success
               : ChatStatus.initial,
           chatId: initialChat.id,
           hasMoreMessages: !initialChat.isDraft,
         ),
       ) {
    on<ChatStarted>(_onStarted);
    on<ChatMessageSent>(_onMessageSent);
    on<ChatMessageImagesSent>(_onImagesSent);
    on<ChatMessageAudioSent>(_onAudioSent);
    on<ChatMessageRetryRequested>(_onRetryRequested);
    on<ChatLocationSent>(_onLocationSent);
    on<ChatMessagesReceived>(_onMessagesReceived);
    on<ChatReplySelected>(_onReplySelected);
    on<ChatReplyCleared>(_onReplyCleared);
    on<ChatMessageDeleteRequested>(_onMessageDeleteRequested);
    on<ChatOlderMessagesRequested>(
      _onOlderMessagesRequested,
      transformer: droppable(),
    );
  }

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    if (_draftPeerId != null) {
      emit(
        state.copyWith(
          status: ChatStatus.success,
          chatId: event.chatId,
          hasMoreMessages: false,
        ),
      );
      return;
    }

    emit(state.copyWith(status: ChatStatus.loading, chatId: event.chatId));
    await _subscribeToMessages(event.chatId);
  }

  Future<void> _subscribeToMessages(String chatId) async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = _chatRepository
        .getMessagesStream(chatId)
        .listen((messages) => add(ChatMessagesReceived(messages)));
  }

  Future<String> _ensureChat(Emitter<ChatState> emit) async {
    final peerId = _draftPeerId;
    if (peerId == null) return state.chatId;

    final pending = _directChatFuture ??= _chatsRepository.ensureDirectChat(
      peerId,
    );
    try {
      final chat = await pending;
      if (_draftPeerId != null) {
        _draftPeerId = null;
        emit(
          state.copyWith(
            status: ChatStatus.loading,
            chatId: chat.id,
            hasMoreMessages: true,
            resolvedChat: chat,
          ),
        );
        await _subscribeToMessages(chat.id);
      }
      return chat.id;
    } finally {
      if (identical(_directChatFuture, pending)) {
        _directChatFuture = null;
      }
    }
  }

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    if (event.text.trim().isEmpty) return;

    final replyToMessageId = state.replyToMessage?.id;
    emit(state.copyWith(clearReplyToMessage: true));
    try {
      final chatId = await _ensureChat(emit);
      await _chatRepository.sendMessage(
        chatId,
        event.text,
        replyToMessageId: replyToMessageId,
      );
    } catch (_) {
      emit(state.copyWith(status: ChatStatus.failure));
    }
  }

  Future<void> _onImagesSent(
    ChatMessageImagesSent event,
    Emitter<ChatState> emit,
  ) async {
    if (event.imagePaths.isEmpty) return;

    final replyToMessageId = state.replyToMessage?.id;
    emit(state.copyWith(clearReplyToMessage: true));
    try {
      final chatId = await _ensureChat(emit);
      await _chatRepository.sendImages(
        chatId,
        event.imagePaths,
        replyToMessageId: replyToMessageId,
      );
    } catch (_) {
      emit(state.copyWith(status: ChatStatus.failure));
    }
  }

  Future<void> _onRetryRequested(
    ChatMessageRetryRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (event.message.type != MessageType.image ||
        event.message.mediaUrls.isEmpty) {
      return;
    }

    try {
      await _chatRepository.retryImages(state.chatId, event.message);
    } catch (_) {
      emit(state.copyWith(status: ChatStatus.failure));
    }
  }

  Future<void> _onAudioSent(
    ChatMessageAudioSent event,
    Emitter<ChatState> emit,
  ) async {
    final replyToMessageId = state.replyToMessage?.id;
    emit(state.copyWith(clearReplyToMessage: true));
    try {
      final chatId = await _ensureChat(emit);
      await _chatRepository.sendAudio(
        chatId,
        event.audioPath,
        event.duration,
        event.waveform,
        replyToMessageId: replyToMessageId,
      );
    } catch (_) {
      emit(state.copyWith(status: ChatStatus.failure));
    }
  }

  Future<void> _onLocationSent(
    ChatLocationSent event,
    Emitter<ChatState> emit,
  ) async {
    final replyToMessageId = state.replyToMessage?.id;
    emit(state.copyWith(clearReplyToMessage: true));
    try {
      final chatId = await _ensureChat(emit);
      await _chatRepository.sendLocation(
        chatId,
        event.latitude,
        event.longitude,
        replyToMessageId: replyToMessageId,
      );
    } catch (_) {
      emit(state.copyWith(status: ChatStatus.failure));
    }
  }

  void _onMessagesReceived(
    ChatMessagesReceived event,
    Emitter<ChatState> emit,
  ) {
    final isFirstLoad = state.status != ChatStatus.success;

    final initialIds = isFirstLoad
        ? event.messages.map((m) => m.id).toSet()
        : state.initialMessageIds;

    emit(
      state.copyWith(
        status: ChatStatus.success,
        messages: event.messages,
        initialMessageIds: initialIds,
      ),
    );
  }

  void _onReplySelected(ChatReplySelected event, Emitter<ChatState> emit) {
    emit(state.copyWith(replyToMessage: event.message));
  }

  void _onReplyCleared(ChatReplyCleared event, Emitter<ChatState> emit) {
    emit(state.copyWith(clearReplyToMessage: true));
  }

  Future<void> _onOlderMessagesRequested(
    ChatOlderMessagesRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isLoadingMore || !state.hasMoreMessages) return;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final hasMore = await _chatRepository.loadMoreMessages(state.chatId);
      emit(state.copyWith(isLoadingMore: false, hasMoreMessages: hasMore));
    } catch (_) {
      emit(state.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onMessageDeleteRequested(
    ChatMessageDeleteRequested event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _chatRepository.deleteMessage(
        state.chatId,
        event.message.id,
        deleteForEveryone: event.message.isMine,
      );
      if (state.replyToMessage?.id == event.message.id) {
        emit(state.copyWith(clearReplyToMessage: true));
      }
    } catch (_) {
      emit(state.copyWith(status: ChatStatus.failure));
    }
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
