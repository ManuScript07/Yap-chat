import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final IChatRepository _chatRepository;
  final IChatsRepository _chatsRepository;
  String? _draftPeerId;
  Future<String>? _directChatFuture;
  Future<void> _sendQueue = Future<void>.value();
  final _submissions = <(ChatOutgoingEvent, int), ChatSendRequested>{};
  final _replyClaims = <int, Object>{};
  int _replyRevision = 0;
  bool _closing = false;
  StreamSubscription? _messagesSubscription;
  StreamSubscription<Chat?>? _draftChatSubscription;

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
    on<ChatDraftResolved>(_onDraftResolved, transformer: droppable());
    on<ChatOutgoingEvent>((event, emit) async {
      try {
        await _queueSend(event, emit);
      } on PartialImageSendException {
        // Legacy callers have no retained selection to reconcile. The failure
        // state is already published; submitted UI callers receive progress.
      }
    });
    on<ChatSendRequested>((event, emit) async {
      try {
        final accepted = await _queueSend(event.message, emit);
        if (!event.completion.isCompleted) event.completion.complete(accepted);
      } on PartialImageSendException catch (error, stack) {
        if (!event.completion.isCompleted) {
          event.completion.completeError(error, stack);
        }
      }
    });
    on<ChatMessageRetryRequested>(_onRetryRequested);
    on<ChatMessagesReceived>(_onMessagesReceived);
    on<ChatReplySelected>(_onReplySelected);
    on<ChatReplyCleared>(_onReplyCleared);
    on<ChatMessageDeleteRequested>(_onMessageDeleteRequested);
    on<ChatOlderMessagesRequested>(
      _onOlderMessagesRequested,
      transformer: droppable(),
    );
  }

  /// Completes after durable local enqueue, not after network delivery. Content
  /// owners keep their draft on rejection; duplicate taps share one operation.
  Future<bool> submit(ChatOutgoingEvent event) {
    if (_closing || isClosed) return Future.value(false);
    final message = switch (event) {
      ChatMessageImagesSent() => ChatMessageImagesSent(
        List.unmodifiable(event.imagePaths),
      ),
      ChatMessageAudioSent() => ChatMessageAudioSent(
        audioPath: event.audioPath,
        duration: event.duration,
        waveform: List.unmodifiable(event.waveform),
      ),
      _ => event,
    };
    final key = (message, _replyRevision);
    final existing = _submissions[key];
    if (existing != null) return existing.completion.future;
    final request = ChatSendRequested(message);
    _submissions[key] = request;
    add(request);
    return request.completion.future.whenComplete(() {
      if (identical(_submissions[key], request)) _submissions.remove(key);
    });
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
      _watchForDraftResolution(_draftPeerId!);
      return;
    }

    emit(state.copyWith(status: ChatStatus.loading, chatId: event.chatId));
    await _subscribeToMessages(event.chatId);
  }

  void _watchForDraftResolution(String peerId) {
    unawaited(_draftChatSubscription?.cancel());
    _draftChatSubscription = _chatsRepository.watchChatByPeerId(peerId).listen((
      chat,
    ) {
      if (_closing ||
          isClosed ||
          _draftPeerId != peerId ||
          chat == null ||
          chat.peerId != peerId) {
        return;
      }
      add(ChatDraftResolved(peerId: peerId, chat: chat));
    });
  }

  Future<void> _onDraftResolved(
    ChatDraftResolved event,
    Emitter<ChatState> emit,
  ) async {
    if (_closing || _draftPeerId != event.peerId || _directChatFuture != null) {
      return;
    }
    _draftPeerId = null;
    emit(
      state.copyWith(
        status: ChatStatus.loading,
        chatId: event.chat.id,
        hasMoreMessages: true,
        resolvedChat: event.chat,
      ),
    );
    await _draftChatSubscription?.cancel();
    _draftChatSubscription = null;
    if (_closing || emit.isDone) return;
    await _subscribeToMessages(event.chat.id);
  }

  Future<void> _subscribeToMessages(String chatId) async {
    await _messagesSubscription?.cancel();
    if (_closing || isClosed) return;
    _messagesSubscription = _chatRepository.getMessagesStream(chatId).listen((
      messages,
    ) {
      if (!_closing && !isClosed) add(ChatMessagesReceived(messages));
    });
  }

  Future<String> _ensureChat(Emitter<ChatState> emit) {
    final existing = _directChatFuture;
    if (existing != null) return existing;
    final peerId = _draftPeerId;
    if (peerId == null) return Future.value(state.chatId);

    late final Future<String> pending;
    pending = _resolveDraft(peerId, emit).whenComplete(() {
      if (identical(_directChatFuture, pending)) _directChatFuture = null;
    });
    _directChatFuture = pending;
    return pending;
  }

  Future<String> _resolveDraft(String peerId, Emitter<ChatState> emit) async {
    await _draftChatSubscription?.cancel();
    _draftChatSubscription = null;
    try {
      final chat = await _chatsRepository.ensureDirectChat(peerId);
      if (_closing || emit.isDone) return chat.id;
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
      return chat.id;
    } catch (_) {
      if (!_closing && !emit.isDone) {
        _draftPeerId = peerId;
        _watchForDraftResolution(peerId);
      }
      rethrow;
    }
  }

  Future<bool> _queueSend(ChatOutgoingEvent event, Emitter<ChatState> emit) {
    final revision = _replyRevision;
    final selected = state.replyToMessage;
    final claim = selected != null && !_replyClaims.containsKey(revision)
        ? Object()
        : null;
    if (claim != null) _replyClaims[revision] = claim;
    // Capture reply intent before waiting for another send. A reply selection
    // belongs to its first submission; later user selections have a new revision.
    final operation = _sendQueue
        .then(
          (_) => _performSend(
            event,
            emit,
            claim == null ? null : selected,
            revision,
          ),
        )
        .whenComplete(() {
          if (claim != null && identical(_replyClaims[revision], claim)) {
            _replyClaims.remove(revision);
          }
        });
    _sendQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<bool> _performSend(
    ChatOutgoingEvent event,
    Emitter<ChatState> emit,
    ChatMessage? reply,
    int replyRevision,
  ) async {
    if (_closing ||
        emit.isDone ||
        event is ChatMessageSent && event.text.trim().isEmpty ||
        event is ChatMessageImagesSent && event.imagePaths.isEmpty) {
      return false;
    }
    try {
      final chatId = await _ensureChat(emit);
      if (_closing || emit.isDone) return false;
      switch (event) {
        case ChatMessageSent():
          await _chatRepository.sendMessage(
            chatId,
            event.text,
            replyToMessageId: reply?.id,
          );
        case ChatMessageImagesSent():
          await _chatRepository.sendImages(
            chatId,
            event.imagePaths,
            replyToMessageId: reply?.id,
          );
        case ChatMessageAudioSent():
          await _chatRepository.sendAudio(
            chatId,
            event.audioPath,
            event.duration,
            event.waveform,
            replyToMessageId: reply?.id,
          );
        case ChatLocationSent():
          await _chatRepository.sendLocation(
            chatId,
            event.latitude,
            event.longitude,
            replyToMessageId: reply?.id,
          );
      }
      _consumeReply(reply, replyRevision, emit);
      return true;
    } on PartialImageSendException {
      // The first accepted batch already owns this reply. Retrying only the
      // remaining paths must not attach it a second time.
      _consumeReply(reply, replyRevision, emit);
      if (!_closing && !emit.isDone) {
        emit(state.copyWith(status: ChatStatus.failure));
      }
      rethrow;
    } on ChatLimitReachedException {
      if (!_closing && !emit.isDone) {
        emit(
          state.copyWith(
            chatLimitRefusalCount: state.chatLimitRefusalCount + 1,
            audioSendFailureCount:
                state.audioSendFailureCount +
                (event is ChatMessageAudioSent ? 1 : 0),
          ),
        );
      }
      return false;
    } catch (_) {
      if (!_closing && !emit.isDone) {
        emit(
          state.copyWith(
            status: ChatStatus.failure,
            audioSendFailureCount:
                state.audioSendFailureCount +
                (event is ChatMessageAudioSent ? 1 : 0),
          ),
        );
      }
      return false;
    }
  }

  void _consumeReply(
    ChatMessage? reply,
    int revision,
    Emitter<ChatState> emit,
  ) {
    if (!_closing &&
        !emit.isDone &&
        reply != null &&
        _replyRevision == revision &&
        state.replyToMessage?.id == reply.id) {
      _replyRevision++;
      emit(state.copyWith(clearReplyToMessage: true));
    }
  }

  Future<void> _onRetryRequested(
    ChatMessageRetryRequested event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _chatRepository.retryMessage(state.chatId, event.message);
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
    _replyRevision++;
    emit(state.copyWith(replyToMessage: event.message));
  }

  void _onReplyCleared(ChatReplyCleared event, Emitter<ChatState> emit) {
    _replyRevision++;
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
    _closing = true;
    for (final request in _submissions.values) {
      if (!request.completion.isCompleted) request.completion.complete(false);
    }
    _submissions.clear();
    _draftChatSubscription?.cancel();
    _messagesSubscription?.cancel();
    return super.close();
  }
}
