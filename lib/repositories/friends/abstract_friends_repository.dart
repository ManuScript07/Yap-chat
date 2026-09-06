import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends_cache_data_source.dart';

abstract interface class IFriendsRepository {
  /// The own-friends screen consumes this cursor-backed stream.
  Stream<List<Friend>> watchPaginatedFriends();

  /// Kept as an alias while older presentation code migrates to the explicit
  /// paginated name. It never performs an unbounded server read.
  Stream<List<Friend>> watchFriends();
  Stream<FriendListCacheState> watchFriendListState();
  Stream<List<FriendRequest>> watchRequests();
  Stream<List<Friend>> watchCachedFriends();
  Stream<List<FriendRequest>> watchCachedRequests();

  Future<void> loadMoreFriends();
  Future<List<FriendRequest>> getRequests();
  Future<List<FriendCandidate>> searchUsers(String query);
  Future<ContactMatchSnapshot> readCachedContactMatches(
    List<String> phoneNumbers,
  );
  Future<ContactMatchSnapshot> readCachedPhoneSearchMatch(String phoneNumber);
  Future<ContactMatchSnapshot> refreshContactMatches(List<String> phoneNumbers);
  Future<ContactMatchSnapshot> refreshNewFriendContactMatches(
    List<String> phoneNumbers,
    Set<String> friendIds,
  );
  Future<ContactMatchSnapshot> refreshPhoneMatch(String phoneNumber);
  Future<String?> resolveFriendAvatar(Friend friend);
  Future<String?> resolveRequestAvatar(FriendRequest request);
  Future<String?> resolveCandidateAvatar(FriendCandidate candidate);

  Future<void> sendRequest(FriendCandidate candidate);
  Future<void> cancelRequest(String requestId);
  Future<void> respondToRequest(String requestId, {required bool accept});
  Future<FriendLocationLookup> getFriendLocation(String friendId);
  Future<void> pauseRealtime();
  Future<void> resumeRealtime();
}

abstract interface class IProfileFriendsRepository {
  Stream<String> watchProfileChanges();
  Future<FriendLocation?> getCachedFriendLocation(String friendId);
  Future<UserDistance?> getCachedUserDistance(String userId);
  Future<bool> isCachedUserDistanceFresh(String userId);
  Future<void> cacheUserDistance(String userId, UserDistance distance);
  Future<void> clearCachedUserDistances();
  Future<UserDistance?> getUserDistance(String userId);
  Future<void> removeFriend(String friendId);
}

extension ProfileFriendsRepositoryAccess on IFriendsRepository {
  IProfileFriendsRepository get _profiles => this as IProfileFriendsRepository;

  Stream<String> watchProfileChanges() => _profiles.watchProfileChanges();

  Future<FriendLocation?> getCachedFriendLocation(String friendId) =>
      _profiles.getCachedFriendLocation(friendId);
  Future<UserDistance?> getCachedUserDistance(String userId) =>
      _profiles.getCachedUserDistance(userId);
  Future<bool> isCachedUserDistanceFresh(String userId) =>
      _profiles.isCachedUserDistanceFresh(userId);
  Future<void> cacheUserDistance(String userId, UserDistance distance) =>
      _profiles.cacheUserDistance(userId, distance);
  Future<void> clearCachedUserDistances() =>
      _profiles.clearCachedUserDistances();
  Future<UserDistance?> getUserDistance(String userId) =>
      _profiles.getUserDistance(userId);
  Future<void> removeFriend(String friendId) =>
      _profiles.removeFriend(friendId);
}
