import 'package:yap_chat/features/friends/data/data.dart';

abstract interface class IFriendsRepository {
  Stream<List<Friend>> watchFriends();
  Stream<List<FriendRequest>> watchRequests();

  Future<List<Friend>> getFriends();
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
  Future<FriendLocation?> getCachedFriendLocation(String friendId);
  Future<UserDistance?> getCachedUserDistance(String userId);
  Future<UserDistance?> getUserDistance(String userId);
  Future<void> removeFriend(String friendId);
}

extension ProfileFriendsRepositoryAccess on IFriendsRepository {
  IProfileFriendsRepository get _profiles => this as IProfileFriendsRepository;

  Future<FriendLocation?> getCachedFriendLocation(String friendId) =>
      _profiles.getCachedFriendLocation(friendId);
  Future<UserDistance?> getCachedUserDistance(String userId) =>
      _profiles.getCachedUserDistance(userId);
  Future<UserDistance?> getUserDistance(String userId) =>
      _profiles.getUserDistance(userId);
  Future<void> removeFriend(String friendId) =>
      _profiles.removeFriend(friendId);
}
