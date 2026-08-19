import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/repositories/presence/abstract_presence_repository.dart';

class PresenceRepository implements IPresenceRepository {
  PresenceRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;
  final _controller = StreamController<Set<String>>.broadcast();
  RealtimeChannel? _channel;
  String? _connectedUserId;

  @override
  Stream<Set<String>> watchOnlineUserIds() => _controller.stream;

  @override
  Future<void> connect(String userId) async {
    if (_connectedUserId == userId && _channel != null) return;
    await disconnect();
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
      if (status == RealtimeSubscribeStatus.subscribed) {
        unawaited(
          channel.track({
            'user_id': userId,
            'online_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
    });
  }

  void _emitPresence(RealtimeChannel channel) {
    _controller.add(
      Set.unmodifiable(channel.presenceState().map((state) => state.key)),
    );
  }

  @override
  Future<void> disconnect() async {
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
}
