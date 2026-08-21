abstract interface class IPushNotificationsRepository {
  Stream<String> get openedConversationIds;

  Future<void> setAuthenticatedUser(String? userId);

  Future<void> setActiveConversation(String? conversationId);

  Future<void> setAppForeground(bool isForeground);

  Future<void> unregisterCurrentDevice();

  Future<void> dispose();
}
