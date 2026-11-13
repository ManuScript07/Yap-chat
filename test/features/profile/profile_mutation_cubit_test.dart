import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/profile.dart';
import 'package:yap_chat/repositories/profile/profile.dart';

void main() {
  group('ProfileMutationCubit', () {
    test('does not call the repository for unchanged normalized data', () {
      final profile = _profile(username: 'before');
      final repository = _ControlledProfileRepository();
      final cubit = ProfileMutationCubit(repository: repository);
      addTearDown(cubit.close);
      cubit.setAuthenticatedUser(profile.id);

      final operationId = cubit.submit(
        currentProfile: profile,
        draft: ProfileDraft.fromProfile(profile),
      );

      expect(operationId, isNull);
      expect(repository.saveCallCount, 0);
      expect(cubit.state.status, ProfileMutationStatus.idle);
    });

    test('keeps one immutable operation alive until it succeeds', () async {
      final initial = _profile(username: 'before');
      final saved = _profile(username: 'after');
      final repository = _ControlledProfileRepository();
      final cubit = ProfileMutationCubit(
        repository: repository,
        uuid: const Uuid(),
      );
      addTearDown(cubit.close);
      cubit.setAuthenticatedUser(initial.id);
      final photos = <ProfilePhoto>[
        const ProfilePhoto(position: 0, storagePath: 'user/avatar.jpg'),
      ];
      final draft = ProfileDraft(
        userId: initial.id,
        displayName: 'Updated',
        birthDate: DateTime(2000),
        gender: ProfileGender.unspecified,
        username: 'after',
        bio: 'Bio',
        photos: photos,
      );

      final operationId = cubit.submit(currentProfile: initial, draft: draft);

      expect(operationId, isNotNull);
      expect(cubit.state.status, ProfileMutationStatus.submitting);
      expect(repository.saveCallCount, 1);
      photos.clear();
      expect(repository.receivedPhotos, hasLength(1));

      final repeatedOperationId = cubit.submit(
        currentProfile: initial,
        draft: ProfileDraft.fromProfile(saved),
      );
      expect(repeatedOperationId, operationId);
      expect(repository.saveCallCount, 1);

      repository.complete(saved);
      await _waitForState(
        cubit,
        (state) => state.status == ProfileMutationStatus.success,
      );

      expect(cubit.state.savedProfile, saved);
      expect(cubit.state.draft?.username, 'after');
    });

    test('maps a duplicate username to a retryable failure', () async {
      final initial = _profile(username: 'before');
      final repository = _ControlledProfileRepository();
      final cubit = ProfileMutationCubit(repository: repository);
      addTearDown(cubit.close);
      cubit.setAuthenticatedUser(initial.id);

      cubit.submit(
        currentProfile: initial,
        draft: ProfileDraft.fromProfile(_profile(username: 'taken')),
      );
      repository.completeError(const UsernameAlreadyTakenException());
      await _waitForState(
        cubit,
        (state) => state.status == ProfileMutationStatus.failure,
      );

      expect(cubit.state.failure, ProfileMutationFailure.usernameTaken);
      expect(cubit.state.draft?.username, 'taken');
    });

    test(
      'ignores an old result after the authenticated user changes',
      () async {
        final initial = _profile(username: 'before');
        final repository = _ControlledProfileRepository();
        final cubit = ProfileMutationCubit(repository: repository);
        addTearDown(cubit.close);
        cubit.setAuthenticatedUser(initial.id);

        cubit.submit(
          currentProfile: initial,
          draft: ProfileDraft.fromProfile(_profile(username: 'after')),
        );
        cubit.setAuthenticatedUser('another-user');
        repository.complete(_profile(username: 'after'));
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.status, ProfileMutationStatus.idle);
        expect(cubit.state.savedProfile, isNull);
      },
    );
  });
}

Future<void> _waitForState(
  ProfileMutationCubit cubit,
  bool Function(ProfileMutationState state) predicate,
) async {
  if (predicate(cubit.state)) return;
  await cubit.stream.firstWhere(predicate);
}

UserProfile _profile({required String username}) {
  final acceptedAt = DateTime.utc(2026);
  return UserProfile(
    id: 'user',
    username: username,
    displayName: 'User',
    birthDate: DateTime(2000),
    onboardingCompleted: true,
    termsAcceptedAt: acceptedAt,
    privacyAcceptedAt: acceptedAt,
  );
}

class _ControlledProfileRepository implements IProfileRepository {
  final _completer = Completer<UserProfile>();

  int saveCallCount = 0;
  List<ProfilePhoto>? receivedPhotos;

  void complete(UserProfile profile) => _completer.complete(profile);

  void completeError(Object error) => _completer.completeError(error);

  @override
  Future<UserProfile?> getCachedProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<String?> resolveSharedProfileUsername(String username) async => null;

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) =>
      throw UnimplementedError();

  @override
  Future<UserProfile> saveOwnProfile({
    required UserProfile currentProfile,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    required String username,
    required String bio,
    required List<ProfilePhoto> photos,
  }) {
    saveCallCount++;
    receivedPhotos = photos;
    return _completer.future;
  }
}
