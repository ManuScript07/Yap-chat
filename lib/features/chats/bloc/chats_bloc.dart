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
    on<ChatsListViewUpdated>(_onListViewUpdated);
    on<ChatsLoadMoreRequested>((event, emit) async {
      if (_loadingPage) return;
      if (_chatsRepository case final IChatsListRepository repository) {
        _loadingPage = true;
        try {
          await repository.loadMoreChatList(retry: event.retry);
        } catch (_) {
          // The list stream retains cached rows and publishes the retry state.
        } finally {
          _loadingPage = false;
        }
      }
    });
    on<ChatsVisibleIdsChanged>((event, emit) {
      _visibleIds = event.ids;
      _updateObserved();
    });
    on<ChatsUnreadCountUpdated>((event, emit) {
      if (event.generation != _subscriptionGeneration) return;
      emit(
        state.copyWith(
          unreadTotal: event.total,
          clearUnreadTotal: event.total == null,
        ),
      );
    });
  }

  final IChatsRepository _chatsRepository;
  StreamSubscription<List<Chat>>? _chatsSubscription;
  StreamSubscription<int?>? _unreadSubscription;
  int _subscriptionGeneration = 0;
  StreamSubscription<ChatListViewState>? _listSubscription;
  Set<String> _visibleIds = {};
  bool _loadingPage = false;

  void _updateObserved() {
    if (_chatsRepository case final IChatsListRepository repository) {
      repository.setChatListObservedIds(_visibleIds, state.selectedChatIds);
    }
  }

  void _onListViewUpdated(
    ChatsListViewUpdated event,
    Emitter<ChatsState> emit,
  ) {
    if (event.generation != _subscriptionGeneration ||
        event.view.query != state.searchQuery.trim().toLowerCase()) {
      return;
    }
    final view = event.view;
    final selected = Set<String>.of(state.selectedChatIds)
      ..removeAll(view.missingSelectedIds);
    final selectionChanged = selected.length != state.selectedChatIds.length;
    final snapshot = Map<String, Chat>.of(state.selectedChats)
      ..removeWhere((id, _) => !selected.contains(id));
    for (final chat in [...view.chats, ...view.selectedChats]) {
      if (selected.contains(chat.id)) snapshot[chat.id] = chat;
    }
    emit(
      state.copyWith(
        status: view.ready
            ? (view.chats.isEmpty &&
                      (view.error != null || view.refreshError != null)
                  ? ChatsStatus.failure
                  : ChatsStatus.success)
            : ChatsStatus.loading,
        isPaginated: true,
        chats: view.chats,
        filteredChats: view.chats,
        selectedChatIds: selected,
        selectedChats: Map.unmodifiable(snapshot),
        hasMoreCached: view.hasMoreCached,
        hasMoreRemote: view.hasMoreRemote,
        isLoadingMore: view.isLoadingCache || view.isLoadingRemote,
        isRefreshing: view.isRefreshing,
        paginationError: view.error,
        clearPaginationError: view.error == null,
        refreshError: view.refreshError,
        clearRefreshError: view.refreshError == null,
      ),
    );
    if (selectionChanged) _updateObserved();
  }

  Future<void> _onLoadStarted(
    ChatsLoadStarted event,
    Emitter<ChatsState> emit,
  ) async {
    emit(state.copyWith(status: ChatsStatus.loading));
    final generation = ++_subscriptionGeneration;
    await _unreadSubscription?.cancel();
    await _listSubscription?.cancel();
    await _chatsSubscription?.cancel();
    if (isClosed || generation != _subscriptionGeneration) return;
    if (_chatsRepository case final IChatsListRepository repository) {
      _listSubscription = repository.watchChatList().listen(
        (view) {
          if (!isClosed && generation == _subscriptionGeneration) {
            add(ChatsListViewUpdated(view, generation));
          }
        },
        onError: (Object _, StackTrace _) {
          if (!isClosed) add(const ChatsSubscriptionFailed());
        },
      );
      emit(state.copyWith(isPaginated: true));
    }
    if (_chatsRepository case final IChatsUnreadRepository repository) {
      _unreadSubscription = repository.watchUnreadCount().listen(
        (total) {
          if (!isClosed && generation == _subscriptionGeneration) {
            add(ChatsUnreadCountUpdated(total, generation));
          }
        },
        // An unavailable count must not replace the visible list with failure.
        onError: (Object _, StackTrace _) {},
      );
    }
    if (_listSubscription == null) {
      _chatsSubscription = _chatsRepository.watchChats().listen(
        (chats) => add(ChatsSubscriptionUpdated(chats)),
        onError: (_, _) => add(const ChatsSubscriptionFailed()),
      );
    }
  }

  void _onSubscriptionUpdated(
    ChatsSubscriptionUpdated event,
    Emitter<ChatsState> emit,
  ) {
    emit(
      state.copyWith(
        status: ChatsStatus.success,
        chats: event.chats,
        selectedChats: Map.unmodifiable({
          for (final chat in event.chats)
            if (state.selectedChatIds.contains(chat.id)) chat.id: chat,
        }),
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
    if (_chatsRepository case final IChatsListRepository repository) {
      final query = String.fromCharCodes(
        event.query.trim().toLowerCase().runes.take(100),
      );
      emit(state.copyWith(searchQuery: query));
      await repository.setChatListQuery(query);
      return;
    }
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
    if (state.isBulkActionInProgress) return;
    final selectedChatIds = Set<String>.of(state.selectedChatIds);

    if (!selectedChatIds.contains(event.id) &&
        selectedChatIds.length >= ChatBulkSelection.maximum) {
      emit(
        state.copyWith(
          feedback: ChatsBulkActionFeedback.selectionLimit,
          feedbackId: state.feedbackId + 1,
        ),
      );
      return;
    }

    if (!selectedChatIds.add(event.id)) {
      selectedChatIds.remove(event.id);
    }

    final snapshot = Map<String, Chat>.of(state.selectedChats);
    if (selectedChatIds.contains(event.id)) {
      final chat = state.chats.where((c) => c.id == event.id).firstOrNull;
      if (chat != null) snapshot[event.id] = chat;
    } else {
      snapshot.remove(event.id);
    }
    emit(
      state.copyWith(
        selectedChatIds: selectedChatIds,
        selectedChats: Map.unmodifiable(snapshot),
      ),
    );
    _updateObserved();
  }

  void _onSelectionCleared(
    ChatSelectionCleared event,
    Emitter<ChatsState> emit,
  ) {
    if (state.isBulkActionInProgress) return;
    emit(state.copyWith(selectedChatIds: const {}, selectedChats: const {}));
    _updateObserved();
  }

  Future<void> _onDeleted(ChatsDeleted event, Emitter<ChatsState> emit) async {
    final selectedIds = Set<String>.of(state.selectedChatIds);
    await _performBulkAction(
      selectedIds,
      ChatsBulkAction.delete,
      () => _chatsRepository.deleteChats(selectedIds),
      (chats) => chats
          .where((chat) => !selectedIds.contains(chat.id))
          .toList(growable: false),
      emit,
    );
  }

  Future<void> _onMarkedAsRead(
    ChatsMarkedAsRead event,
    Emitter<ChatsState> emit,
  ) async {
    final selectedIds = Set<String>.of(state.selectedChatIds);
    await _performBulkAction(
      selectedIds,
      ChatsBulkAction.markRead,
      () => _chatsRepository.markAsRead(selectedIds),
      // The repository updates the authoritative cache conditionally. Never
      // overwrite a newer Realtime snapshot with an unconditional zero here.
      (chats) => chats,
      emit,
    );
  }

  Future<void> _onMuteToggled(
    ChatsMuteToggled event,
    Emitter<ChatsState> emit,
  ) async {
    if (state.isBulkActionInProgress) return;
    final selectedIds = Set<String>.of(state.selectedChatIds);
    final isMuted = !state.hasMutedSelection;
    final changedIds = state.selectionRows
        .where(
          (chat) => selectedIds.contains(chat.id) && chat.isMuted != isMuted,
        )
        .map((chat) => chat.id)
        .toSet();
    await _performBulkAction(
      selectedIds,
      ChatsBulkAction.toggleMute,
      () => _chatsRepository.setMuted(changedIds, isMuted: isMuted),
      (chats) => _updateSelectedChats(
        changedIds,
        (chat) => chat.copyWith(isMuted: isMuted),
      ),
      emit,
      muteValue: isMuted,
    );
  }

  Future<void> _performBulkAction(
    Set<String> selectedIds,
    ChatsBulkAction action,
    Future<void> Function() operation,
    List<Chat> Function(List<Chat>) updateChats,
    Emitter<ChatsState> emit, {
    bool? muteValue,
  }) async {
    if (selectedIds.isEmpty || state.isBulkActionInProgress) return;
    emit(state.copyWith(isBulkActionInProgress: true, clearFeedback: true));
    try {
      await operation();
      final chats = updateChats(state.chats);
      emit(
        state.copyWith(
          chats: chats,
          filteredChats: state.isPaginated
              ? chats
              : _filterChats(chats, state.searchQuery),
          selectedChatIds: const {},
          selectedChats: const {},
          isBulkActionInProgress: false,
          feedback: ChatsBulkActionFeedback.success,
          feedbackAction: action,
          feedbackIsMuted: muteValue,
          feedbackId: state.feedbackId + 1,
        ),
      );
      _updateObserved();
    } catch (_) {
      emit(
        state.copyWith(
          isBulkActionInProgress: false,
          feedback: ChatsBulkActionFeedback.failure,
          feedbackAction: action,
          feedbackIsMuted: muteValue,
          feedbackId: state.feedbackId + 1,
        ),
      );
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
    _subscriptionGeneration++;
    await _listSubscription?.cancel();
    await _unreadSubscription?.cancel();
    await _chatsSubscription?.cancel();
    return super.close();
  }
}
