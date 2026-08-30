import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chats/data/data.dart';

enum ChatsStatus { initial, loading, success, failure }

enum ChatsBulkAction { delete, markRead, toggleMute }

enum ChatsBulkActionFeedback { success, failure }

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
    this.feedbackId = 0,
  });

  final ChatsStatus status;
  final List<Chat> chats;
  final List<Chat> filteredChats;
  final Set<String> selectedChatIds;
  final String searchQuery;
  final bool isBulkActionInProgress;
  final ChatsBulkActionFeedback? feedback;
  final ChatsBulkAction? feedbackAction;
  final int feedbackId;

  bool get isSelectionMode => selectedChatIds.isNotEmpty;

  ChatsState copyWith({
    ChatsStatus? status,
    List<Chat>? chats,
    List<Chat>? filteredChats,
    Set<String>? selectedChatIds,
    String? searchQuery,
    bool? isBulkActionInProgress,
    ChatsBulkActionFeedback? feedback,
    ChatsBulkAction? feedbackAction,
    bool clearFeedback = false,
    int? feedbackId,
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
      feedbackId: feedbackId ?? this.feedbackId,
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
    feedbackId,
  ];
}
