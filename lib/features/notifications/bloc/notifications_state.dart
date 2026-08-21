import 'package:equatable/equatable.dart';

class NotificationsState extends Equatable {
  const NotificationsState({
    this.activeConversationId,
    this.pendingConversationId,
  });

  final String? activeConversationId;
  final String? pendingConversationId;

  NotificationsState copyWith({
    String? activeConversationId,
    String? pendingConversationId,
    bool clearActiveConversation = false,
    bool clearPendingConversation = false,
  }) {
    return NotificationsState(
      activeConversationId: clearActiveConversation
          ? null
          : activeConversationId ?? this.activeConversationId,
      pendingConversationId: clearPendingConversation
          ? null
          : pendingConversationId ?? this.pendingConversationId,
    );
  }

  @override
  List<Object?> get props => [activeConversationId, pendingConversationId];
}
