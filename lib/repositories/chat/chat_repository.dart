import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/core/services/chat_media_processor.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_chat_repository.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/conversation_sync_service.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/abstract_local_media_repository.dart';

class ChatRepository implements IChatRepository {
  ChatRepository({
    required AppConfig config,
    required ChatCacheDataSource cache,
    required ChatRemoteDataSource remote,
    required ChatMediaProcessor mediaProcessor,
    required MediaCacheService mediaCache,
    required ConversationSyncService syncService,
    required ChatsCacheDataSource chatsCache,
    required ILocalMediaRepository localMediaRepository,
    required AccountSessionController accountSessionController,
    Uuid uuid = const Uuid(),
  }) : _config = config,
       _cache = cache,
       _remote = remote,
       _mediaProcessor = mediaProcessor,
       _mediaCache = mediaCache,
       _syncService = syncService,
       _chatsCache = chatsCache,
       _localMediaRepository = localMediaRepository,
       _accountSessionController = accountSessionController,
       _uuid = uuid;

  static const _retryInterval = Duration(seconds: 20);

  final AppConfig _config;
  final ChatCacheDataSource _cache;
  final ChatRemoteDataSource _remote;
  final ChatMediaProcessor _mediaProcessor;
  final MediaCacheService _mediaCache;
  final ConversationSyncService _syncService;
  final ChatsCacheDataSource _chatsCache;
  final ILocalMediaRepository _localMediaRepository;
  final AccountSessionController _accountSessionController;
  final Uuid _uuid;
  final Set<String> _deliveringOperationIds = {};
  bool _isNetworkPaused = false;

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    late final StreamController<List<ChatMessage>> controller;
    StreamSubscription<List<ChatMessage>>? cacheSubscription;
    Timer? retryTimer;
    AccountSessionSnapshot? streamScope;

    controller = StreamController<List<ChatMessage>>(
      onListen: () {
        final scope = _accountSessionController.capture();
        streamScope = scope;
        _syncService.openConversation(chatId, session: scope);
        cacheSubscription = _cache
            .watchMessages(chatId, currentUserId: scope.userId)
            .listen(controller.add, onError: controller.addError);
        retryTimer = Timer.periodic(_retryInterval, (_) {
          if (!_isNetworkPaused) unawaited(_retryPending(chatId, scope));
        });
        unawaited(_initializeChat(chatId, scope));
      },
      onCancel: () async {
        _syncService.closeConversation(chatId, session: streamScope);
        retryTimer?.cancel();
        await cacheSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> _initializeChat(
    String chatId,
    AccountSessionSnapshot scope,
  ) async {
    await _retryPending(chatId, scope);
    try {
      _accountSessionController.ensureCurrent(scope);
      final messages = await _syncService.synchronizeRecent(chatId);
      _accountSessionController.ensureCurrent(scope);
      final hasUnreadIncoming = messages.any(
        (message) => !message.isMine && message.readAt == null,
      );
      if (hasUnreadIncoming) await _remote.markAsRead(chatId);
    } catch (error, stackTrace) {
      _config.talker.handle(error, stackTrace, 'Initial chat sync failed');
    }
  }

  @override
  Future<void> synchronizeOpenChats() async {
    _isNetworkPaused = false;
    final scope = _accountSessionController.capture();
    final chatIds = _syncService.openConversationIds;
    await Future.wait(chatIds.map((chatId) => _initializeChat(chatId, scope)));
  }

  @override
  Future<void> pauseNetwork() async {
    _isNetworkPaused = true;
  }

  @override
  Future<bool> loadMoreMessages(String chatId) async {
    final scope = _accountSessionController.capture();
    final cached = await _cache.readMessages(
      chatId,
      currentUserId: scope.userId,
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
    _accountSessionController.ensureCurrent(scope);
    final hydrated = await _syncService.hydrateAll(
      page,
      ownerUserId: scope.userId,
    );
    await _accountSessionController.commit(
      scope,
      () => _cache.upsertMessages(hydrated, ownerUserId: scope.userId),
    );
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
    final scope = _accountSessionController.capture();
    final operations = await _cache.readPendingOperations(
      ownerUserId: scope.userId,
    );
    final operation = operations
        .where((item) => item.id == message.id && item.chatId == chatId)
        .firstOrNull;
    if (operation == null) return;
    await _accountSessionController.commit(
      scope,
      () => _cache.markMessageStatus(
        message.id,
        MessageStatus.sending,
        ownerUserId: scope.userId,
      ),
    );
    await _deliver(operation, scope);
  }

  @override
  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required bool deleteForEveryone,
  }) async {
    final scope = _accountSessionController.capture();
    final localMessage = await _cache.readMessage(
      messageId,
      currentUserId: scope.userId,
    );
    if (localMessage?.isLocalOnly ?? false) {
      await _accountSessionController.commit(scope, () async {
        await _cache.removeMessage(messageId, ownerUserId: scope.userId);
        await _syncService.refreshLocalPreview(
          chatId,
          ownerUserId: scope.userId,
        );
      });
      await _localMediaRepository.collectGarbage();
      return;
    }
    final pending = (await _cache.readPendingOperations(
      ownerUserId: scope.userId,
    )).where((operation) => operation.id == messageId).firstOrNull;
    if (pending != null) {
      await _accountSessionController.commit(scope, () async {
        await _cache.removePendingOperation(
          messageId,
          ownerUserId: scope.userId,
        );
        await _cache.removeMessage(messageId, ownerUserId: scope.userId);
        await _syncService.refreshLocalPreview(
          chatId,
          ownerUserId: scope.userId,
        );
      });
      await _localMediaRepository.collectGarbage();
      return;
    }
    _accountSessionController.ensureCurrent(scope);
    await _remote.deleteMessage(
      messageId,
      deleteForEveryone: deleteForEveryone,
    );
    await _accountSessionController.commit(
      scope,
      () => _cache.removeMessage(messageId, ownerUserId: scope.userId),
    );
    await _syncService.synchronizeRecent(chatId, refreshAfterActive: true);
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
    final scope = _accountSessionController.capture();
    final id = _uuid.v4();
    final localOnly = await _chatsCache.isDeliveryBlocked(
      chatId,
      ownerUserId: scope.userId,
    );
    final reply = await _createReply(replyToMessageId, scope);
    final message = ChatMessage(
      id: id,
      chatId: chatId,
      senderId: scope.userId,
      text: text,
      timestamp: DateTime.now(),
      isMine: true,
      status: localOnly ? MessageStatus.sent : MessageStatus.sending,
      type: type,
      mediaUrls: imagePaths,
      audioUrl: audioPath,
      audioDuration: audioDuration,
      audioWaveform: waveform,
      latitude: latitude,
      longitude: longitude,
      replyTo: reply,
      isLocalOnly: localOnly,
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
    await _accountSessionController.commit(scope, () async {
      await _cache.upsertMessage(
        message,
        isPending: !localOnly,
        ownerUserId: scope.userId,
      );
      await _syncService.reflectLocalMessage(
        message,
        ownerUserId: scope.userId,
      );
      if (!localOnly) {
        await _cache.putPendingOperation(operation, ownerUserId: scope.userId);
      }
    });
    if (!localOnly) await _deliver(operation, scope);
  }

  Future<MessageReply?> _createReply(
    String? messageId,
    AccountSessionSnapshot scope,
  ) async {
    if (messageId == null) return null;
    final message = await _cache.readMessage(
      messageId,
      currentUserId: scope.userId,
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

  Future<void> _retryPending(
    String chatId,
    AccountSessionSnapshot scope,
  ) async {
    _accountSessionController.ensureCurrent(scope);
    final operations = await _cache.readPendingOperations(
      ownerUserId: scope.userId,
    );
    for (final operation in operations.where((item) => item.chatId == chatId)) {
      await _deliver(operation, scope);
    }
  }

  Future<void> _deliver(
    PendingMessageOperation operation,
    AccountSessionSnapshot scope,
  ) async {
    if (await _chatsCache.isDeliveryBlocked(
      operation.chatId,
      ownerUserId: scope.userId,
    )) {
      await _makeLocalOnly(operation, scope);
      return;
    }
    final deliveryKey = '${scope.generation}:${scope.userId}:${operation.id}';
    if (!_deliveringOperationIds.add(deliveryKey)) return;
    try {
      _accountSessionController.ensureCurrent(scope);
      final type = MessageType.values.byName(operation.type);
      final payload = operation.payload;
      final attachments = switch (type) {
        MessageType.image => await _uploadImages(operation, scope),
        MessageType.audio => [await _uploadAudio(operation, scope)],
        _ => const <Map<String, dynamic>>[],
      };
      _accountSessionController.ensureCurrent(scope);
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
      await _accountSessionController.commit(scope, () async {
        await _cache.markMessageStatus(
          operation.id,
          MessageStatus.sent,
          ownerUserId: scope.userId,
        );
        await _cache.removePendingOperation(
          operation.id,
          ownerUserId: scope.userId,
        );
      });
      if (type == MessageType.audio) {
        await _mediaProcessor.deletePersistentAudio(
          payload['audio_path'] as String?,
        );
      }
      await _syncService.synchronizeRecent(
        operation.chatId,
        refreshAfterActive: true,
      );
      await _localMediaRepository.collectGarbage();
    } on StaleAccountSessionException {
      return;
    } catch (error, stackTrace) {
      if (_isConversationBlockedError(error) &&
          _accountSessionController.isCurrent(scope)) {
        await _makeLocalOnly(operation, scope);
        return;
      }
      if (_accountSessionController.isCurrent(scope)) {
        await _accountSessionController.commit(scope, () async {
          if (operation.type == MessageType.image.name) {
            await _cache.markMessageStatus(
              operation.id,
              MessageStatus.error,
              ownerUserId: scope.userId,
            );
          }
          await _cache.markPendingFailure(
            operation.id,
            error,
            ownerUserId: scope.userId,
          );
        });
      }
      _config.talker.handle(error, stackTrace, 'Pending message upload failed');
    } finally {
      _deliveringOperationIds.remove(deliveryKey);
      if (_accountSessionController.isCurrent(scope)) {
        unawaited(_localMediaRepository.collectGarbage());
      }
    }
  }

  bool _isConversationBlockedError(Object error) =>
      error.toString().contains('conversation_blocked');

  Future<void> _makeLocalOnly(
    PendingMessageOperation operation,
    AccountSessionSnapshot scope,
  ) async {
    final message = await _cache.readMessage(
      operation.id,
      currentUserId: scope.userId,
    );
    if (message == null) return;
    await _accountSessionController.commit(scope, () async {
      await _cache.upsertMessage(
        message.copyWith(status: MessageStatus.sent, isLocalOnly: true),
        ownerUserId: scope.userId,
      );
      await _cache.removePendingOperation(
        operation.id,
        ownerUserId: scope.userId,
      );
      await _syncService.refreshLocalPreview(
        operation.chatId,
        ownerUserId: scope.userId,
      );
    });
  }

  Future<List<Map<String, dynamic>>> _uploadImages(
    PendingMessageOperation operation,
    AccountSessionSnapshot scope,
  ) async {
    final sourcePaths = List<String>.from(
      operation.payload['image_paths'] as List? ?? const [],
    );
    final attachments = List<Map<String, dynamic>?>.filled(
      sourcePaths.length,
      null,
    );
    const parallelUploads = 2;
    for (
      var offset = 0;
      offset < sourcePaths.length;
      offset += parallelUploads
    ) {
      final end = (offset + parallelUploads).clamp(0, sourcePaths.length);
      await Future.wait([
        for (var index = offset; index < end; index++)
          _uploadImage(
            operation,
            sourcePaths[index],
            index,
            scope,
          ).then((attachment) => attachments[index] = attachment),
      ]);
    }
    return attachments.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _uploadImage(
    PendingMessageOperation operation,
    String sourcePath,
    int index,
    AccountSessionSnapshot scope,
  ) async {
    _accountSessionController.ensureCurrent(scope);
    final storagePath = _storagePath(operation, '$index.jpg', scope.userId);
    final cachedPath = await _mediaCache.findStorageFile(
      ownerUserId: scope.userId,
      bucket: 'chat-images',
      storagePath: storagePath,
      mimeType: 'image/jpeg',
    );
    final processed = await _mediaProcessor.processImage(
      cachedPath ?? sourcePath,
    );
    if (cachedPath == null) {
      try {
        await _mediaCache.storeBytes(
          ownerUserId: scope.userId,
          bucket: 'chat-images',
          storagePath: storagePath,
          bytes: processed.bytes,
          mimeType: processed.mimeType,
        );
      } catch (error, stackTrace) {
        _config.talker.handle(
          error,
          stackTrace,
          'Prepared image caching failed',
        );
      }
    }
    await _remote.upload(
      bucket: 'chat-images',
      storagePath: storagePath,
      bytes: processed.bytes,
      contentType: processed.mimeType,
    );
    return {
      'id': _attachmentId(operation.id, index),
      'position': index,
      'kind': 'image',
      'storage_path': storagePath,
      'mime_type': processed.mimeType,
      'size_bytes': processed.bytes.lengthInBytes,
      'width': processed.width,
      'height': processed.height,
    };
  }

  Future<Map<String, dynamic>> _uploadAudio(
    PendingMessageOperation operation,
    AccountSessionSnapshot scope,
  ) async {
    _accountSessionController.ensureCurrent(scope);
    final sourcePath = operation.payload['audio_path'] as String;
    final bytes = await _mediaProcessor.readAudio(sourcePath);
    final mimeType =
        operation.payload['audio_mime_type'] as String? ?? 'audio/mp4';
    final extension = mimeType == 'audio/webm' ? 'webm' : 'm4a';
    final attachmentId = _attachmentId(operation.id, 0);
    final storagePath = _storagePath(operation, '0.$extension', scope.userId);
    await _remote.upload(
      bucket: 'chat-audio',
      storagePath: storagePath,
      bytes: bytes,
      contentType: mimeType,
    );
    try {
      await _mediaCache.storeFile(
        ownerUserId: scope.userId,
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

  String _storagePath(
    PendingMessageOperation operation,
    String fileName,
    String ownerUserId,
  ) {
    return '${operation.chatId}/$ownerUserId/'
        '${operation.id}/$fileName';
  }

  String _attachmentId(String messageId, int position) {
    return _uuid.v5(Namespace.url.value, '$messageId:$position');
  }
}
