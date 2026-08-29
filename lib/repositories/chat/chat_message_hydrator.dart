import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';

class ChatMessageHydrator {
  const ChatMessageHydrator({
    required AppConfig config,
    required ChatRemoteDataSource remote,
    required MediaCacheService mediaCache,
  }) : _config = config,
       _remote = remote,
       _mediaCache = mediaCache;

  final AppConfig _config;
  final ChatRemoteDataSource _remote;
  final MediaCacheService _mediaCache;

  Future<List<ChatMessage>> hydrateAll(
    List<ChatMessage> messages, {
    String? ownerUserId,
  }) {
    return Future.wait(
      messages.map((message) => hydrate(message, ownerUserId: ownerUserId)),
    );
  }

  Future<ChatMessage> hydrate(
    ChatMessage message, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _remote.currentUserId;
    if (message.type == MessageType.image) {
      final localPaths = <String>[];
      for (final storagePath in message.mediaStoragePaths) {
        try {
          localPaths.add(
            await _mediaCache.cacheStorageFile(
              ownerUserId: owner,
              bucket: 'chat-images',
              storagePath: storagePath,
              mimeType: 'image/jpeg',
            ),
          );
        } catch (error, stackTrace) {
          _config.talker.handle(error, stackTrace, 'Image caching failed');
        }
      }
      return message.copyWith(mediaUrls: localPaths);
    }

    final audioStoragePath = message.audioStoragePath;
    if (message.type != MessageType.audio || audioStoragePath == null) {
      return message;
    }
    try {
      final localPath = await _mediaCache.cacheStorageFile(
        ownerUserId: owner,
        bucket: 'chat-audio',
        storagePath: audioStoragePath,
      );
      return message.copyWith(audioUrl: localPath);
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Audio caching failed');
      return message;
    }
  }
}
