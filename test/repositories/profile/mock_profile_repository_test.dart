import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/mock_profile_repository.dart';

void main() {
  test('stores primary photo bytes only once in the dev profile', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = MockProfileRepository(preferences: preferences);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final current = UserProfile(
      id: 'mock-yandex-user',
      username: 'mockuser',
      displayName: 'Mock',
      birthDate: DateTime(2000, 1, 1),
      onboardingCompleted: false,
    );

    await repository.saveOwnProfile(
      currentProfile: current,
      displayName: current.displayName,
      birthDate: current.birthDate!,
      gender: ProfileGender.unspecified,
      username: current.username,
      bio: '',
      photos: [ProfilePhoto(position: 0, bytes: bytes)],
    );

    final encoded = preferences.getString('mock_user_profile');
    final json = jsonDecode(encoded!) as Map<String, dynamic>;
    expect(json['avatar_bytes'], isNull);
    expect((json['photos'] as List).single['bytes'], isNotNull);
  });

  test('keeps reordered photos after recreating the repository', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = MockProfileRepository(preferences: preferences);
    final acceptedAt = DateTime.utc(2026);
    final current = UserProfile(
      id: 'mock-user',
      username: 'mockuser',
      displayName: 'User',
      birthDate: DateTime(2000),
      onboardingCompleted: true,
      termsAcceptedAt: acceptedAt,
      privacyAcceptedAt: acceptedAt,
      photos: const [
        ProfilePhoto(position: 0, storagePath: 'mock-user/first.jpg'),
        ProfilePhoto(position: 1, storagePath: 'mock-user/second.jpg'),
      ],
    );

    await repository.saveOwnProfile(
      currentProfile: current,
      displayName: current.displayName,
      birthDate: current.birthDate!,
      gender: current.gender,
      username: current.username,
      bio: current.bio,
      photos: const [
        ProfilePhoto(position: 1, storagePath: 'mock-user/second.jpg'),
        ProfilePhoto(position: 0, storagePath: 'mock-user/first.jpg'),
      ],
    );
    final restored = await MockProfileRepository(
      preferences: preferences,
    ).getCachedProfile(current.id);

    expect(restored?.effectivePhotos.map((photo) => photo.storagePath), [
      'mock-user/second.jpg',
      'mock-user/first.jpg',
    ]);
    expect(restored?.effectivePhotos.map((photo) => photo.position), [0, 1]);
  });

  test('records an explicit removal of every photo', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = MockProfileRepository(preferences: preferences);
    final acceptedAt = DateTime.utc(2026);
    final current = UserProfile(
      id: 'mock-user',
      username: 'mockuser',
      displayName: 'User',
      birthDate: DateTime(2000),
      onboardingCompleted: true,
      termsAcceptedAt: acceptedAt,
      privacyAcceptedAt: acceptedAt,
      photos: const [
        ProfilePhoto(position: 0, avatarUrl: 'https://avatars.yandex.net/a'),
      ],
    );

    final saved = await repository.saveOwnProfile(
      currentProfile: current,
      displayName: current.displayName,
      birthDate: current.birthDate!,
      gender: current.gender,
      username: current.username,
      bio: current.bio,
      photos: const [],
    );

    expect(saved.effectivePhotos, isEmpty);
    expect(saved.yandexAvatarDisabled, isTrue);
    final restored = await MockProfileRepository(
      preferences: preferences,
    ).getCachedProfile(current.id);
    expect(restored?.yandexAvatarDisabled, isTrue);
  });
}
