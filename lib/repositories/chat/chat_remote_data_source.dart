import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/services/app_diagnostics.dart';
import 'package:yap_chat/features/chat/data/data.dart';

class ChatRemoteDataSource {
  const ChatRemoteDataSource({
    required SupabaseClient client,
    AppDiagnostics? diagnostics,
  }) : _client = client,
       _diagnostics = diagnostics;

  final SupabaseClient _client;
  final AppDiagnostics? _diagnostics;

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
    final response = await measureRpc(
      _diagnostics,
      'get_conversation_messages',
      () => _client.rpc<List<dynamic>>(
        'get_conversation_messages',
        params: {
          'target_conversation_id': chatId,
          'before_created_at': beforeTimestamp?.toUtc().toIso8601String(),
          'before_message_id': beforeMessageId,
          'page_size': pageSize,
        },
      ),
    );
    final rows = response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    return rows.map(_mapMessage).toList(growable: false);
  }

  /// Checks cached history without downloading message bodies or media.
  /// The existing messages RLS applies the same per-user visibility rules as
  /// get_conversation_messages (including hides and conversation clearing).
  Future<Set<String>> fetchVisibleMessageIds(
    String chatId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return const <String>{};
    return (await fetchVisibleMessageStates(chatId, messageIds)).keys.toSet();
  }

  Future<Map<String, MessageReactionState>> fetchVisibleMessageStates(
    String chatId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return const {};
    final rows = await measureRpc(
      _diagnostics,
      'get_visible_conversation_message_states',
      () => _client.rpc<List<dynamic>>(
        'get_visible_conversation_message_states',
        params: {'target_conversation_id': chatId, 'message_ids': messageIds},
      ),
    );
    return {
      for (final row in rows)
        (row as Map)['id'] as String: MessageReactionState.fromJson(
          row['reaction_state'],
        ),
    };
  }

  Future<({bool applied, MessageReactionState state})> setReaction({
    required String chatId,
    required String messageId,
    required String operationId,
    required ReactionCode? code,
    required int expectedRevision,
  }) async {
    final result = await measureRpc(
      _diagnostics,
      'set_message_reaction',
      () => _client.rpc<Map<String, dynamic>>(
        'set_message_reaction',
        params: {
          'target_conversation_id': chatId,
          'target_message_id': messageId,
          'reaction_code': code?.wireName,
          'operation_id': operationId,
          'expected_user_revision': expectedRevision,
        },
      ),
    );
    return (
      applied: result['applied'] == true,
      state: MessageReactionState.fromJson(result['state']),
    );
  }

  /// The server applies the same membership, clear-boundary and hidden-message
  /// rules as get_conversation_messages. A distant window is kept out of Drift.
  Future<List<ChatMessage>> fetchMessageWindow(
    String chatId, {
    String? targetMessageId,
    DateTime? afterTimestamp,
    String? afterMessageId,
  }) async {
    final response = await measureRpc(
      _diagnostics,
      'get_conversation_message_window',
      () => _client.rpc<List<dynamic>>(
        'get_conversation_message_window',
        params: {
          'target_conversation_id': chatId,
          'target_message_id': targetMessageId,
          'after_created_at': afterTimestamp?.toUtc().toIso8601String(),
          'after_message_id': afterMessageId,
          'page_size': 60,
        },
      ),
    );
    return response
        .map((row) => _mapMessage(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
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
            retryAttempts: 2,
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
    return measureRpc(
      _diagnostics,
      'send_chat_message',
      () => _client.rpc<void>(
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
      ),
    );
  }

  Future<void> markVisibleMessagesRead(String chatId, Set<String> messageIds) =>
      measureRpc(
        _diagnostics,
        'mark_visible_conversation_messages_read',
        () => _client
            .rpc<int>(
              'mark_visible_conversation_messages_read',
              params: {
                'target_conversation_id': chatId,
                'visible_message_ids': messageIds.toList(growable: false),
              },
            )
            .then((_) {}),
      );

  Future<void> deleteMessage(
    String messageId, {
    required bool deleteForEveryone,
  }) => measureRpc(
    _diagnostics,
    'soft_delete_message',
    () => _client.rpc<void>(
      'soft_delete_message',
      params: {
        'target_message_id': messageId,
        'delete_for_everyone': deleteForEveryone,
      },
    ),
  );

  List<Map<String, dynamic>> _attachments(Map<String, dynamic> row) {
    final value = row['attachments'];
    if (value is! List) return const [];
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  ChatMessage _mapMessage(Map<String, dynamic> row) {
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
      reactionState: MessageReactionState.fromJson(row['reaction_state']),
      status: isMine && readAtValue != null
          ? MessageStatus.read
          : MessageStatus.sent,
      type: MessageType.values.byName(row['type'] as String),
      mediaUrls: const [],
      mediaStoragePaths: imageAttachments
          .map((item) => item['storage_path'] as String)
          .toList(growable: false),
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      audioUrl: null,
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
}
