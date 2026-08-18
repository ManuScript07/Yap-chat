import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';
import 'package:yap_chat/repositories/profile/avatar_storage_data_source.dart';
import 'package:yap_chat/repositories/profile/profile_cache_data_source.dart';

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
    final profile = await _hydrateAvatar(remoteProfile, session: session);
    await _writeCacheBestEffort(profile);
    return profile;
  }

  @override
  Future<UserProfile> completeProfile({
    required String userId,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    String? username,
    String? bio,
    Uint8List? avatarBytes,
    bool removeAvatar = false,
  }) async {
    final cachedProfile = await _readCacheBestEffort(userId);
    final currentAvatar = await _client
        .from('profiles')
        .select('avatar_storage_path')
        .eq('id', userId)
        .single();
    final previousStoragePath = currentAvatar['avatar_storage_path'] as String?;
    StoredAvatar? uploadedAvatar;

    if (avatarBytes != null) {
      uploadedAvatar = await _avatarStorage.upload(
        userId: userId,
        sourceBytes: avatarBytes,
      );
    }

    final normalizedUsername = username?.trim().toLowerCase();
    final avatarChanged = uploadedAvatar != null || removeAvatar;
    final update = <String, dynamic>{
      'display_name': displayName.trim(),
      'birth_date': birthDate.toIso8601String().split('T').first,
      'gender': gender.databaseValue,
      'bio': bio?.trim() ?? '',
      'onboarding_completed': true,
      if (avatarChanged) 'avatar_url': null,
      if (avatarChanged) 'avatar_storage_path': uploadedAvatar?.path,
      if (avatarChanged)
        'avatar_updated_at': uploadedAvatar == null
            ? null
            : DateTime.now().toUtc().toIso8601String(),
    };
    if (normalizedUsername != null && normalizedUsername.isNotEmpty) {
      update['username'] = normalizedUsername;
    }

    late final Map<String, dynamic> result;
    try {
      result = await _client
          .from('profiles')
          .update(update)
          .eq('id', userId)
          .select()
          .single();
    } on PostgrestException catch (error) {
      if (uploadedAvatar != null) {
        await _deleteAvatarBestEffort(uploadedAvatar.path);
      }
      if (error.code == '23505') throw const UsernameAlreadyTakenException();
      rethrow;
    } catch (_) {
      if (uploadedAvatar != null) {
        await _deleteAvatarBestEffort(uploadedAvatar.path);
      }
      rethrow;
    }

    var profile = UserProfile.fromMap(result);
    if (uploadedAvatar != null) {
      profile = profile.copyWith(avatarBytes: uploadedAvatar.bytes);
    } else if (removeAvatar) {
      profile = profile.copyWith(
        clearAvatarUrl: true,
        clearAvatarStoragePath: true,
        clearAvatarBytes: true,
        clearAvatarUpdatedAt: true,
      );
    } else if (cachedProfile?.avatarStoragePath == profile.avatarStoragePath) {
      profile = profile.copyWith(avatarBytes: cachedProfile?.avatarBytes);
    }

    await _writeCacheBestEffort(profile);
    if (avatarChanged &&
        previousStoragePath != null &&
        previousStoragePath != uploadedAvatar?.path) {
      await _deleteAvatarBestEffort(previousStoragePath);
    }
    return profile;
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

  Future<UserProfile> _hydrateAvatar(
    UserProfile profile, {
    required AuthSession session,
  }) async {
    final cached = await _readCacheBestEffort(profile.id);
    final storagePath = profile.avatarStoragePath;
    if (storagePath != null) {
      if (cached?.avatarStoragePath == storagePath &&
          cached?.avatarBytes != null) {
        return profile.copyWith(avatarBytes: cached!.avatarBytes);
      }
      try {
        final bytes = await _avatarStorage.download(storagePath);
        return profile.copyWith(avatarBytes: bytes);
      } catch (_) {
        return profile;
      }
    }

    final externalUrl = profile.avatarUrl ?? session.avatarUrl;
    final sourceUri = externalUrl == null ? null : Uri.tryParse(externalUrl);
    if (sourceUri == null || !sourceUri.hasScheme) return profile;

    StoredAvatar? storedAvatar;
    try {
      storedAvatar = await _avatarStorage.copyExternal(sourceUrl: sourceUri);
      return profile.copyWith(
        avatarStoragePath: storedAvatar.path,
        avatarBytes: storedAvatar.bytes,
        avatarUpdatedAt: storedAvatar.updatedAt,
      );
    } catch (_) {
      return profile;
    }
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
