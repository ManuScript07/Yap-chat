import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chats/data/data.dart';

enum ChatsStatus { initial, loading, success, failure }

/// Единый read-only снимок состояния страницы чатов.
class ChatsState extends Equatable {
  const ChatsState({
    this.status = ChatsStatus.initial,
    this.chats = const [],
    this.filteredChats = const [],
    this.selectedChatIds = const {},
    this.searchQuery = '',
  });

  final ChatsStatus status;
  final List<Chat> chats;
  final List<Chat> filteredChats;
  final Set<String> selectedChatIds;
  final String searchQuery;

  bool get isSelectionMode => selectedChatIds.isNotEmpty;

  ChatsState copyWith({
    ChatsStatus? status,
    List<Chat>? chats,
    List<Chat>? filteredChats,
    Set<String>? selectedChatIds,
    String? searchQuery,
  }) {
    return ChatsState(
      status: status ?? this.status,
      chats: chats ?? this.chats,
      filteredChats: filteredChats ?? this.filteredChats,
      selectedChatIds: selectedChatIds ?? this.selectedChatIds,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [
    status,
    chats,
    filteredChats,
    selectedChatIds,
    searchQuery,
  ];
}
