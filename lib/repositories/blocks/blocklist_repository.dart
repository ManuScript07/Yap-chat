import 'dart:async';

import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/repositories/blocks/abstract_blocklist_repository.dart';
import 'package:yap_chat/repositories/blocks/blocked_user.dart';
import 'package:yap_chat/repositories/blocks/blocklist_cache_data_source.dart';
import 'package:yap_chat/repositories/blocks/blocklist_remote_data_source.dart';

class BlocklistRepository implements IBlocklistRepository {
  BlocklistRepository({
    required BlocklistRemoteDataSource remote,
    required BlocklistCacheDataSource cache,
    required AccountSessionController accountSessionController,
  }) : _remote = remote,
       _cache = cache,
       _accountSessionController = accountSessionController;

  final BlocklistRemoteDataSource _remote;
  final BlocklistCacheDataSource _cache;
  final AccountSessionController _accountSessionController;
  final _controller = StreamController<List<BlockedUser>>.broadcast();
  final _pendingController = StreamController<Set<String>>.broadcast();
  List<BlockedUser> _users = const [];
  Set<String> _pendingUserIds = const {};
  String? _ownerUserId;
  int _localRevision = 0;

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
  Future<BlocklistCacheSnapshot?> readCachedBlockedUsers() async {
    final scope = _accountSessionController.capture();
    final revision = _localRevision;
    if (_ownerUserId != scope.userId) {
      _ownerUserId = scope.userId;
      _publishUsers(const []);
    }
    final snapshot = await _cache.read(scope.userId);
    _accountSessionController.ensureCurrent(scope);
    if (snapshot != null &&
        _localRevision == revision &&
        _ownerUserId == scope.userId) {
      _publishUsers(snapshot.users);
    }
    return snapshot;
  }

  @override
  Future<List<BlockedUser>> refreshBlockedUsers() async {
    final scope = _accountSessionController.capture();
    final revision = _localRevision;
    final users = await _remote.fetchBlockedUsers();
    _accountSessionController.ensureCurrent(scope);
    await _accountSessionController.commit(scope, () async {
      // Do not overwrite a newer successful local ban/unban with a refresh
      // that began before that mutation completed.
      if (_localRevision != revision) return;
      try {
        await _cache.replaceAll(scope.userId, users);
      } catch (_) {
        // The server response remains usable if local storage is unavailable.
      }
      _ownerUserId = scope.userId;
      _publishUsers(users);
    });
    return _ownerUserId == scope.userId ? _users : users;
  }

  @override
  Future<void> blockUser(BlockedUser user) => _runExclusive(user.id, () async {
    final scope = _accountSessionController.capture();
    await _remote.blockUser(user.id);
    _accountSessionController.ensureCurrent(scope);
    await _accountSessionController.commit(scope, () async {
      final users = [user, ..._users.where((item) => item.id != user.id)];
      try {
        await _cache.replaceAll(scope.userId, users);
      } catch (_) {
        // Keep the confirmed server state in memory even if SQLite is full.
      }
      _ownerUserId = scope.userId;
      _localRevision++;
      _publishUsers(users);
    });
  });

  @override
  Future<void> unblockUser(String userId) => _runExclusive(userId, () async {
    final scope = _accountSessionController.capture();
    await _remote.unblockUser(userId);
    _accountSessionController.ensureCurrent(scope);
    await _accountSessionController.commit(scope, () async {
      final users = _users.where((item) => item.id != userId).toList();
      try {
        await _cache.replaceAll(scope.userId, users);
      } catch (_) {
        // Keep the confirmed server state in memory even if SQLite is full.
      }
      _ownerUserId = scope.userId;
      _localRevision++;
      _publishUsers(users);
    });
  });

  @override
  Future<void> clearUserCache(String userId) async {
    await _cache.clearUser(userId);
    if (_ownerUserId == userId) {
      _ownerUserId = null;
      _localRevision++;
      _publishUsers(const []);
    }
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

  void _publishUsers(List<BlockedUser> users) {
    _users = List.unmodifiable(users);
    _controller.add(_users);
  }
}
