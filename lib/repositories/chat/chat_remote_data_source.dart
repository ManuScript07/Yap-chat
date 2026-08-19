import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/chat/data/data.dart';

class ChatRemoteDataSource {
  const ChatRemoteDataSource({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('A signed-in user is required');
    return id;
  }

  Future<List<ChatMessage>> fetchMessages(
    String chatId, {
    DateTime? beforeTimestamp,
    String? beforeMessageId,
    int pageSize = 60,
  }) async {
    final response = await _client.rpc<List<dynamic>>(
      'get_conversation_messages',
      params: {
        'target_conversation_id': chatId,
        'before_created_at': beforeTimestamp?.toUtc().toIso8601String(),
        'before_message_id': beforeMessageId,
        'page_size': pageSize,
      },
    );
    final rows = response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final imagePaths = <String>{};
    final audioPaths = <String>{};
    for (final row in rows) {
      for (final attachment in _attachments(row)) {
        final path = attachment['storage_path'] as String?;
        if (path == null) continue;
        if (attachment['kind'] == 'image') {
          imagePaths.add(path);
        } else if (attachment['kind'] == 'audio') {
          audioPaths.add(path);
        }
      }
    }
    final signedUrls = {
      ...await _createSignedUrls(imagePaths, bucket: 'chat-images'),
      ...await _createSignedUrls(audioPaths, bucket: 'chat-audio'),
    };
    return rows
        .map((row) => _mapMessage(row, signedUrls))
        .toList(growable: false);
  }

  Stream<void> watchChanges(String chatId) {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel =
            _client
                .channel(
                  'chat:$chatId',
                  opts: const RealtimeChannelConfig(private: true),
                )
                .onBroadcast(
                  event: 'changed',
                  callback: (_) => controller.add(null),
                )
              ..subscribe();
      },
      onCancel: () async {
        final activeChannel = channel;
        if (activeChannel != null) await _client.removeChannel(activeChannel);
      },
    );
    return controller.stream;
  }

  Future<void> upload({
    required String bucket,
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              cacheControl: '31536000',
            ),
          );
    } on StorageException catch (error) {
      final isAlreadyUploaded =
          error.statusCode == '409' ||
          error.message.toLowerCase().contains('duplicate');
      if (!isAlreadyUploaded) rethrow;
    }
  }

  Future<void> sendMessage({
    required String id,
    required String chatId,
    required MessageType type,
    String text = '',
    double? latitude,
    double? longitude,
    String? replyToMessageId,
    List<Map<String, dynamic>> attachments = const [],
  }) {
    return _client.rpc<void>(
      'send_chat_message',
      params: {
        'message_id': id,
        'target_conversation_id': chatId,
        'message_type': type.name,
        'message_text': text,
        'message_latitude': latitude,
        'message_longitude': longitude,
        'reply_message_id': replyToMessageId,
        'message_attachments': attachments,
      },
    );
  }

  Future<void> markAsRead(String chatId) => _client.rpc<void>(
    'mark_conversations_read',
    params: {
      'conversation_ids': [chatId],
    },
  );

  Future<void> deleteMessage(
    String messageId, {
    required bool deleteForEveryone,
  }) => _client.rpc<void>(
    'soft_delete_message',
    params: {
      'target_message_id': messageId,
      'delete_for_everyone': deleteForEveryone,
    },
  );

  List<Map<String, dynamic>> _attachments(Map<String, dynamic> row) {
    final value = row['attachments'];
    if (value is! List) return const [];
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  ChatMessage _mapMessage(
    Map<String, dynamic> row,
    Map<String, String> signedUrls,
  ) {
    final attachments = _attachments(row);
    final imageAttachments = attachments
        .where((item) => item['kind'] == 'image')
        .toList(growable: false);
    final audioAttachment = attachments
        .where((item) => item['kind'] == 'audio')
        .firstOrNull;
    final senderId = row['sender_id'] as String;
    final isMine = senderId == currentUserId;
    final readAtValue = row['read_at'] as String?;
    final replyId = row['reply_to_message_id'] as String?;
    final replyType = row['reply_type'] as String?;
    return ChatMessage(
      id: row['id'] as String,
      chatId: row['conversation_id'] as String,
      senderId: senderId,
      text: row['text'] as String? ?? '',
      timestamp: DateTime.parse(row['created_at'] as String).toLocal(),
      isMine: isMine,
      status: isMine && readAtValue != null
          ? MessageStatus.read
          : MessageStatus.sent,
      type: MessageType.values.byName(row['type'] as String),
      mediaUrls: imageAttachments
          .map((item) => signedUrls[item['storage_path']] ?? '')
          .where((url) => url.isNotEmpty)
          .toList(growable: false),
      mediaStoragePaths: imageAttachments
          .map((item) => item['storage_path'] as String)
          .toList(growable: false),
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      audioUrl: audioAttachment == null
          ? null
          : signedUrls[audioAttachment['storage_path']],
      audioStoragePath: audioAttachment?['storage_path'] as String?,
      audioDuration: audioAttachment?['duration_ms'] == null
          ? null
          : Duration(
              milliseconds: (audioAttachment!['duration_ms'] as num).toInt(),
            ),
      audioWaveform: (audioAttachment?['waveform'] as List? ?? const [])
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
      replyTo: replyId == null || replyType == null
          ? null
          : MessageReply(
              messageId: replyId,
              senderId: row['reply_sender_id'] as String? ?? '',
              isMine: row['reply_sender_id'] == currentUserId,
              type: MessageType.values.byName(replyType),
              text: row['reply_text'] as String? ?? '',
            ),
      readAt: readAtValue == null
          ? null
          : DateTime.parse(readAtValue).toLocal(),
    );
  }

  Future<Map<String, String>> _createSignedUrls(
    Set<String> paths, {
    required String bucket,
  }) async {
    if (paths.isEmpty) return const {};
    final results = await _client.storage
        .from(bucket)
        .createSignedUrlsResult(paths.toList(growable: false), 60 * 60 * 24);
    return {
      for (final result in results)
        if (result case SignedUrlSuccess(:final path, :final signedUrl))
          path: signedUrl,
    };
  }
}
