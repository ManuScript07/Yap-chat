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

  int get unreadCount =>
      unreadTotal ??
      chats
          .where((chat) => !chat.isMuted)
          .fold(0, (total, chat) => total + chat.unreadCount);

  bool get isSelectionMode => selectedChatIds.isNotEmpty;
  bool get hasMutedSelection =>
      chats.any((chat) => selectedChatIds.contains(chat.id) && chat.isMuted);

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
  ];
}
