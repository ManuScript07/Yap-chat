import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/presence/presence.dart';
import 'package:yap_chat/repositories/realtime/realtime.dart';

class ConversationChange {
  const ConversationChange({
    required this.conversationId,
    required this.reason,
    this.messageId,
    this.reactionState,
  });

  final String? conversationId;
  final String reason;
  final String? messageId;
  final MessageReactionState? reactionState;
}

class ChatsRemoteDataSource {
  static const summaryBatchSize = 50;
  ChatsRemoteDataSource({
    required SupabaseClient client,
    required Talker talker,
    UserRealtimeDataSource? userRealtime,
    PresenceStatusStore? presenceStore,
    AppDiagnostics? diagnostics,
    this.summaryRequestTimeout = const Duration(seconds: 30),
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
  final Duration summaryRequestTimeout;
  final _summaryRequests = <Completer<void>>{};

  /// Cancels only reads owned by this source, never accepted bulk writes.
  void cancelSummaryRequests() {
    for (final request in _summaryRequests.toList(growable: false)) {
      if (!request.isCompleted) request.complete();
    }
  }

  Future<List<dynamic>> _fetchSummaries(
    String rpc, {
    Map<String, dynamic>? params,
  }) async {
    final abort = Completer<void>();
    _summaryRequests.add(abort);
    try {
      return await measureRpc(
        _diagnostics,
        rpc,
        () => _client
            .rpc<List<dynamic>>(rpc, params: params)
            .retry(enabled: false, requestTimeout: summaryRequestTimeout)
            .abortSignal(abort.future),
      );
    } finally {
      _summaryRequests.remove(abort);
    }
  }

  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('A signed-in user is required');
    return id;
  }

  Future<List<Chat>> fetchChats() async {
    final presenceTicket = _presenceStore?.captureSnapshot();
    final response = await _fetchSummaries('get_chat_summaries');
    return _mapSummaries(response, presenceTicket);
  }

  Future<List<Chat>> fetchChatsByIds(Set<String> ids) async {
    if (ids.isEmpty) return const [];
    if (ids.length > summaryBatchSize || ids.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Invalid chat summary batch');
    }
    final presenceTicket = _presenceStore?.captureSnapshot();
    final response = await _fetchSummaries(
      'get_chat_summaries_by_ids',
      params: {'conversation_ids': ids.toList(growable: false)},
    );
    return _mapSummaries(response, presenceTicket);
  }

  List<Chat> _mapSummaries(
    List<dynamic> response,
    PresenceSnapshotTicket? presenceTicket,
  ) {
    final rows = response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    _presenceStore?.applySnapshot(presenceTicket!, {
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
            peerIsDeleted: row['peer_is_deleted'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }

  Stream<ConversationChange> watchChanges() {
    return _userRealtime.watchConversationEvents().map(
      (event) => ConversationChange(
        conversationId: event.conversationId,
        reason: event.reason,
        messageId: event.messageId,
        reactionState: event.reactionState,
      ),
    );
  }

  Future<void> pauseChanges() {
    cancelSummaryRequests();
    return _userRealtime.pause();
  }

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

  Future<void> setMuted(Set<String> ids, {required bool isMuted}) => measureRpc(
    _diagnostics,
    'set_conversations_muted',
    () => _client.rpc<void>(
      'set_conversations_muted',
      params: {
        'conversation_ids': ids.toList(growable: false),
        'muted': isMuted,
      },
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
