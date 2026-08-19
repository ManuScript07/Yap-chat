import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chats/bloc/bloc.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:stream_transform/stream_transform.dart';

EventTransformer<Event> debounce<Event>(Duration duration) {
  return (events, mapper) {
    return restartable<Event>().call(events.debounce(duration), mapper);
  };
}

/// Координирует загрузку, поиск и bulk-действия над чатами.
class ChatsBloc extends Bloc<ChatsEvent, ChatsState> {
  ChatsBloc({required this._chatsRepository}) : super(const ChatsState()) {
    on<ChatsLoadStarted>(_onLoadStarted);
    on<ChatsSearchChanged>(
      _onSearchChanged,
      transformer: debounce(const Duration(milliseconds: 200)),
    );
    on<ChatSelectionToggled>(_onSelectionToggled);
    on<ChatSelectionCleared>(_onSelectionCleared);
    on<ChatsDeleted>(_onDeleted);
    on<ChatsMarkedAsRead>(_onMarkedAsRead);
    on<ChatsMuteToggled>(_onMuteToggled);
    on<ChatsSubscriptionUpdated>(_onSubscriptionUpdated);
    on<ChatsSubscriptionFailed>(_onSubscriptionFailed);
  }

  final IChatsRepository _chatsRepository;
  StreamSubscription<List<Chat>>? _chatsSubscription;

  Future<void> _onLoadStarted(
    ChatsLoadStarted event,
    Emitter<ChatsState> emit,
  ) async {
    emit(state.copyWith(status: ChatsStatus.loading));

    await _chatsSubscription?.cancel();
    _chatsSubscription = _chatsRepository.watchChats().listen(
      (chats) => add(ChatsSubscriptionUpdated(chats)),
      onError: (_, _) => add(const ChatsSubscriptionFailed()),
    );
  }

  void _onSubscriptionUpdated(
    ChatsSubscriptionUpdated event,
    Emitter<ChatsState> emit,
  ) {
    emit(
      state.copyWith(
        status: ChatsStatus.success,
        chats: event.chats,
        filteredChats: _filterChats(event.chats, state.searchQuery),
      ),
    );
  }

  void _onSubscriptionFailed(
    ChatsSubscriptionFailed event,
    Emitter<ChatsState> emit,
  ) {
    emit(state.copyWith(status: ChatsStatus.failure));
  }

  Future<void> _onSearchChanged(
    ChatsSearchChanged event,
    Emitter<ChatsState> emit,
  ) async {
    emit(
      state.copyWith(
        searchQuery: event.query,
        filteredChats: _filterChats(state.chats, event.query),
      ),
    );
  }

  void _onSelectionToggled(
    ChatSelectionToggled event,
    Emitter<ChatsState> emit,
  ) {
    final selectedChatIds = Set<String>.of(state.selectedChatIds);

    if (!selectedChatIds.add(event.id)) {
      selectedChatIds.remove(event.id);
    }

    emit(state.copyWith(selectedChatIds: selectedChatIds));
  }

  void _onSelectionCleared(
    ChatSelectionCleared event,
    Emitter<ChatsState> emit,
  ) {
    emit(state.copyWith(selectedChatIds: const {}));
  }

  Future<void> _onDeleted(ChatsDeleted event, Emitter<ChatsState> emit) async {
    final selectedIds = Set<String>.of(state.selectedChatIds);
    if (selectedIds.isEmpty) return;

    try {
      await _chatsRepository.deleteChats(selectedIds);
      final chats = state.chats
          .where((chat) => !selectedIds.contains(chat.id))
          .toList(growable: false);

      emit(
        state.copyWith(
          chats: chats,
          filteredChats: _filterChats(chats, state.searchQuery),
          selectedChatIds: const {},
        ),
      );
    } catch (_) {
      emit(state.copyWith(selectedChatIds: const {}));
    }
  }

  Future<void> _onMarkedAsRead(
    ChatsMarkedAsRead event,
    Emitter<ChatsState> emit,
  ) async {
    final selectedIds = Set<String>.of(state.selectedChatIds);
    if (selectedIds.isEmpty) return;

    try {
      await _chatsRepository.markAsRead(selectedIds);
      final chats = _updateSelectedChats(
        selectedIds,
        (chat) => chat.copyWith(unreadCount: 0),
      );

      emit(
        state.copyWith(
          chats: chats,
          filteredChats: _filterChats(chats, state.searchQuery),
          selectedChatIds: const {},
        ),
      );
    } catch (_) {
      emit(state.copyWith(selectedChatIds: const {}));
    }
  }

  Future<void> _onMuteToggled(
    ChatsMuteToggled event,
    Emitter<ChatsState> emit,
  ) async {
    final selectedIds = Set<String>.of(state.selectedChatIds);
    if (selectedIds.isEmpty) return;

    try {
      await _chatsRepository.toggleMute(selectedIds);
      final chats = _updateSelectedChats(
        selectedIds,
        (chat) => chat.copyWith(isMuted: !chat.isMuted),
      );

      emit(
        state.copyWith(
          chats: chats,
          filteredChats: _filterChats(chats, state.searchQuery),
          selectedChatIds: const {},
        ),
      );
    } catch (_) {
      emit(state.copyWith(selectedChatIds: const {}));
    }
  }

  List<Chat> _updateSelectedChats(
    Set<String> selectedIds,
    Chat Function(Chat chat) update,
  ) {
    return state.chats
        .map((chat) => selectedIds.contains(chat.id) ? update(chat) : chat)
        .toList(growable: false);
  }

  static List<Chat> _filterChats(List<Chat> chats, String query) {
    final normalizedQuery = query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return List.unmodifiable(chats);
    }

    return chats
        .where((chat) => chat.userName.toLowerCase().contains(normalizedQuery))
        .toList(growable: false);
  }

  @override
  Future<void> close() async {
    await _chatsSubscription?.cancel();
    return super.close();
  }
}
