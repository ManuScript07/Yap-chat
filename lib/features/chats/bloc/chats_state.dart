import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chats/data/data.dart';

enum ChatsStatus { initial, loading, success, failure }

enum ChatsBulkAction { delete, markRead, toggleMute }

enum ChatsBulkActionFeedback { success, failure, selectionLimit }

/// Единый read-only снимок состояния страницы чатов.
class ChatsState extends Equatable {
  const ChatsState({
    this.status = ChatsStatus.initial,
    this.chats = const [],
    this.filteredChats = const [],
    this.selectedChatIds = const {},
    this.searchQuery = '',
    this.isBulkActionInProgress = false,
    this.feedback,
    this.feedbackAction,
    this.feedbackIsMuted,
    this.feedbackId = 0,
    this.unreadTotal,
    this.isPaginated = false,
    this.hasMoreCached = false,
    this.hasMoreRemote = false,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.paginationError,
    this.selectedChats = const {},
  });

  final ChatsStatus status;
  final List<Chat> chats;
  final List<Chat> filteredChats;
  final Set<String> selectedChatIds;
  final String searchQuery;
  final bool isBulkActionInProgress;
  final ChatsBulkActionFeedback? feedback;
  final ChatsBulkAction? feedbackAction;
  final bool? feedbackIsMuted;
  final int feedbackId;
  final int? unreadTotal;
  final bool isPaginated,
      hasMoreCached,
      hasMoreRemote,
      isLoadingMore,
      isRefreshing;
  final Object? paginationError;
  final Map<String, Chat> selectedChats;
  bool get hasMoreChats => hasMoreCached || hasMoreRemote;
  Iterable<Chat> get selectionRows => selectedChatIds
      .map(
        (id) => selectedChats[id] ?? chats.where((c) => c.id == id).firstOrNull,
      )
      .whereType<Chat>();

  int get unreadCount =>
      unreadTotal ??
      (isPaginated
          ? 0
          : chats
                .where((chat) => !chat.isMuted)
                .fold(0, (total, chat) => total + chat.unreadCount));

  bool get isSelectionMode => selectedChatIds.isNotEmpty;
  bool get hasMutedSelection => selectionRows.any((chat) => chat.isMuted);

  ChatsState copyWith({
    ChatsStatus? status,
    List<Chat>? chats,
    List<Chat>? filteredChats,
    Set<String>? selectedChatIds,
    String? searchQuery,
    bool? isBulkActionInProgress,
    ChatsBulkActionFeedback? feedback,
    ChatsBulkAction? feedbackAction,
    bool? feedbackIsMuted,
    bool clearFeedback = false,
    int? feedbackId,
    int? unreadTotal,
    bool clearUnreadTotal = false,
    bool? isPaginated,
    bool? hasMoreCached,
    bool? hasMoreRemote,
    bool? isLoadingMore,
    bool? isRefreshing,
    Object? paginationError,
    bool clearPaginationError = false,
    Map<String, Chat>? selectedChats,
  }) {
    return ChatsState(
      status: status ?? this.status,
      chats: chats ?? this.chats,
      filteredChats: filteredChats ?? this.filteredChats,
      selectedChatIds: selectedChatIds ?? this.selectedChatIds,
      searchQuery: searchQuery ?? this.searchQuery,
      isBulkActionInProgress:
          isBulkActionInProgress ?? this.isBulkActionInProgress,
      feedback: clearFeedback ? null : feedback ?? this.feedback,
      feedbackAction: clearFeedback
          ? null
          : feedbackAction ?? this.feedbackAction,
      feedbackIsMuted: clearFeedback
          ? null
          : feedbackIsMuted ?? this.feedbackIsMuted,
      feedbackId: feedbackId ?? this.feedbackId,
      unreadTotal: clearUnreadTotal ? null : unreadTotal ?? this.unreadTotal,
      isPaginated: isPaginated ?? this.isPaginated,
      hasMoreCached: hasMoreCached ?? this.hasMoreCached,
      hasMoreRemote: hasMoreRemote ?? this.hasMoreRemote,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      paginationError: clearPaginationError
          ? null
          : paginationError ?? this.paginationError,
      selectedChats: selectedChats ?? this.selectedChats,
    );
  }

  @override
  List<Object?> get props => [
    status,
    chats,
    filteredChats,
    selectedChatIds,
    searchQuery,
    isBulkActionInProgress,
    feedback,
    feedbackAction,
    feedbackIsMuted,
    feedbackId,
    unreadTotal,
    isPaginated,
    hasMoreCached,
    hasMoreRemote,
    isLoadingMore,
    isRefreshing,
    paginationError,
    selectedChats,
  ];
}
