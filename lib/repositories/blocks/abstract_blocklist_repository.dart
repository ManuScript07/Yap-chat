import 'package:yap_chat/repositories/blocks/blocked_user.dart';

abstract interface class IBlocklistRepository {
  Stream<List<BlockedUser>> watchBlockedUsers();
  Stream<Set<String>> watchBlockedUserIds();
  Stream<Set<String>> watchPendingUserIds();

  Future<List<BlockedUser>> readCachedBlockedUsers();
  Future<List<BlockedUser>> refreshBlockedUsers();
  Future<void> blockUser(BlockedUser user);
  Future<void> unblockUser(String userId);
  Future<void> clearUserCache(String userId);
}
