import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';
import 'package:yap_chat/repositories/profile/avatar_storage_data_source.dart';
import 'package:yap_chat/repositories/profile/profile_cache_data_source.dart';
import 'package:yap_chat/repositories/profile/profile_change_detector.dart';

class ProfileRepository implements IProfileRepository {
  ProfileRepository({
    required SupabaseClient client,
    required ProfileCacheDataSource cache,
    required AvatarStorageDataSource avatarStorage,
  }) : _client = client,
       _cache = cache,
       _avatarStorage = avatarStorage;

  final SupabaseClient _client;
  final ProfileCacheDataSource _cache;
  final AvatarStorageDataSource _avatarStorage;

  @override
  Future<UserProfile?> getCachedProfile(String userId) => _cache.read(userId);

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async {
    final existing = await _client
        .from('profiles')
        .select()
        .eq('id', session.userId)
        .maybeSingle();

    final remoteProfile = existing == null
        ? await _createProfile(session)
        : await _fillMissingYandexData(UserProfile.fromMap(existing), session);
    final remotePhotos = await _loadRemotePhotos(remoteProfile);
    final profile = await _hydratePhotos(
      remoteProfile.copyWith(photos: remotePhotos),
      session: session,
    );
    await _writeCacheBestEffort(profile);
    return profile;
  }

  @override
  Future<UserProfile> saveOwnProfile({
    required UserProfile currentProfile,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    required String username,
    required String bio,
    required List<ProfilePhoto> photos,
  }) async {
    if (photos.length > 5) {
      throw const ProfilePhotoLimitException();
    }
    if (isProfileSaveNoOp(
      currentProfile: currentProfile,
      displayName: displayName,
      birthDate: birthDate,
      gender: gender,
      username: username,
      bio: bio,
      photos: photos,
    )) {
      return currentProfile;
    }

    final userId = currentProfile.id;
    final uploadedPaths = <String>[];
    final savedPhotos = <ProfilePhoto>[];
    try {
      for (var index = 0; index < photos.length; index++) {
        final photo = photos[index];
        if (photo.needsUpload) {
          final uploaded = await _avatarStorage.upload(
            userId: userId,
            sourceBytes: photo.bytes!,
          );
          uploadedPaths.add(uploaded.path);
          savedPhotos.add(
            ProfilePhoto(
              position: index,
              storagePath: uploaded.path,
              bytes: uploaded.bytes,
              updatedAt: uploaded.updatedAt,
            ),
          );
        } else {
          savedPhotos.add(photo.copyWith(position: index));
        }
      }

      final response = await _client.rpc<List<dynamic>>(
        'save_own_profile',
        params: {
          'p_display_name': displayName.trim(),
          'p_birth_date': birthDate.toIso8601String().split('T').first,
          'p_gender': gender.databaseValue,
          'p_username': username.trim().toLowerCase(),
          'p_bio': bio.trim(),
          'p_photos': savedPhotos
              .map(
                (photo) => {
                  'avatar_url': photo.avatarUrl,
                  'storage_path': photo.storagePath,
                  'updated_at': photo.updatedAt?.toUtc().toIso8601String(),
                },
              )
              .toList(growable: false),
        },
      );
      if (response.isEmpty) throw const ProfileSaveException();

      var profile = UserProfile.fromMap(
        Map<String, dynamic>.from(response.first as Map),
      );
      final hydratedPhotos = _reuseCachedPhotoBytes(
        savedPhotos,
        currentProfile.effectivePhotos,
      );
      profile = _withPhotos(profile, hydratedPhotos);
      await _writeCacheBestEffort(profile);

      final keptPaths = hydratedPhotos
          .map((photo) => photo.storagePath)
          .whereType<String>()
          .toSet();
      for (final oldPath
          in currentProfile.effectivePhotos
              .map((photo) => photo.storagePath)
              .whereType<String>()) {
        if (!keptPaths.contains(oldPath)) {
          unawaited(_deleteAvatarBestEffort(oldPath));
        }
      }
      return profile;
    } on PostgrestException catch (error) {
      for (final path in uploadedPaths) {
        await _deleteAvatarBestEffort(path);
      }
      if (error.code == '23505') throw const UsernameAlreadyTakenException();
      rethrow;
    } catch (_) {
      for (final path in uploadedPaths) {
        await _deleteAvatarBestEffort(path);
      }
      rethrow;
    }
  }

  Future<UserProfile> _createProfile(AuthSession session) async {
    try {
      final acceptedAt = DateTime.now().toUtc().toIso8601String();
      final created = await _client
          .from('profiles')
          .insert({
            'id': session.userId,
            'display_name': session.displayName ?? '',
            'birth_date': session.birthDate?.toIso8601String().split('T').first,
            'avatar_url': session.avatarUrl,
            'terms_accepted_at': acceptedAt,
            'privacy_accepted_at': acceptedAt,
          })
          .select()
          .single();
      return UserProfile.fromMap(created);
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', session.userId)
          .single();
      return _fillMissingYandexData(UserProfile.fromMap(profile), session);
    }
  }

  Future<UserProfile> _fillMissingYandexData(
    UserProfile profile,
    AuthSession session,
  ) async {
    final update = <String, dynamic>{};
    if (profile.displayName.isEmpty && session.displayName != null) {
      update['display_name'] = session.displayName;
    }
    if (profile.birthDate == null && session.birthDate != null) {
      update['birth_date'] = session.birthDate!
          .toIso8601String()
          .split('T')
          .first;
    }
    if (profile.avatarUrl == null &&
        profile.avatarStoragePath == null &&
        session.avatarUrl != null) {
      update['avatar_url'] = session.avatarUrl;
    }
    if (profile.termsAcceptedAt == null || profile.privacyAcceptedAt == null) {
      final acceptedAt = DateTime.now().toUtc().toIso8601String();
      if (profile.termsAcceptedAt == null) {
        update['terms_accepted_at'] = acceptedAt;
      }
      if (profile.privacyAcceptedAt == null) {
        update['privacy_accepted_at'] = acceptedAt;
      }
    }
    if (update.isEmpty) return profile;

    final updated = await _client
        .from('profiles')
        .update(update)
        .eq('id', session.userId)
        .select()
        .single();
    return UserProfile.fromMap(updated);
  }

  Future<List<ProfilePhoto>> _loadRemotePhotos(UserProfile profile) async {
    final response = await _client
        .from('profile_photos')
        .select()
        .eq('profile_id', profile.id)
        .order('position');
    final photos = response
        .map(
          (row) => ProfilePhoto(
            position: (row['position'] as num).toInt(),
            avatarUrl: row['avatar_url'] as String?,
            storagePath: row['storage_path'] as String?,
            updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
          ),
        )
        .toList(growable: false);
    if (photos.isNotEmpty) return photos;
    if (profile.avatarUrl == null && profile.avatarStoragePath == null) {
      return const [];
    }
    return [
      ProfilePhoto(
        position: 0,
        avatarUrl: profile.avatarStoragePath == null ? profile.avatarUrl : null,
        storagePath: profile.avatarStoragePath,
        updatedAt: profile.avatarUpdatedAt,
      ),
    ];
  }

  Future<UserProfile> _hydratePhotos(
    UserProfile profile, {
    required AuthSession session,
  }) async {
    final cached = await _readCacheBestEffort(profile.id);
    final hydrated = <ProfilePhoto>[];
    for (final photo in profile.photos) {
      final cachedPhoto = _matchingCachedPhoto(
        photo,
        cached?.photos ?? const [],
      );
      if (cachedPhoto?.bytes != null) {
        hydrated.add(photo.copyWith(bytes: cachedPhoto!.bytes));
        continue;
      }

      final storagePath = photo.storagePath;
      if (storagePath != null) {
        try {
          hydrated.add(
            photo.copyWith(bytes: await _avatarStorage.download(storagePath)),
          );
        } catch (_) {
          hydrated.add(photo);
        }
        continue;
      }

      final sourceUri = photo.avatarUrl == null
          ? null
          : Uri.tryParse(photo.avatarUrl!);
      if (photo.position == 0 &&
          sourceUri != null &&
          sourceUri.hasScheme &&
          sourceUri.host == 'avatars.yandex.net') {
        try {
          final stored = await _avatarStorage.copyExternal(
            sourceUrl: sourceUri,
          );
          try {
            final response = await _client.rpc<List<dynamic>>(
              'adopt_imported_profile_avatar',
              params: {
                'p_storage_path': stored.path,
                'p_updated_at': stored.updatedAt?.toUtc().toIso8601String(),
              },
            );
            if (response.isEmpty) throw const ProfileSaveException();
          } catch (_) {
            await _deleteAvatarBestEffort(stored.path);
            rethrow;
          }
          hydrated.add(
            ProfilePhoto(
              position: photo.position,
              storagePath: stored.path,
              bytes: stored.bytes,
              updatedAt: stored.updatedAt,
            ),
          );
          continue;
        } catch (_) {
          // Внешний URL остаётся рабочим fallback при ошибке импорта.
        }
      }
      hydrated.add(photo);
    }

    if (hydrated.isEmpty &&
        profile.avatarUrl == null &&
        profile.avatarStoragePath == null &&
        session.avatarUrl != null) {
      hydrated.add(ProfilePhoto(position: 0, avatarUrl: session.avatarUrl));
    }
    return _withPhotos(profile, hydrated);
  }

  UserProfile _withPhotos(UserProfile profile, List<ProfilePhoto> photos) {
    final normalized = [
      for (var index = 0; index < photos.length; index++)
        photos[index].copyWith(position: index),
    ];
    final primary = normalized.firstOrNull;
    return profile.copyWith(
      photos: normalized,
      avatarUrl: primary?.avatarUrl,
      avatarStoragePath: primary?.storagePath,
      avatarBytes: primary?.bytes,
      avatarUpdatedAt: primary?.updatedAt,
      clearAvatarUrl: primary?.avatarUrl == null,
      clearAvatarStoragePath: primary?.storagePath == null,
      clearAvatarBytes: primary?.bytes == null,
      clearAvatarUpdatedAt: primary?.updatedAt == null,
    );
  }

  List<ProfilePhoto> _reuseCachedPhotoBytes(
    List<ProfilePhoto> photos,
    List<ProfilePhoto> cachedPhotos,
  ) {
    return photos
        .map((photo) {
          if (photo.bytes != null) return photo;
          final cached = _matchingCachedPhoto(photo, cachedPhotos);
          return cached?.bytes == null
              ? photo
              : photo.copyWith(bytes: cached!.bytes);
        })
        .toList(growable: false);
  }

  ProfilePhoto? _matchingCachedPhoto(
    ProfilePhoto photo,
    List<ProfilePhoto> cachedPhotos,
  ) {
    for (final cached in cachedPhotos) {
      if (photo.storagePath != null &&
          photo.storagePath == cached.storagePath) {
        return cached;
      }
      if (photo.avatarUrl != null && photo.avatarUrl == cached.avatarUrl) {
        return cached;
      }
    }
    return null;
  }

  Future<void> _deleteAvatarBestEffort(String storagePath) async {
    try {
      await _avatarStorage.delete(storagePath);
    } catch (_) {
      // Удаление старого файла не должно откатывать успешно сохранённый профиль.
    }
  }

  Future<UserProfile?> _readCacheBestEffort(String userId) async {
    try {
      return await _cache.read(userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCacheBestEffort(UserProfile profile) async {
    try {
      await _cache.write(profile);
    } catch (_) {
      // Удалённый профиль остаётся источником истины при сбое локального кеша.
    }
  }
}

class ProfilePhotoLimitException implements Exception {
  const ProfilePhotoLimitException();
}

class ProfileSaveException implements Exception {
  const ProfileSaveException();
}
