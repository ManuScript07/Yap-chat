import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/services/reconnect_backoff.dart';
import 'package:yap_chat/features/chats/data/data.dart';

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
  }) : _client = client,
       _talker = talker,
       _reconnectBackoff = ReconnectBackoff(
         onError: (error, stackTrace) =>
             talker.handle(error, stackTrace, 'Chats realtime retry failed'),
       );

  final SupabaseClient _client;
  final Talker _talker;
  final ReconnectBackoff _reconnectBackoff;
  StreamController<ConversationChange>? _changesController;
  RealtimeChannel? _changesChannel;
  Future<void> _channelOperation = Future<void>.value();
  bool _isPaused = false;

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
            isLastMessageFromMe: row['last_message_sender_id'] == currentUserId,
            isMuted: row['is_muted'] as bool? ?? false,
          );
        })
        .toList(growable: false);
  }

  Stream<ConversationChange> watchChanges() {
    return (_changesController ??=
            StreamController<ConversationChange>.broadcast(
              onListen: () =>
                  unawaited(_serializeChannelOperation(_ensureChannel)),
              onCancel: () =>
                  unawaited(_serializeChannelOperation(_removeCurrentChannel)),
            ))
        .stream;
  }

  Future<void> pauseChanges() {
    _isPaused = true;
    _reconnectBackoff.cancel();
    return _serializeChannelOperation(_removeCurrentChannel);
  }

  Future<void> resumeChanges() {
    _isPaused = false;
    _reconnectBackoff.reset();
    return _serializeChannelOperation(() async {
      await _removeCurrentChannel();
      await _ensureChannel();
    });
  }

  Future<void> _ensureChannel() async {
    if (_isPaused || _changesChannel != null) return;
    final controller = _changesController;
    if (controller == null || controller.isClosed || !controller.hasListener) {
      return;
    }
    late final RealtimeChannel channel;
    channel = _client
        .channel(
          'user:$currentUserId:chats',
          opts: const RealtimeChannelConfig(private: true),
        )
        .onBroadcast(
          event: 'changed',
          callback: (event) {
            if (!identical(_changesChannel, channel)) return;
            final nested = event['payload'];
            final payload = nested is Map
                ? Map<String, dynamic>.from(nested)
                : event;
            final reason = payload['reason'] as String? ?? 'changed';
            final conversationId = payload['conversation_id'];
            if (conversationId is String) {
              controller.add(
                ConversationChange(
                  conversationId: conversationId,
                  reason: reason,
                ),
              );
            }
            final conversationIds = payload['conversation_ids'];
            if (conversationIds is List) {
              for (final id in conversationIds.whereType<String>()) {
                controller.add(
                  ConversationChange(conversationId: id, reason: reason),
                );
              }
            }
          },
        );
    _changesChannel = channel;
    channel.subscribe((status, _) {
      if (!identical(_changesChannel, channel) || controller.isClosed) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _reconnectBackoff.reset();
          _talker.debug('Chats realtime subscribed');
          controller.add(
            const ConversationChange(
              conversationId: null,
              reason: 'subscribed',
            ),
          );
        case RealtimeSubscribeStatus.closed:
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _handleChannelFailure(channel, status);
      }
    });
  }

  void _handleChannelFailure(
    RealtimeChannel channel,
    RealtimeSubscribeStatus status,
  ) {
    if (!identical(_changesChannel, channel)) return;
    _changesChannel = null;
    _talker.warning('Chats realtime unavailable: ${status.name}');
    unawaited(
      _serializeChannelOperation(() async {
        await _removeChannel(channel);
        _scheduleReconnect();
      }),
    );
  }

  void _scheduleReconnect() {
    if (_isPaused || !(_changesController?.hasListener ?? false)) return;
    final delay = _reconnectBackoff.schedule(
      () => _serializeChannelOperation(_ensureChannel),
    );
    if (delay != null) {
      _talker.debug(
        'Chats realtime reconnect scheduled in ${delay.inSeconds}s',
      );
    }
  }

  Future<void> _removeCurrentChannel() async {
    final channel = _changesChannel;
    _changesChannel = null;
    if (channel != null) await _removeChannel(channel);
  }

  Future<void> _removeChannel(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (error, stackTrace) {
      _talker.handle(
        error,
        stackTrace,
        'Chats realtime channel removal failed',
      );
    }
  }

  Future<void> _serializeChannelOperation(Future<void> Function() action) {
    final operation = _channelOperation.then(
      (_) => action(),
      onError: (_) => action(),
    );
    _channelOperation = operation;
    return operation;
  }

  Future<void> hideChats(Set<String> ids, {required DateTime clearedAt}) =>
      _client.rpc<void>(
        'hide_conversations',
        params: {
          'conversation_ids': ids.toList(growable: false),
          'cleared_before': clearedAt.toUtc().toIso8601String(),
        },
      );

  Future<void> markAsRead(Set<String> ids) => _client.rpc<void>(
    'mark_conversations_read',
    params: {'conversation_ids': ids.toList(growable: false)},
  );

  Future<void> toggleMute(Set<String> ids) => _client.rpc<void>(
    'toggle_conversations_mute',
    params: {'conversation_ids': ids.toList(growable: false)},
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
