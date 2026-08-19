import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/repositories/presence/abstract_presence_repository.dart';

class PresenceRepository implements IPresenceRepository {
  PresenceRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;
  final _controller = StreamController<Set<String>>.broadcast();
  RealtimeChannel? _channel;
  String? _connectedUserId;
  Future<void> _operation = Future<void>.value();

  @override
  Stream<Set<String>> watchOnlineUserIds() => _controller.stream;

  @override
  Future<void> connect(String userId) {
    return _serialize(() => _connect(userId));
  }

  Future<void> _connect(String userId) async {
    if (_connectedUserId == userId && _channel != null) return;
    await _disconnect();
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
          unawaited(_track(channel, userId));
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _controller.add(const {});
        case RealtimeSubscribeStatus.closed:
          _controller.add(const {});
          _channel = null;
          unawaited(connect(userId));
      }
    });
  }

  Future<void> _track(RealtimeChannel channel, String userId) async {
    try {
      await channel.track({
        'user_id': userId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  void _emitPresence(RealtimeChannel channel) {
    if (!identical(_channel, channel)) return;
    _controller.add(
      Set.unmodifiable(channel.presenceState().map((state) => state.key)),
    );
  }

  @override
  Future<void> disconnect() {
    return _serialize(_disconnect);
  }

  Future<void> _disconnect() async {
    final channel = _channel;
    _channel = null;
    _connectedUserId = null;
    if (channel != null) {
      try {
        await channel.untrack();
      } catch (_) {}
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
    _controller.add(const {});
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
