import 'package:equatable/equatable.dart';

class NotificationsState extends Equatable {
  const NotificationsState({
    this.activeConversationId,
    this.pendingConversationId,
    this.pendingProfileId,
  });

  final String? activeConversationId;
  final String? pendingConversationId;
  final String? pendingProfileId;

  NotificationsState copyWith({
    String? activeConversationId,
    String? pendingConversationId,
    String? pendingProfileId,
    bool clearActiveConversation = false,
    bool clearPendingConversation = false,
    bool clearPendingProfile = false,
  }) {
    return NotificationsState(
      activeConversationId: clearActiveConversation
          ? null
          : activeConversationId ?? this.activeConversationId,
      pendingConversationId: clearPendingConversation
          ? null
          : pendingConversationId ?? this.pendingConversationId,
      pendingProfileId: clearPendingProfile
          ? null
          : pendingProfileId ?? this.pendingProfileId,
    );
  }

  @override
  List<Object?> get props => [
    activeConversationId,
    pendingConversationId,
    pendingProfileId,
  ];
}
