import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/services/reconnect_backoff.dart';

class UserConversationRealtimeEvent {
  const UserConversationRealtimeEvent({
    required this.conversationId,
    required this.reason,
  });

  final String? conversationId;
  final String reason;
}

class UserPresenceRealtimeEvent {
  const UserPresenceRealtimeEvent({
    required this.userId,
    required this.isOnline,
  });

  final String userId;
  final bool isOnline;
}

/// Owns the single private, user-addressed Realtime channel used by chat and
/// presence events. Multiple local listeners never create duplicate channels.
class UserRealtimeDataSource {
  UserRealtimeDataSource({
    required SupabaseClient client,
    required Talker talker,
  }) : _client = client,
       _talker = talker,
       _backoff = ReconnectBackoff(
         onError: (error, stackTrace) =>
             talker.handle(error, stackTrace, 'User realtime retry failed'),
       );

  final SupabaseClient _client;
  final Talker _talker;
  final ReconnectBackoff _backoff;
  final _conversationController =
      StreamController<UserConversationRealtimeEvent>.broadcast();
  final _presenceController =
      StreamController<UserPresenceRealtimeEvent>.broadcast();

  RealtimeChannel? _channel;
  String? _channelUserId;
  Future<void> _operation = Future<void>.value();
  bool _paused = false;
  bool _disposed = false;

  Stream<UserConversationRealtimeEvent> watchConversationEvents() {
    unawaited(_serialize(_ensureChannel));
    return _conversationController.stream;
  }

  Stream<UserPresenceRealtimeEvent> watchPresenceEvents() {
    unawaited(_serialize(_ensureChannel));
    return _presenceController.stream;
  }

  Future<void> pause() {
    _paused = true;
    _backoff.cancel();
    return _serialize(_removeCurrentChannel);
  }

  Future<void> resume() {
    if (_disposed) return Future.value();
    _paused = false;
    _backoff.reset();
    return _serialize(_ensureChannel);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _paused = true;
    _backoff.cancel();
    await _serialize(_removeCurrentChannel);
    await Future.wait([
      _conversationController.close(),
      _presenceController.close(),
    ]);
  }

  Future<void> _ensureChannel() async {
    if (_disposed || _paused) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    if (_channel != null && _channelUserId == userId) return;
    if (_channel != null) await _removeCurrentChannel();

    late final RealtimeChannel channel;
    channel = _client
        .channel(
          'user:$userId:chats',
          opts: const RealtimeChannelConfig(private: true),
        )
        .onBroadcast(
          event: 'changed',
          callback: (event) => _handleConversationEvent(channel, event),
        )
        .onBroadcast(
          event: 'presence_changed',
          callback: (event) => _handlePresenceEvent(channel, event),
        );
    _channel = channel;
    _channelUserId = userId;
    channel.subscribe((status, _) {
      if (!identical(_channel, channel) || _disposed) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _backoff.reset();
          _talker.debug('User realtime subscribed');
          _conversationController.add(
            const UserConversationRealtimeEvent(
              conversationId: null,
              reason: 'subscribed',
            ),
          );
        case RealtimeSubscribeStatus.closed:
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _handleFailure(channel, status);
      }
    });
  }

  void _handleConversationEvent(
    RealtimeChannel channel,
    Map<String, dynamic> event,
  ) {
    if (!identical(_channel, channel) || _conversationController.isClosed) {
      return;
    }
    final payload = _payload(event);
    final reason = payload['reason'] as String? ?? 'changed';
    final conversationId = payload['conversation_id'];
    if (conversationId is String) {
      _conversationController.add(
        UserConversationRealtimeEvent(
          conversationId: conversationId,
          reason: reason,
        ),
      );
    }
    final conversationIds = payload['conversation_ids'];
    if (conversationIds is List) {
      for (final id in conversationIds.whereType<String>()) {
        _conversationController.add(
          UserConversationRealtimeEvent(conversationId: id, reason: reason),
        );
      }
    }
  }

  void _handlePresenceEvent(
    RealtimeChannel channel,
    Map<String, dynamic> event,
  ) {
    if (!identical(_channel, channel) || _presenceController.isClosed) return;
    final payload = _payload(event);
    final userId = payload['user_id'];
    final isOnline = payload['is_online'];
    if (userId is String && isOnline is bool) {
      _presenceController.add(
        UserPresenceRealtimeEvent(userId: userId, isOnline: isOnline),
      );
    }
  }

  Map<String, dynamic> _payload(Map<String, dynamic> event) {
    final nested = event['payload'];
    return nested is Map ? Map<String, dynamic>.from(nested) : event;
  }

  void _handleFailure(RealtimeChannel channel, RealtimeSubscribeStatus status) {
    if (!identical(_channel, channel)) return;
    _channel = null;
    _channelUserId = null;
    _talker.warning('User realtime unavailable: ${status.name}');
    unawaited(
      _serialize(() async {
        await _removeChannel(channel);
        _scheduleReconnect();
      }),
    );
  }

  void _scheduleReconnect() {
    if (_paused || _disposed) return;
    final delay = _backoff.schedule(() => _serialize(_ensureChannel));
    if (delay != null) {
      _talker.debug('User realtime reconnect scheduled in ${delay.inSeconds}s');
    }
  }

  Future<void> _removeCurrentChannel() async {
    final channel = _channel;
    _channel = null;
    _channelUserId = null;
    if (channel != null) await _removeChannel(channel);
  }

  Future<void> _removeChannel(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'User realtime channel removal failed');
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _operation.then((_) => action(), onError: (_) => action());
    _operation = next;
    return next;
  }
}
