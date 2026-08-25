import 'dart:async';

import 'package:yap_chat/repositories/notifications/abstract_push_notifications_repository.dart';

class MockPushNotificationsRepository implements IPushNotificationsRepository {
  const MockPushNotificationsRepository();

  @override
  Stream<String> get openedConversationIds => const Stream.empty();

  @override
  Future<void> setAuthenticatedUser(String? userId) async {}

  @override
  Future<void> setActiveConversation(String? conversationId) async {}

  @override
  Future<void> setAppForeground(bool isForeground) async {}

  @override
  Future<PushPermissionStatus> getPermissionStatus() async =>
      PushPermissionStatus.authorized;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> unregisterCurrentDevice() async {}

  @override
  Future<void> dispose() async {}
}
