abstract interface class IPresenceRepository {
  Stream<Set<String>> watchOnlineUserIds();

  Future<void> connect(String userId);

  Future<void> disconnect();
}
