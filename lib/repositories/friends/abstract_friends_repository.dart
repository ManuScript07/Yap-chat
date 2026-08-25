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
  Future<ContactMatchSnapshot> refreshContactMatches(
    List<String> phoneNumbers,
  );
  Future<ContactMatchSnapshot> refreshPhoneMatch(String phoneNumber);
  Future<String?> resolveFriendAvatar(Friend friend);
  Future<String?> resolveRequestAvatar(FriendRequest request);
  Future<String?> resolveCandidateAvatar(FriendCandidate candidate);

  Future<void> sendRequest(FriendCandidate candidate);
  Future<void> cancelRequest(String requestId);
  Future<void> respondToRequest(String requestId, {required bool accept});
  Future<FriendLocation?> getFriendLocation(String friendId);

  Future<void> pauseRealtime();
  Future<void> resumeRealtime();
}
