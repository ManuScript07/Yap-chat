import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';

abstract interface class IProfileRepository {
  Future<UserProfile?> getCachedProfile(String userId);

  Future<UserProfile> getOrCreateProfile(AuthSession session);

  Future<UserProfile> saveOwnProfile({
    required UserProfile currentProfile,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    required String username,
    required String bio,
    required List<ProfilePhoto> photos,
  });
}

abstract interface class IViewedProfileRepository {
  Future<ViewedProfile?> getCachedViewedProfile(String userId);
  Future<ViewedProfile> getViewedProfile(
    String userId, {
    bool registerView = true,
  });
  Future<List<ViewedProfileFriend>> getCachedViewedProfileFriends(
    String userId,
  );
  Future<List<ViewedProfileFriend>> getViewedProfileFriends(String userId);
  Future<String?> resolveViewedProfileFriendAvatar(ViewedProfileFriend friend);
  Future<int?> getCachedProfileViewCount(String userId);
  Future<int> getProfileViewCount(String userId);
}

extension ViewedProfileRepositoryAccess on IProfileRepository {
  IViewedProfileRepository get _viewedProfiles =>
      this as IViewedProfileRepository;

  Future<ViewedProfile?> getCachedViewedProfile(String userId) =>
      _viewedProfiles.getCachedViewedProfile(userId);
  Future<ViewedProfile> getViewedProfile(
    String userId, {
    bool registerView = true,
  }) => _viewedProfiles.getViewedProfile(userId, registerView: registerView);
  Future<List<ViewedProfileFriend>> getCachedViewedProfileFriends(
    String userId,
  ) => _viewedProfiles.getCachedViewedProfileFriends(userId);
  Future<List<ViewedProfileFriend>> getViewedProfileFriends(String userId) =>
      _viewedProfiles.getViewedProfileFriends(userId);
  Future<String?> resolveViewedProfileFriendAvatar(
    ViewedProfileFriend friend,
  ) => _viewedProfiles.resolveViewedProfileFriendAvatar(friend);
  Future<int?> getCachedProfileViewCount(String userId) =>
      _viewedProfiles.getCachedProfileViewCount(userId);
  Future<int> getProfileViewCount(String userId) =>
      _viewedProfiles.getProfileViewCount(userId);
}

class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();
}
