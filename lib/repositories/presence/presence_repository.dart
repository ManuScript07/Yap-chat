import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/services/reconnect_backoff.dart';
import 'package:yap_chat/repositories/presence/abstract_presence_repository.dart';

class PresenceRepository implements IPresenceRepository {
  PresenceRepository({required SupabaseClient client, required Talker talker})
    : _client = client,
      _talker = talker,
      _reconnectBackoff = ReconnectBackoff(
        onError: (error, stackTrace) =>
            talker.handle(error, stackTrace, 'Presence retry failed'),
      );

  static const _healthCheckInterval = Duration(seconds: 30);

  final SupabaseClient _client;
  final Talker _talker;
  final ReconnectBackoff _reconnectBackoff;
  final _controller = StreamController<Set<String>>.broadcast();
  RealtimeChannel? _channel;
  String? _connectedUserId;
  Future<void> _operation = Future<void>.value();
  Timer? _healthCheckTimer;
  bool _shouldBeConnected = false;
  bool _isSubscribed = false;

  @override
  Stream<Set<String>> watchOnlineUserIds() => _controller.stream;

  @override
  Future<void> connect(String userId) {
    _shouldBeConnected = true;
    return _serialize(() => _connect(userId));
  }

  Future<void> _connect(String userId) async {
    if (!_shouldBeConnected) return;
    if (_connectedUserId == userId && _channel != null && _isSubscribed) {
      return;
    }
    await _removeCurrentChannel(clearDesiredUser: false);
    _connectedUserId = userId;
    late final RealtimeChannel channel;
    channel = _client
        .channel(
          'online',
          opts: RealtimeChannelConfig(
            private: true,
            enabled: true,
            key: userId,
          ),
        )
        .onPresenceSync((_) => _emitPresence(channel));
    _channel = channel;
    channel.subscribe((status, _) {
      if (!identical(_channel, channel)) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _isSubscribed = true;
          _reconnectBackoff.reset();
          _startHealthChecks(channel, userId);
          _talker.debug('Presence realtime subscribed');
          unawaited(_trackAndValidate(channel, userId));
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          _handleChannelFailure(channel, userId, status);
      }
    });
  }

  Future<void> _trackAndValidate(RealtimeChannel channel, String userId) async {
    if (!identical(_channel, channel) || !_shouldBeConnected) return;
    try {
      final response = await channel.track({
        'user_id': userId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (response != ChannelResponse.ok) {
        _handleChannelFailure(
          channel,
          userId,
          response == ChannelResponse.timedOut
              ? RealtimeSubscribeStatus.timedOut
              : RealtimeSubscribeStatus.channelError,
        );
        return;
      }
      unawaited(_touchLastSeen());
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Presence tracking failed');
      _handleChannelFailure(
        channel,
        userId,
        RealtimeSubscribeStatus.channelError,
      );
    }
  }

  Future<void> _touchLastSeen() async {
    try {
      await _client.rpc<void>('touch_last_seen');
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Last seen update failed');
    }
  }

  void _emitPresence(RealtimeChannel channel) {
    if (!identical(_channel, channel)) return;
    _controller.add(
      Set.unmodifiable(channel.presenceState().map((state) => state.key)),
    );
  }

  @override
  Future<void> disconnect() {
    _shouldBeConnected = false;
    _reconnectBackoff.cancel();
    return _serialize(() => _removeCurrentChannel(clearDesiredUser: true));
  }

  void _handleChannelFailure(
    RealtimeChannel channel,
    String userId,
    RealtimeSubscribeStatus status,
  ) {
    if (!identical(_channel, channel)) return;
    _channel = null;
    _isSubscribed = false;
    _stopHealthChecks();
    _controller.add(const {});
    _talker.warning('Presence realtime unavailable: ${status.name}');
    unawaited(
      _serialize(() async {
        await _removeChannel(channel, untrack: false);
        _scheduleReconnect(userId);
      }),
    );
  }

  void _scheduleReconnect(String userId) {
    if (!_shouldBeConnected || _connectedUserId != userId) return;
    final delay = _reconnectBackoff.schedule(
      () => _serialize(() => _connect(userId)),
    );
    if (delay != null) {
      _talker.debug(
        'Presence realtime reconnect scheduled in ${delay.inSeconds}s',
      );
    }
  }

  void _startHealthChecks(RealtimeChannel channel, String userId) {
    _stopHealthChecks();
    _healthCheckTimer = Timer.periodic(
      _healthCheckInterval,
      (_) => unawaited(_trackAndValidate(channel, userId)),
    );
  }

  void _stopHealthChecks() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> _removeCurrentChannel({required bool clearDesiredUser}) async {
    final channel = _channel;
    _channel = null;
    _isSubscribed = false;
    _stopHealthChecks();
    if (clearDesiredUser) _connectedUserId = null;
    if (channel != null) await _removeChannel(channel, untrack: true);
    _controller.add(const {});
  }

  Future<void> _removeChannel(
    RealtimeChannel channel, {
    required bool untrack,
  }) async {
    if (untrack) {
      await _touchLastSeen();
      try {
        await channel.untrack();
      } catch (_) {}
    }
    try {
      await _client.removeChannel(channel);
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Presence channel removal failed');
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _operation.then(
      (_) => action(),
      onError: (_) => action(),
    );
    _operation = operation;
    return operation;
  }
}
