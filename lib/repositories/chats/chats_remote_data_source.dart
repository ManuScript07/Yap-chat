import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/services/app_diagnostics.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/presence/presence_status_store.dart';
import 'package:yap_chat/repositories/realtime/user_realtime_data_source.dart';

class ConversationChange {
  const ConversationChange({
    required this.conversationId,
    required this.reason,
  });

  final String? conversationId;
  final String reason;
}

class ChatsRemoteDataSource {
  ChatsRemoteDataSource({
    required SupabaseClient client,
    required Talker talker,
    UserRealtimeDataSource? userRealtime,
    PresenceStatusStore? presenceStore,
    AppDiagnostics? diagnostics,
  }) : _client = client,
       _userRealtime =
           userRealtime ??
           UserRealtimeDataSource(client: client, talker: talker),
       _presenceStore = presenceStore,
       _diagnostics = diagnostics;

  final SupabaseClient _client;
  final UserRealtimeDataSource _userRealtime;
  final PresenceStatusStore? _presenceStore;
  final AppDiagnostics? _diagnostics;

  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('A signed-in user is required');
    return id;
  }

  Future<List<Chat>> fetchChats() async {
    final response = await measureRpc(
      _diagnostics,
      'get_chat_summaries',
      () => _client.rpc<List<dynamic>>('get_chat_summaries'),
    );
    final rows = response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    _presenceStore?.recordAll({
      for (final row in rows)
        if (row['peer_id'] is String && row['peer_is_online'] is bool)
          row['peer_id'] as String: row['peer_is_online'] as bool,
    });
    return rows
        .map((row) {
          final storagePath = row['peer_avatar_storage_path'] as String?;
          final lastMessageAt = row['last_message_at'] as String?;
          final lastMessageType = row['last_message_type'] as String?;
          final lastSeenAt = row['peer_last_seen_at'] as String?;
          final showsLastSeen = row['peer_shows_last_seen'] as bool? ?? true;
          return Chat(
            id: row['id'] as String,
            peerId: row['peer_id'] as String,
            peerUsername: row['peer_username'] as String? ?? '',
            userName: row['peer_display_name'] as String? ?? '',
            avatarUrl: storagePath == null
                ? row['peer_avatar_url'] as String?
                : null,
            avatarStoragePath: storagePath,
            lastMessageId: row['last_message_id'] as String?,
            lastMessage: row['last_message_text'] as String? ?? '',
            lastMessageType: _previewType(lastMessageType),
            lastMessageTime: lastMessageAt == null
                ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
                : DateTime.parse(lastMessageAt).toLocal(),
            unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
            isOnline: false,
            lastSeenAt: lastSeenAt == null
                ? null
                : DateTime.parse(lastSeenAt).toLocal(),
            showsLastSeen: showsLastSeen,
            isLastMessageFromMe: row['last_message_sender_id'] == currentUserId,
            isMuted: row['is_muted'] as bool? ?? false,
            blockedByMe: row['blocked_by_me'] as bool? ?? false,
            blockedByPeer: row['blocked_by_peer'] as bool? ?? false,
            peerIsGloballyBanned:
                row['peer_is_globally_banned'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }

  Stream<ConversationChange> watchChanges() {
    return _userRealtime.watchConversationEvents().map(
      (event) => ConversationChange(
        conversationId: event.conversationId,
        reason: event.reason,
      ),
    );
  }

  Future<void> pauseChanges() => _userRealtime.pause();

  Future<void> resumeChanges() => _userRealtime.resume();

  Future<void> hideChats(Set<String> ids, {required DateTime clearedAt}) =>
      measureRpc(
        _diagnostics,
        'hide_conversations',
        () => _client.rpc<void>(
          'hide_conversations',
          params: {
            'conversation_ids': ids.toList(growable: false),
            'cleared_before': clearedAt.toUtc().toIso8601String(),
          },
        ),
      );

  Future<void> markAsRead(Set<String> ids) => measureRpc(
    _diagnostics,
    'mark_conversations_read',
    () => _client.rpc<void>(
      'mark_conversations_read',
      params: {'conversation_ids': ids.toList(growable: false)},
    ),
  );

  Future<void> toggleMute(Set<String> ids) => measureRpc(
    _diagnostics,
    'toggle_conversations_mute',
    () => _client.rpc<void>(
      'toggle_conversations_mute',
      params: {'conversation_ids': ids.toList(growable: false)},
    ),
  );

  Future<String> createDirectConversation(String peerId) => measureRpc(
    _diagnostics,
    'create_direct_conversation',
    () => _client.rpc<String>(
      'create_direct_conversation',
      params: {'peer_user_id': peerId},
    ),
  );

  ChatPreviewType _previewType(String? value) {
    return switch (value) {
      'image' => ChatPreviewType.image,
      'audio' => ChatPreviewType.audio,
      'location' => ChatPreviewType.location,
      _ => ChatPreviewType.text,
    };
  }
}
