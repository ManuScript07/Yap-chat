import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/chats/data/data.dart';

class ChatsRemoteDataSource {
  const ChatsRemoteDataSource({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('A signed-in user is required');
    return id;
  }

  Future<List<Chat>> fetchChats() async {
    final response = await _client.rpc<List<dynamic>>('get_chat_summaries');
    final rows = response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final avatarUrls = await _createSignedUrls(
      rows
          .map((row) => row['peer_avatar_storage_path'] as String?)
          .whereType<String>()
          .toSet(),
      bucket: 'avatars',
    );

    return rows
        .map((row) {
          final storagePath = row['peer_avatar_storage_path'] as String?;
          final lastMessageAt = row['last_message_at'] as String?;
          final lastMessageType = row['last_message_type'] as String?;
          return Chat(
            id: row['id'] as String,
            peerId: row['peer_id'] as String,
            peerUsername: row['peer_username'] as String? ?? '',
            userName: row['peer_display_name'] as String? ?? '',
            avatarUrl: storagePath == null
                ? row['peer_avatar_url'] as String?
                : avatarUrls[storagePath],
            avatarStoragePath: storagePath,
            lastMessage: row['last_message_text'] as String? ?? '',
            lastMessageType: _previewType(lastMessageType),
            lastMessageTime: lastMessageAt == null
                ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
                : DateTime.parse(lastMessageAt).toLocal(),
            unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
            isOnline: false,
            isLastMessageFromMe: row['last_message_sender_id'] == currentUserId,
            isMuted: row['is_muted'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }

  Stream<void> watchChanges() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel =
            _client
                .channel(
                  'user:$currentUserId:chats',
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

  Future<void> hideChats(Set<String> ids) => _client.rpc<void>(
    'hide_conversations',
    params: {'conversation_ids': ids.toList(growable: false)},
  );

  Future<void> markAsRead(Set<String> ids) => _client.rpc<void>(
    'mark_conversations_read',
    params: {'conversation_ids': ids.toList(growable: false)},
  );

  Future<void> toggleMute(Set<String> ids) => _client.rpc<void>(
    'toggle_conversations_mute',
    params: {'conversation_ids': ids.toList(growable: false)},
  );

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

  ChatPreviewType _previewType(String? value) {
    return switch (value) {
      'image' => ChatPreviewType.image,
      'audio' => ChatPreviewType.audio,
      'location' => ChatPreviewType.location,
      _ => ChatPreviewType.text,
    };
  }
}
