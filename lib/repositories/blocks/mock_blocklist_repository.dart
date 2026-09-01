import 'dart:async';

import 'package:yap_chat/repositories/blocks/abstract_blocklist_repository.dart';
import 'package:yap_chat/repositories/blocks/blocked_user.dart';

class MockBlocklistRepository implements IBlocklistRepository {
  final _users = <BlockedUser>[];
  final _controller = StreamController<List<BlockedUser>>.broadcast();

  @override
  Stream<List<BlockedUser>> watchBlockedUsers() async* {
    yield List.unmodifiable(_users);
    yield* _controller.stream;
  }

  @override
  Stream<Set<String>> watchBlockedUserIds() =>
      watchBlockedUsers().map((users) => users.map((user) => user.id).toSet());

  @override
  Future<List<BlockedUser>> readCachedBlockedUsers() async =>
      List.unmodifiable(_users);

  @override
  Future<List<BlockedUser>> refreshBlockedUsers() => readCachedBlockedUsers();

  @override
  Future<void> blockUser(BlockedUser user) async {
    _users.removeWhere((item) => item.id == user.id);
    _users.add(user);
    _controller.add(List.unmodifiable(_users));
  }

  @override
  Future<void> unblockUser(String userId) async {
    _users.removeWhere((item) => item.id == userId);
    _controller.add(List.unmodifiable(_users));
  }

  @override
  Future<void> clearUserCache(String userId) async {
    _users.clear();
    _controller.add(const []);
  }
}
