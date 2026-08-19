import 'package:yap_chat/repositories/presence/abstract_presence_repository.dart';

class MockPresenceRepository implements IPresenceRepository {
  @override
  Stream<Set<String>> watchOnlineUserIds() => const Stream.empty();

  @override
  Future<void> connect(String userId) async {}

  @override
  Future<void> disconnect() async {}
}
