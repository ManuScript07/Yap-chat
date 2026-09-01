import 'package:yap_chat/repositories/blocks/blocked_user.dart';
import 'package:yap_chat/repositories/blocks/blocklist_cache_data_source.dart';

abstract interface class IBlocklistRepository {
  Stream<List<BlockedUser>> watchBlockedUsers();
  Stream<Set<String>> watchBlockedUserIds();
  Stream<Set<String>> watchPendingUserIds();

  Future<BlocklistCacheSnapshot?> readCachedBlockedUsers();
  Future<List<BlockedUser>> refreshBlockedUsers();
  Future<void> blockUser(BlockedUser user);
  Future<void> unblockUser(String userId);
  Future<void> clearUserCache(String userId);
}
