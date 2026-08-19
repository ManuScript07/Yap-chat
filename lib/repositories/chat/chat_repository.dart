import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/chat_media_processor.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_chat_repository.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/conversation_sync_service.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';

class ChatRepository implements IChatRepository {
  ChatRepository({
    required AppConfig config,
    required ChatCacheDataSource cache,
    required ChatRemoteDataSource remote,
    required ChatMediaProcessor mediaProcessor,
    required MediaCacheService mediaCache,
    required ConversationSyncService syncService,
    Uuid uuid = const Uuid(),
  }) : _config = config,
       _cache = cache,
       _remote = remote,
       _mediaProcessor = mediaProcessor,
       _mediaCache = mediaCache,
       _syncService = syncService,
       _uuid = uuid;

  static const _retryInterval = Duration(seconds: 20);

  final AppConfig _config;
  final ChatCacheDataSource _cache;
  final ChatRemoteDataSource _remote;
  final ChatMediaProcessor _mediaProcessor;
  final MediaCacheService _mediaCache;
  final ConversationSyncService _syncService;
  final Uuid _uuid;
  final Set<String> _deliveringOperationIds = {};

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    late final StreamController<List<ChatMessage>> controller;
    StreamSubscription<List<ChatMessage>>? cacheSubscription;
    Timer? retryTimer;

    controller = StreamController<List<ChatMessage>>(
      onListen: () {
        _syncService.openConversation(chatId);
        cacheSubscription = _cache
            .watchMessages(chatId, currentUserId: _remote.currentUserId)
            .listen(controller.add, onError: controller.addError);
        retryTimer = Timer.periodic(
          _retryInterval,
          (_) => unawaited(_retryPending(chatId)),
        );
        unawaited(_initializeChat(chatId));
      },
      onCancel: () async {
        _syncService.closeConversation(chatId);
        retryTimer?.cancel();
        await cacheSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> _initializeChat(String chatId) async {
    await _retryPending(chatId);
    try {
      final messages = await _syncService.synchronizeRecent(chatId);
      final hasUnreadIncoming = messages.any(
        (message) => !message.isMine && message.readAt == null,
      );
      if (hasUnreadIncoming) await _remote.markAsRead(chatId);
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Initial chat sync failed');
    }
  }

  @override
  Future<bool> loadMoreMessages(String chatId) async {
    final cached = await _cache.readMessages(
      chatId,
      currentUserId: _remote.currentUserId,
    );
    final serverMessages = cached
        .where((message) => message.status != MessageStatus.sending)
        .toList(growable: false);
    if (serverMessages.isEmpty) return false;
    final oldest = serverMessages.last;
    final page = await _remote.fetchMessages(
      chatId,
      beforeTimestamp: oldest.timestamp,
      beforeMessageId: oldest.id,
      pageSize: ConversationSyncService.pageSize,
    );
    final hydrated = await _syncService.hydrateAll(page);
    await _cache.upsertMessages(hydrated);
    return page.length == ConversationSyncService.pageSize;
  }

  @override
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToMessageId,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return;
    await _enqueue(
      chatId: chatId,
      type: MessageType.text,
      text: normalizedText,
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<void> sendImages(
    String chatId,
    List<String> imagePaths, {
    String? replyToMessageId,
  }) async {
    if (imagePaths.isEmpty) return;
    for (var offset = 0; offset < imagePaths.length; offset += 5) {
      final end = (offset + 5).clamp(0, imagePaths.length);
      await _enqueue(
        chatId: chatId,
        type: MessageType.image,
        imagePaths: List.unmodifiable(imagePaths.sublist(offset, end)),
        replyToMessageId: offset == 0 ? replyToMessageId : null,
      );
    }
  }

  @override
  Future<void> sendAudio(
    String chatId,
    String audioPath,
    Duration duration,
    List<double> waveform, {
    String? replyToMessageId,
  }) async {
    final audio = await _mediaProcessor.persistAudio(audioPath, waveform);
    await _enqueue(
      chatId: chatId,
      type: MessageType.audio,
      audioPath: audio.path,
      audioDuration: duration,
      waveform: audio.waveform,
      audioMimeType: audio.mimeType,
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<void> sendLocation(
    String chatId,
    double latitude,
    double longitude, {
    String? replyToMessageId,
  }) async {
    await _enqueue(
      chatId: chatId,
      type: MessageType.location,
      latitude: latitude,
      longitude: longitude,
      replyToMessageId: replyToMessageId,
    );
  }

  @override
  Future<void> retryImages(String chatId, ChatMessage message) async {
    final operations = await _cache.readPendingOperations();
    final operation = operations
        .where((item) => item.id == message.id && item.chatId == chatId)
        .firstOrNull;
    if (operation == null) return;
    await _cache.markMessageStatus(message.id, MessageStatus.sending);
    await _deliver(operation);
  }

  @override
  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required bool deleteForEveryone,
  }) async {
    final pending = (await _cache.readPendingOperations())
        .where((operation) => operation.id == messageId)
        .firstOrNull;
    if (pending != null) {
      await _cache.removePendingOperation(messageId);
      await _cache.removeMessage(messageId);
      return;
    }
    await _remote.deleteMessage(
      messageId,
      deleteForEveryone: deleteForEveryone,
    );
    await _cache.removeMessage(messageId);
    await _syncService.synchronizeRecent(chatId);
  }

  Future<void> _enqueue({
    required String chatId,
    required MessageType type,
    String text = '',
    List<String> imagePaths = const [],
    String? audioPath,
    Duration? audioDuration,
    List<double> waveform = const [],
    String? audioMimeType,
    double? latitude,
    double? longitude,
    String? replyToMessageId,
  }) async {
    final id = _uuid.v4();
    final reply = await _createReply(replyToMessageId);
    final message = ChatMessage(
      id: id,
      chatId: chatId,
      senderId: _remote.currentUserId,
      text: text,
      timestamp: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      type: type,
      mediaUrls: imagePaths,
      audioUrl: audioPath,
      audioDuration: audioDuration,
      audioWaveform: waveform,
      latitude: latitude,
      longitude: longitude,
      replyTo: reply,
    );
    final operation = PendingMessageOperation(
      id: id,
      chatId: chatId,
      type: type.name,
      createdAt: message.timestamp.toUtc(),
      payload: {
        'text': text,
        'image_paths': imagePaths,
        'audio_path': audioPath,
        'audio_duration_ms': audioDuration?.inMilliseconds,
        'audio_waveform': waveform,
        'audio_mime_type': audioMimeType,
        'latitude': latitude,
        'longitude': longitude,
        'reply_to_message_id': replyToMessageId,
      },
    );
    await _cache.upsertMessage(message, isPending: true);
    await _cache.putPendingOperation(operation);
    await _deliver(operation);
  }

  Future<MessageReply?> _createReply(String? messageId) async {
    if (messageId == null) return null;
    final message = await _cache.readMessage(
      messageId,
      currentUserId: _remote.currentUserId,
    );
    if (message == null) return null;
    return MessageReply(
      messageId: message.id,
      senderId: message.senderId,
      isMine: message.isMine,
      type: message.type,
      text: message.text,
    );
  }

  Future<void> _retryPending(String chatId) async {
    final operations = await _cache.readPendingOperations();
    for (final operation in operations.where((item) => item.chatId == chatId)) {
      await _deliver(operation);
    }
  }

  Future<void> _deliver(PendingMessageOperation operation) async {
    if (!_deliveringOperationIds.add(operation.id)) return;
    try {
      final type = MessageType.values.byName(operation.type);
      final payload = operation.payload;
      final attachments = switch (type) {
        MessageType.image => await _uploadImages(operation),
        MessageType.audio => [await _uploadAudio(operation)],
        _ => const <Map<String, dynamic>>[],
      };
      await _remote.sendMessage(
        id: operation.id,
        chatId: operation.chatId,
        type: type,
        text: payload['text'] as String? ?? '',
        latitude: (payload['latitude'] as num?)?.toDouble(),
        longitude: (payload['longitude'] as num?)?.toDouble(),
        replyToMessageId: payload['reply_to_message_id'] as String?,
        attachments: attachments,
      );
      await _cache.markMessageStatus(operation.id, MessageStatus.sent);
      await _cache.removePendingOperation(operation.id);
      if (type == MessageType.audio) {
        await _mediaProcessor.deletePersistentAudio(
          payload['audio_path'] as String?,
        );
      }
      await _syncService.synchronizeRecent(operation.chatId);
    } catch (error, stackTrace) {
      await _cache.markPendingFailure(operation.id, error);
      _config.talker.handle(error, stackTrace, 'Pending message upload failed');
    } finally {
      _deliveringOperationIds.remove(operation.id);
    }
  }

  Future<List<Map<String, dynamic>>> _uploadImages(
    PendingMessageOperation operation,
  ) async {
    final sourcePaths = List<String>.from(
      operation.payload['image_paths'] as List? ?? const [],
    );
    final attachments = <Map<String, dynamic>>[];
    for (var index = 0; index < sourcePaths.length; index++) {
      final processed = await _mediaProcessor.processImage(sourcePaths[index]);
      final attachmentId = _attachmentId(operation.id, index);
      final storagePath = _storagePath(operation, '$index.jpg');
      await _remote.upload(
        bucket: 'chat-images',
        storagePath: storagePath,
        bytes: processed.bytes,
        contentType: processed.mimeType,
      );
      try {
        await _mediaCache.storeBytes(
          ownerUserId: _remote.currentUserId,
          bucket: 'chat-images',
          storagePath: storagePath,
          bytes: processed.bytes,
          mimeType: processed.mimeType,
        );
      } catch (error, stackTrace) {
        _config.talker.handle(
          error,
          stackTrace,
          'Uploaded image caching failed',
        );
      }
      attachments.add({
        'id': attachmentId,
        'position': index,
        'kind': 'image',
        'storage_path': storagePath,
        'mime_type': processed.mimeType,
        'size_bytes': processed.bytes.lengthInBytes,
        'width': processed.width,
        'height': processed.height,
      });
    }
    return attachments;
  }

  Future<Map<String, dynamic>> _uploadAudio(
    PendingMessageOperation operation,
  ) async {
    final sourcePath = operation.payload['audio_path'] as String;
    final bytes = await _mediaProcessor.readAudio(sourcePath);
    final mimeType =
        operation.payload['audio_mime_type'] as String? ?? 'audio/mp4';
    final extension = mimeType == 'audio/webm' ? 'webm' : 'm4a';
    final attachmentId = _attachmentId(operation.id, 0);
    final storagePath = _storagePath(operation, '0.$extension');
    await _remote.upload(
      bucket: 'chat-audio',
      storagePath: storagePath,
      bytes: bytes,
      contentType: mimeType,
    );
    try {
      await _mediaCache.storeFile(
        ownerUserId: _remote.currentUserId,
        bucket: 'chat-audio',
        storagePath: storagePath,
        sourcePath: sourcePath,
        mimeType: mimeType,
      );
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Uploaded audio caching failed');
    }
    return {
      'id': attachmentId,
      'position': 0,
      'kind': 'audio',
      'storage_path': storagePath,
      'mime_type': mimeType,
      'size_bytes': bytes.lengthInBytes,
      'duration_ms': operation.payload['audio_duration_ms'],
      'waveform': operation.payload['audio_waveform'] ?? const [],
    };
  }

  String _storagePath(PendingMessageOperation operation, String fileName) {
    return '${operation.chatId}/${_remote.currentUserId}/'
        '${operation.id}/$fileName';
  }

  String _attachmentId(String messageId, int position) {
    return _uuid.v5(Namespace.url.value, '$messageId:$position');
  }
}
