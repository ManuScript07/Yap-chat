import 'dart:async';

import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/repositories/blocks/abstract_blocklist_repository.dart';
import 'package:yap_chat/repositories/blocks/blocked_user.dart';
import 'package:yap_chat/repositories/blocks/blocklist_remote_data_source.dart';

class BlocklistRepository implements IBlocklistRepository {
  BlocklistRepository({
    required BlocklistRemoteDataSource remote,
    required AccountSessionController accountSessionController,
  }) : _remote = remote,
       _accountSessionController = accountSessionController;

  final BlocklistRemoteDataSource _remote;
  final AccountSessionController _accountSessionController;
  final _controller = StreamController<List<BlockedUser>>.broadcast();
  final _pendingController = StreamController<Set<String>>.broadcast();
  List<BlockedUser> _users = const [];
  Set<String> _pendingUserIds = const {};

  @override
  Stream<List<BlockedUser>> watchBlockedUsers() async* {
    yield _users;
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
  Future<List<BlockedUser>> readCachedBlockedUsers() async => _users;

  @override
  Future<List<BlockedUser>> refreshBlockedUsers() async {
    final scope = _accountSessionController.capture();
    final users = await _remote.fetchBlockedUsers();
    _accountSessionController.ensureCurrent(scope);
    _users = List.unmodifiable(users);
    _controller.add(_users);
    return users;
  }

  @override
  Future<void> blockUser(BlockedUser user) => _runExclusive(user.id, () async {
    final scope = _accountSessionController.capture();
    await _remote.blockUser(user.id);
    _accountSessionController.ensureCurrent(scope);
    _users = List.unmodifiable([
      user,
      ..._users.where((item) => item.id != user.id),
    ]);
    _controller.add(_users);
  });

  @override
  Future<void> unblockUser(String userId) => _runExclusive(userId, () async {
    final scope = _accountSessionController.capture();
    await _remote.unblockUser(userId);
    _accountSessionController.ensureCurrent(scope);
    _users = List.unmodifiable(_users.where((item) => item.id != userId));
    _controller.add(_users);
  });

  @override
  Future<void> clearUserCache(String userId) async {
    _users = const [];
    _controller.add(_users);
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
