import 'package:yap_chat/repositories/presence/abstract_presence_repository.dart';

class MockPresenceRepository
    implements IPresenceRepository, IPresenceWatchRepository {
  @override
  Stream<Set<String>> watchOnlineUserIds() => const Stream.empty();

  @override
  Future<void> connect(String userId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> setWatchScope(String scopeId, Iterable<String> userIds) async {}

  @override
  Future<void> removeWatchScope(String scopeId) async {}
}
