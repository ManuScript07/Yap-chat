import 'dart:async';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chat/bloc/chat_event.dart';
import 'package:yap_chat/features/chat/bloc/chat_state.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final IChatRepository _chatRepository;
  StreamSubscription? _messagesSubscription;

  ChatBloc({required this._chatRepository}) : super(const ChatState()) {
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
    emit(state.copyWith(status: ChatStatus.loading, chatId: event.chatId));

    await _messagesSubscription?.cancel();
    _messagesSubscription = _chatRepository
        .getMessagesStream(event.chatId)
        .listen((messages) => add(ChatMessagesReceived(messages)));
  }

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    if (event.text.trim().isEmpty) return;

    final replyToMessageId = state.replyToMessage?.id;
    emit(state.copyWith(clearReplyToMessage: true));
    try {
      await _chatRepository.sendMessage(
        state.chatId,
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
      await _chatRepository.sendImages(
        state.chatId,
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
      await _chatRepository.sendAudio(
        state.chatId,
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
      await _chatRepository.sendLocation(
        state.chatId,
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
