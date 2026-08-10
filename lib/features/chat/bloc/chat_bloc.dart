import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chat/bloc/chat_event.dart';
import 'package:yap_chat/features/chat/bloc/chat_state.dart';
import 'package:yap_chat/features/chat/repositories/repositories.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final IChatRepository _chatRepository;
  StreamSubscription? _messagesSubscription;

  ChatBloc({
    required this._chatRepository,
  }) : super(const ChatState()) {
    on<ChatStarted>(_onStarted);
    on<ChatMessageSent>(_onMessageSent);
    on<ChatMessagesReceived>(_onMessagesReceived);
  }

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    emit(state.copyWith(status: ChatStatus.loading, chatId: event.chatId));
    
    await _messagesSubscription?.cancel();
    _messagesSubscription = _chatRepository
        .getMessagesStream(event.chatId)
        .listen((messages) => add(ChatMessagesReceived(messages)));
  }

  Future<void> _onMessageSent(ChatMessageSent event, Emitter<ChatState> emit) async {
    if (event.text.trim().isEmpty) return;
    
    try {
      await _chatRepository.sendMessage(state.chatId, event.text);
    } catch (_) {
      emit(state.copyWith(status: ChatStatus.failure));
    }
  }

  void _onMessagesReceived(ChatMessagesReceived event, Emitter<ChatState> emit) {
    final isFirstLoad = state.status != ChatStatus.success;

    final initialIds = isFirstLoad
        ? event.messages.map((m) => m.id).toSet()
        : state.initialMessageIds;

    emit(state.copyWith(
      status: ChatStatus.success,
      messages: event.messages,
      initialMessageIds: initialIds,
    ));
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
