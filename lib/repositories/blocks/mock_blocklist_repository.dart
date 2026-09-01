import 'dart:async';

import 'package:yap_chat/repositories/blocks/abstract_blocklist_repository.dart';
import 'package:yap_chat/repositories/blocks/blocked_user.dart';

class MockBlocklistRepository implements IBlocklistRepository {
  final _users = <BlockedUser>[];
  final _controller = StreamController<List<BlockedUser>>.broadcast();
  final _pendingController = StreamController<Set<String>>.broadcast();
  Set<String> _pendingUserIds = const {};

  @override
  Stream<List<BlockedUser>> watchBlockedUsers() async* {
    yield List.unmodifiable(_users);
    yield* _controller.stream;
  }

  @override
  Stream<Set<String>> watchBlockedUserIds() =>
      watchBlockedUsers().map((users) => users.map((user) => user.id).toSet());

  @override
  Stream<Set<String>> watchPendingUserIds() async* {
    yield _pendingUserIds;
    yield* _pendingController.stream;
  }

  @override
  Future<List<BlockedUser>> readCachedBlockedUsers() async =>
      List.unmodifiable(_users);

  @override
  Future<List<BlockedUser>> refreshBlockedUsers() => readCachedBlockedUsers();

  @override
  Future<void> blockUser(BlockedUser user) => _runExclusive(user.id, () async {
    _users.removeWhere((item) => item.id == user.id);
    _users.add(user);
    _controller.add(List.unmodifiable(_users));
  });

  @override
  Future<void> unblockUser(String userId) => _runExclusive(userId, () async {
    _users.removeWhere((item) => item.id == userId);
    _controller.add(List.unmodifiable(_users));
  });

  @override
  Future<void> clearUserCache(String userId) async {
    _users.clear();
    _controller.add(const []);
  }

  Future<void> _runExclusive(
    String userId,
    Future<void> Function() operation,
  ) async {
    if (_pendingUserIds.contains(userId)) return;
    _pendingUserIds = Set.unmodifiable({..._pendingUserIds, userId});
    _pendingController.add(_pendingUserIds);
    try {
      await operation();
    } finally {
      _pendingUserIds = Set.unmodifiable(
        _pendingUserIds.where((id) => id != userId),
      );
      _pendingController.add(_pendingUserIds);
    }
  }
}
