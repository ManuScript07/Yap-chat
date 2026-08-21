import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/notifications/bloc/notifications_state.dart';
import 'package:yap_chat/repositories/notifications/notifications.dart';

class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit({required IPushNotificationsRepository repository})
    : _repository = repository,
      super(const NotificationsState()) {
    _openedSubscription = _repository.openedConversationIds.listen((
      conversationId,
    ) {
      emit(state.copyWith(pendingConversationId: conversationId));
    });
  }

  final IPushNotificationsRepository _repository;
  late final StreamSubscription<String> _openedSubscription;

  Future<void> setAuthenticatedUser(String? userId) {
    if (userId == null) {
      emit(const NotificationsState());
    }
    return _repository.setAuthenticatedUser(userId);
  }

  Future<void> setActiveConversation(String? conversationId) async {
    emit(
      state.copyWith(
        activeConversationId: conversationId,
        clearActiveConversation: conversationId == null,
      ),
    );
    await _repository.setActiveConversation(conversationId);
  }

  Future<void> clearActiveConversation(String conversationId) {
    if (state.activeConversationId != conversationId) {
      return Future<void>.value();
    }
    return setActiveConversation(null);
  }

  Future<void> setAppForeground(bool isForeground) {
    return _repository.setAppForeground(isForeground);
  }

  void navigationHandled(String conversationId) {
    if (state.pendingConversationId != conversationId) return;
    emit(state.copyWith(clearPendingConversation: true));
  }

  @override
  Future<void> close() async {
    await _openedSubscription.cancel();
    return super.close();
  }
}
