import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/services/avatar_image_processor.dart';

class AvatarStorageDataSource {
  AvatarStorageDataSource({
    required SupabaseClient client,
    required AvatarImageProcessor imageProcessor,
  }) : _client = client,
       _imageProcessor = imageProcessor;

  static const bucketName = 'avatars';

  final SupabaseClient _client;
  final AvatarImageProcessor _imageProcessor;
  final Random _random = Random.secure();

  Future<StoredAvatar> upload({
    required String userId,
    required Uint8List sourceBytes,
  }) async {
    final compressedBytes = await _imageProcessor.compress(sourceBytes);
    final storagePath = _createStoragePath(userId);
    await _client.storage
        .from(bucketName)
        .uploadBinary(
          storagePath,
          compressedBytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '31536000',
          ),
          retryAttempts: 2,
        );
    return StoredAvatar(path: storagePath, bytes: compressedBytes);
  }

  Future<StoredAvatar> copyExternal({required Uri sourceUrl}) async {
    final response = await _client.functions.invoke(
      'import-profile-avatar',
      body: {'source_url': sourceUrl.toString()},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final storagePath = data['path'] as String?;
    if (storagePath == null || storagePath.isEmpty) {
      throw const AvatarImportException('Storage path is missing');
    }
    return StoredAvatar(
      path: storagePath,
      bytes: await download(storagePath),
      updatedAt: DateTime.tryParse(data['updated_at'] as String? ?? ''),
    );
  }

  Future<Uint8List> download(String storagePath) {
    return _client.storage.from(bucketName).download(storagePath);
  }

  Future<void> delete(String storagePath) async {
    await _client.storage.from(bucketName).remove([storagePath]);
  }

  String _createStoragePath(String userId) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final nonce = _random.nextInt(0x7fffffff).toRadixString(36);
    return '$userId/${timestamp}_$nonce.jpg';
  }
}

class StoredAvatar {
  const StoredAvatar({required this.path, required this.bytes, this.updatedAt});

  final String path;
  final Uint8List bytes;
  final DateTime? updatedAt;
}

class AvatarImportException implements Exception {
  const AvatarImportException(this.message);

  final String message;

  @override
  String toString() => 'AvatarImportException: $message';
}
