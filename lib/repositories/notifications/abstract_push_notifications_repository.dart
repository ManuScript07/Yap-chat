enum PushPermissionStatus { authorized, provisional, denied, notDetermined }

abstract interface class IPushNotificationsRepository {
  Stream<String> get openedConversationIds;

  Future<void> setAuthenticatedUser(String? userId);

  Future<void> setActiveConversation(String? conversationId);

  Future<void> setAppForeground(bool isForeground);

  Future<PushPermissionStatus> getPermissionStatus();

  Future<void> openAppSettings();

  Future<void> unregisterCurrentDevice();

  Future<void> cancelAll();

  Future<void> dispose();
}
