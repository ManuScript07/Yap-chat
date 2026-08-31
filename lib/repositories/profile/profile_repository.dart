import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';
import 'package:yap_chat/repositories/profile/avatar_storage_data_source.dart';
import 'package:yap_chat/repositories/profile/avatar_deletion_queue.dart';
import 'package:yap_chat/repositories/profile/profile_cache_data_source.dart';
import 'package:yap_chat/repositories/profile/profile_change_detector.dart';
import 'package:yap_chat/repositories/profile/viewed_profile_cache_data_source.dart';

class ProfileRepository
    implements IProfileRepository, IViewedProfileRepository {
  ProfileRepository({
    required SupabaseClient client,
    required ProfileCacheDataSource cache,
    required AvatarStorageDataSource avatarStorage,
    required AvatarDeletionQueue avatarDeletionQueue,
    required Talker talker,
    required AccountSessionController accountSessionController,
    required ViewedProfileCacheDataSource viewedProfileCache,
    required MediaCacheService mediaCache,
  }) : _client = client,
       _cache = cache,
       _avatarStorage = avatarStorage,
       _avatarDeletionQueue = avatarDeletionQueue,
       _accountSessionController = accountSessionController,
       _viewedProfileCache = viewedProfileCache,
       _mediaCache = mediaCache,
       _talker = talker;

  final SupabaseClient _client;
  final ProfileCacheDataSource _cache;
  final AvatarStorageDataSource _avatarStorage;
  final AvatarDeletionQueue _avatarDeletionQueue;
  final Talker _talker;
  final AccountSessionController _accountSessionController;
  final ViewedProfileCacheDataSource _viewedProfileCache;
  final MediaCacheService _mediaCache;
  final Map<String, Future<List<ViewedProfileFriend>>>
  _activeViewedProfileFriendsRequests = {};

  @override
  Future<UserProfile?> getCachedProfile(String userId) => _cache.read(userId);

  @override
  Future<ViewedProfile?> getCachedViewedProfile(String userId) {
    final scope = _accountSessionController.capture();
    return _viewedProfileCache.read(scope.userId, userId);
  }

  @override
  Future<ViewedProfile> getViewedProfile(
    String userId, {
    bool registerView = true,
  }) async {
    final scope = _accountSessionController.capture();
    final response = await _client.rpc<List<dynamic>>(
      'get_viewed_profile',
      params: {'target_user_id': userId, 'should_register_view': registerView},
    );
    _accountSessionController.ensureCurrent(scope);
    if (response.isEmpty) throw const ProfileNotFoundException();
    final row = Map<String, dynamic>.from(response.first as Map);
    final photos = _photoRows(row['photos']);
    final baseProfile = UserProfile.fromMap(row);
    // Older profiles can have only the primary avatar columns populated. Keep
    // that avatar in the photo list as well, so it is hydrated and persisted
    // by the same offline cache as every other profile photo.
    var profile = baseProfile.copyWith(
      photos: photos.isEmpty ? baseProfile.effectivePhotos : photos,
    );
    profile = await _hydrateViewedProfile(profile, scope);
    final viewedProfile = ViewedProfile(
      profile: profile,
      relationship: ProfileRelationship.values.byName(
        row['relationship'] as String? ?? ProfileRelationship.none.name,
      ),
      requestId: row['request_id'] as String?,
      friendCount: (row['friend_count'] as num?)?.toInt() ?? 0,
      friendsPreview: _viewedFriends(row['friends_preview']),
      viewCount: (row['profile_view_count'] as num?)?.toInt() ?? 0,
      lastSeenAt: DateTime.tryParse(
        row['last_seen_at'] as String? ?? '',
      )?.toLocal(),
      showsLastSeen: row['shows_last_seen'] as bool? ?? false,
    );
    await _accountSessionController.commit(
      scope,
      () => _viewedProfileCache.write(scope.userId, viewedProfile),
    );
    // The page always shows this small set of avatars. Warm their shared media
    // cache without delaying profile rendering, so an offline reopen has the
    // same result as friend and chat lists.
    unawaited(
      Future.wait(
        viewedProfile.friendsPreview.map(resolveViewedProfileFriendAvatar),
      ),
    );
    return viewedProfile;
  }

  @override
  Future<List<ViewedProfileFriend>> getCachedViewedProfileFriends(
    String userId,
  ) async {
    final scope = _accountSessionController.capture();
    final friends = await _viewedProfileCache.readFriends(scope.userId, userId);
    _accountSessionController.ensureCurrent(scope);
    return friends
        .where((friend) => friend.id != scope.userId)
        .toList(growable: false);
  }

  @override
  Future<DateTime?> getCachedViewedProfileFriendsUpdatedAt(
    String userId,
  ) async {
    final scope = _accountSessionController.capture();
    final cachedAt = await _viewedProfileCache.readFriendsCachedAt(
      scope.userId,
      userId,
    );
    _accountSessionController.ensureCurrent(scope);
    return cachedAt;
  }

  @override
  Future<List<ViewedProfileFriend>> getViewedProfileFriends(
    String userId,
  ) async {
    final scope = _accountSessionController.capture();
    final operationKey = '${scope.userId}:$userId';
    final active = _activeViewedProfileFriendsRequests[operationKey];
    if (active != null) return active;
    final request = _fetchViewedProfileFriends(userId, scope);
    _activeViewedProfileFriendsRequests[operationKey] = request;
    try {
      return await request;
    } finally {
      if (identical(
        _activeViewedProfileFriendsRequests[operationKey],
        request,
      )) {
        _activeViewedProfileFriendsRequests.remove(operationKey);
      }
    }
  }

  Future<List<ViewedProfileFriend>> _fetchViewedProfileFriends(
    String userId,
    AccountSessionSnapshot scope,
  ) async {
    final response = await _client.rpc<List<dynamic>>(
      'get_user_profile_friends',
      params: {'target_user_id': userId},
    );
    _accountSessionController.ensureCurrent(scope);
    final friends = response
        .map((item) => _viewedFriend(Map<String, dynamic>.from(item as Map)))
        .where((friend) => friend.id != scope.userId)
        .toList(growable: false);
    await _accountSessionController.commit(
      scope,
      () => _viewedProfileCache.replaceFriends(scope.userId, userId, friends),
    );
    return friends;
  }

  @override
  Future<String?> resolveViewedProfileFriendAvatar(
    ViewedProfileFriend friend,
  ) async {
    final scope = _accountSessionController.capture();
    try {
      final storagePath = friend.avatarStoragePath;
      if (storagePath != null && storagePath.isNotEmpty) {
        final path = await _mediaCache.cacheStorageFile(
          ownerUserId: scope.userId,
          bucket: AvatarStorageDataSource.bucketName,
          storagePath: storagePath,
          mimeType: 'image/jpeg',
        );
        _accountSessionController.ensureCurrent(scope);
        return path;
      }
      final url = friend.avatarUrl;
      if (url != null && url.isNotEmpty) {
        final path = await _mediaCache.cacheNetworkFile(
          ownerUserId: scope.userId,
          url: url,
        );
        _accountSessionController.ensureCurrent(scope);
        return path;
      }
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Viewed profile avatar caching failed');
    }
    return null;
  }

  @override
  Future<int?> getCachedProfileViewCount(String userId) {
    final scope = _accountSessionController.capture();
    return _viewedProfileCache.readViewCount(scope.userId, userId);
  }

  @override
  Future<int> getProfileViewCount(String userId) async {
    final scope = _accountSessionController.capture();
    final value = await _client.rpc<num>(
      'get_profile_view_count',
      params: {'target_user_id': userId},
    );
    _accountSessionController.ensureCurrent(scope);
    final count = value.toInt();
    await _accountSessionController.commit(
      scope,
      () => _viewedProfileCache.writeViewCount(scope.userId, userId, count),
    );
    return count;
  }

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async {
    final scope = _accountSessionController.capture();
    if (scope.userId != session.userId) {
      throw const StaleAccountSessionException();
    }
    final existing = await _client
        .from('profiles')
        .select()
        .eq('id', session.userId)
        .maybeSingle();
    _accountSessionController.ensureCurrent(scope);

    final remoteProfile = existing == null
        ? await _createProfile(session, scope)
        : await _fillMissingYandexData(
            UserProfile.fromMap(existing),
            session,
            scope,
          );
    _accountSessionController.ensureCurrent(scope);
    final remotePhotos = await _loadRemotePhotos(remoteProfile);
    _accountSessionController.ensureCurrent(scope);
    final profile = await _hydratePhotos(
      remoteProfile.copyWith(photos: remotePhotos),
      session: session,
      scope: scope,
    );
    await _accountSessionController.commit(
      scope,
      () => _writeCacheBestEffort(profile),
    );
    unawaited(_reconcileAvatarDeletions(profile));
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
    final scope = _accountSessionController.capture();
    if (scope.userId != currentProfile.id) {
      throw const StaleAccountSessionException();
    }
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
    final stopwatch = Stopwatch()..start();
    final uploadCount = photos.where((photo) => photo.needsUpload).length;
    _talker.info(
      'Profile save started: photos=${photos.length}, uploads=$uploadCount',
    );
    final savedPhotos = <ProfilePhoto>[];
    try {
      for (var index = 0; index < photos.length; index++) {
        _accountSessionController.ensureCurrent(scope);
        final photo = photos[index];
        if (photo.needsUpload) {
          final uploaded = await _avatarStorage.upload(
            userId: userId,
            sourceBytes: photo.bytes!,
          );
          try {
            await _avatarDeletionQueue.enqueue(userId, [uploaded.path]);
          } catch (_) {
            await _deleteAvatarBestEffort(uploaded.path);
            rethrow;
          }
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

      await _avatarDeletionQueue.enqueue(
        userId,
        currentProfile.effectivePhotos
            .map((photo) => photo.storagePath)
            .whereType<String>(),
      );

      _accountSessionController.ensureCurrent(scope);
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
      _accountSessionController.ensureCurrent(scope);
      if (response.isEmpty) throw const ProfileSaveException();

      var profile = UserProfile.fromMap(
        Map<String, dynamic>.from(response.first as Map),
      );
      final hydratedPhotos = _reuseCachedPhotoBytes(
        savedPhotos,
        currentProfile.effectivePhotos,
      );
      profile = _withPhotos(profile, hydratedPhotos);
      await _accountSessionController.commit(
        scope,
        () => _writeCacheBestEffort(profile),
      );

      unawaited(_reconcileAvatarDeletions(profile));
      _talker.info(
        'Profile save completed: durationMs=${stopwatch.elapsedMilliseconds}, '
        'photos=${hydratedPhotos.length}, uploads=$uploadCount',
      );
      return profile;
    } on PostgrestException catch (error, stackTrace) {
      if (error.code == '23505') {
        _talker.warning(
          'Profile save rejected: code=23505, '
          'durationMs=${stopwatch.elapsedMilliseconds}',
        );
        throw const UsernameAlreadyTakenException();
      }
      _talker.handle(
        error,
        stackTrace,
        'Profile save failed: code=${error.code}, '
        'durationMs=${stopwatch.elapsedMilliseconds}',
      );
      rethrow;
    } catch (error, stackTrace) {
      _talker.handle(
        error,
        stackTrace,
        'Profile save failed: durationMs=${stopwatch.elapsedMilliseconds}',
      );
      rethrow;
    }
  }

  Future<UserProfile> _createProfile(
    AuthSession session,
    AccountSessionSnapshot scope,
  ) async {
    _accountSessionController.ensureCurrent(scope);
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
      _accountSessionController.ensureCurrent(scope);
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', session.userId)
          .single();
      return _fillMissingYandexData(
        UserProfile.fromMap(profile),
        session,
        scope,
      );
    }
  }

  Future<UserProfile> _fillMissingYandexData(
    UserProfile profile,
    AuthSession session,
    AccountSessionSnapshot scope,
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
    if (!profile.yandexAvatarDisabled &&
        profile.avatarUrl == null &&
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

    _accountSessionController.ensureCurrent(scope);
    final updated = await _client
        .from('profiles')
        .update(update)
        .eq('id', session.userId)
        .select()
        .single();
    return UserProfile.fromMap(updated);
  }

  List<ProfilePhoto> _photoRows(Object? value) {
    final rows = value is List<dynamic> ? value : const <dynamic>[];
    return rows
        .map((item) {
          final row = Map<String, dynamic>.from(item as Map);
          return ProfilePhoto(
            position: (row['position'] as num?)?.toInt() ?? 0,
            avatarUrl: row['avatar_url'] as String?,
            storagePath: row['storage_path'] as String?,
            updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
          );
        })
        .toList(growable: false);
  }

  List<ViewedProfileFriend> _viewedFriends(Object? value) {
    final rows = value is List<dynamic> ? value : const <dynamic>[];
    return rows
        .map((item) => _viewedFriend(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  ViewedProfileFriend _viewedFriend(Map<String, dynamic> row) {
    final storagePath = row['avatar_storage_path'] as String?;
    return ViewedProfileFriend(
      id: row['id'] as String,
      username: row['username'] as String? ?? '',
      displayName: row['display_name'] as String? ?? '',
      avatarUrl: storagePath == null ? row['avatar_url'] as String? : null,
      avatarStoragePath: storagePath,
    );
  }

  Future<UserProfile> _hydrateViewedProfile(
    UserProfile profile,
    AccountSessionSnapshot scope,
  ) async {
    final cached = await _readCacheBestEffort(profile.id);
    final hydrated = <ProfilePhoto>[];
    for (final photo in profile.photos) {
      _accountSessionController.ensureCurrent(scope);
      final cachedPhoto = _matchingCachedPhoto(
        photo,
        cached?.photos ?? const [],
      );
      if (cachedPhoto?.bytes != null) {
        hydrated.add(photo.copyWith(bytes: cachedPhoto!.bytes));
        continue;
      }
      final storagePath = photo.storagePath;
      try {
        if (storagePath != null) {
          hydrated.add(
            photo.copyWith(bytes: await _avatarStorage.download(storagePath)),
          );
          continue;
        }
        final url = photo.avatarUrl;
        if (url != null && url.isNotEmpty) {
          final localPath = await _mediaCache.cacheNetworkFile(
            ownerUserId: scope.userId,
            url: url,
          );
          hydrated.add(
            photo.copyWith(bytes: await File(localPath).readAsBytes()),
          );
          continue;
        }
        hydrated.add(photo);
      } catch (error, stackTrace) {
        _talker.handle(error, stackTrace, 'Viewed profile photo load failed');
        hydrated.add(photo);
      }
    }
    return _withPhotos(profile, hydrated);
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
    if (photos.isNotEmpty) return _alignPrimaryPhoto(profile, photos);
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

  List<ProfilePhoto> _alignPrimaryPhoto(
    UserProfile profile,
    List<ProfilePhoto> photos,
  ) {
    if (photos.length < 2) return photos;
    final primaryIndex = photos.indexWhere(
      (photo) => profile.avatarStoragePath != null
          ? photo.storagePath == profile.avatarStoragePath
          : profile.avatarUrl != null && photo.avatarUrl == profile.avatarUrl,
    );
    if (primaryIndex <= 0) return photos;

    final aligned = photos.toList()..insert(0, photos[primaryIndex]);
    aligned.removeAt(primaryIndex + 1);
    return [
      for (var index = 0; index < aligned.length; index++)
        aligned[index].copyWith(position: index),
    ];
  }

  Future<UserProfile> _hydratePhotos(
    UserProfile profile, {
    required AuthSession session,
    required AccountSessionSnapshot scope,
  }) async {
    final cached = await _readCacheBestEffort(profile.id);
    final hydrated = <ProfilePhoto>[];
    for (final photo in profile.photos) {
      _accountSessionController.ensureCurrent(scope);
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
            _accountSessionController.ensureCurrent(scope);
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
        !profile.yandexAvatarDisabled &&
        profile.avatarUrl == null &&
        profile.avatarStoragePath == null &&
        session.avatarUrl != null) {
      hydrated.add(ProfilePhoto(position: 0, avatarUrl: session.avatarUrl));
    }
    final cachedExternalPhotos = <ProfilePhoto>[];
    for (final photo in hydrated) {
      if (photo.bytes != null || photo.avatarUrl == null) {
        cachedExternalPhotos.add(photo);
        continue;
      }
      try {
        final localPath = await _mediaCache.cacheNetworkFile(
          ownerUserId: scope.userId,
          url: photo.avatarUrl!,
        );
        cachedExternalPhotos.add(
          photo.copyWith(bytes: await File(localPath).readAsBytes()),
        );
      } catch (_) {
        // An external avatar can still be shown online; a failed cache write
        // must not prevent profile loading.
        cachedExternalPhotos.add(photo);
      }
    }
    return _withPhotos(profile, cachedExternalPhotos);
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

  Future<void> _reconcileAvatarDeletions(UserProfile profile) {
    return _avatarDeletionQueue.reconcile(
      ownerUserId: profile.id,
      referencedPaths: profile.effectivePhotos
          .map((photo) => photo.storagePath)
          .whereType<String>()
          .toSet(),
      delete: _avatarStorage.delete,
    );
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

class ProfileNotFoundException implements Exception {
  const ProfileNotFoundException();
}

class ProfilePhotoLimitException implements Exception {
  const ProfilePhotoLimitException();
}

class ProfileSaveException implements Exception {
  const ProfileSaveException();
}
