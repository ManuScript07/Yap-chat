import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/services/reconnect_backoff.dart';
import 'package:yap_chat/features/friends/data/data.dart';

class FriendsRemoteDataSource {
  FriendsRemoteDataSource({
    required SupabaseClient client,
    required Talker talker,
  }) : _client = client,
       _talker = talker,
       _backoff = ReconnectBackoff(
         onError: (error, stackTrace) =>
             talker.handle(error, stackTrace, 'Friends realtime retry failed'),
       );

  final SupabaseClient _client;
  final Talker _talker;
  final ReconnectBackoff _backoff;
  StreamController<void>? _changesController;
  RealtimeChannel? _channel;
  Future<void> _channelOperation = Future<void>.value();
  bool _paused = false;

  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('A signed-in user is required');
    return id;
  }

  Future<List<Friend>> fetchFriends() async {
    final response = await _client.rpc<List<dynamic>>('get_friends');
    return response
        .map((item) {
          final row = Map<String, dynamic>.from(item as Map);
          final storagePath = row['avatar_storage_path'] as String?;
          return Friend(
            id: row['id'] as String,
            username: row['username'] as String? ?? '',
            displayName: row['display_name'] as String? ?? '',
            avatarUrl: storagePath == null
                ? row['avatar_url'] as String?
                : null,
            avatarStoragePath: storagePath,
            friendsSince: DateTime.parse(
              row['friends_since'] as String,
            ).toLocal(),
          );
        })
        .toList(growable: false);
  }

  Future<List<FriendRequest>> fetchRequests() async {
    final response = await _client.rpc<List<dynamic>>('get_friend_requests');
    return response
        .map((item) {
          final row = Map<String, dynamic>.from(item as Map);
          final storagePath = row['peer_avatar_storage_path'] as String?;
          return FriendRequest(
            id: row['request_id'] as String,
            peerId: row['peer_id'] as String,
            peerUsername: row['peer_username'] as String? ?? '',
            peerDisplayName: row['peer_display_name'] as String? ?? '',
            peerAvatarUrl: storagePath == null
                ? row['peer_avatar_url'] as String?
                : null,
            peerAvatarStoragePath: storagePath,
            peerFriendCount: (row['peer_friend_count'] as num?)?.toInt(),
            direction: FriendRequestDirection.values.byName(
              row['direction'] as String,
            ),
            requestedAt: DateTime.parse(
              row['requested_at'] as String,
            ).toLocal(),
          );
        })
        .toList(growable: false);
  }

  Future<List<FriendCandidate>> searchUsers(String query) async {
    final response = await _client.rpc<List<dynamic>>(
      'search_friend_candidates',
      params: {'search_query': query, 'result_limit': 50},
    );
    return response
        .map((item) {
          final row = Map<String, dynamic>.from(item as Map);
          final storagePath = row['avatar_storage_path'] as String?;
          return FriendCandidate(
            id: row['id'] as String,
            username: row['username'] as String? ?? '',
            displayName: row['display_name'] as String? ?? '',
            avatarUrl: storagePath == null
                ? row['avatar_url'] as String?
                : null,
            avatarStoragePath: storagePath,
            friendCount: (row['friend_count'] as num?)?.toInt(),
            relationship: FriendRelationship.values.byName(
              row['relationship'] as String,
            ),
          );
        })
        .toList(growable: false);
  }

  Future<String> sendRequest(String peerId) => _client.rpc<String>(
    'send_friend_request',
    params: {'peer_user_id': peerId},
  );

  Future<void> cancelRequest(String requestId) => _client.rpc<void>(
    'cancel_friend_request',
    params: {'target_request_id': requestId},
  );

  Future<void> respond(String requestId, {required bool accept}) =>
      _client.rpc<void>(
        'respond_friend_request',
        params: {'target_request_id': requestId, 'accept_request': accept},
      );

  Future<FriendLocation?> getFriendLocation(String friendId) async {
    final response = await _client.rpc<List<dynamic>>(
      'get_friend_location',
      params: {'friend_user_id': friendId},
    );
    if (response.isEmpty) return null;
    final row = Map<String, dynamic>.from(response.first as Map);
    return FriendLocation(
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }

  Stream<void> watchChanges() =>
      (_changesController ??= StreamController<void>.broadcast(
        onListen: () => unawaited(_serialize(_ensureChannel)),
        onCancel: () => unawaited(_serialize(_removeCurrentChannel)),
      )).stream;

  Future<void> pauseChanges() {
    _paused = true;
    _backoff.cancel();
    return _serialize(_removeCurrentChannel);
  }

  Future<void> resumeChanges() {
    _paused = false;
    _backoff.reset();
    return _serialize(() async {
      await _removeCurrentChannel();
      await _ensureChannel();
    });
  }

  Future<void> _ensureChannel() async {
    if (_paused || _channel != null) return;
    final controller = _changesController;
    if (controller == null || controller.isClosed || !controller.hasListener) {
      return;
    }
    late final RealtimeChannel channel;
    channel = _client
        .channel(
          'user:$currentUserId:friends',
          opts: const RealtimeChannelConfig(private: true),
        )
        .onBroadcast(
          event: 'changed',
          callback: (_) {
            if (identical(_channel, channel) && !controller.isClosed) {
              controller.add(null);
            }
          },
        );
    _channel = channel;
    channel.subscribe((status, _) {
      if (!identical(_channel, channel) || controller.isClosed) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _backoff.reset();
          _talker.debug('Friends realtime subscribed');
          controller.add(null);
        case RealtimeSubscribeStatus.closed:
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _handleFailure(channel, status);
      }
    });
  }

  void _handleFailure(RealtimeChannel channel, RealtimeSubscribeStatus status) {
    if (!identical(_channel, channel)) return;
    _channel = null;
    _talker.warning('Friends realtime unavailable: ${status.name}');
    unawaited(
      _serialize(() async {
        await _removeChannel(channel);
        if (!_paused && (_changesController?.hasListener ?? false)) {
          _backoff.schedule(() => _serialize(_ensureChannel));
        }
      }),
    );
  }

  Future<void> _removeCurrentChannel() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await _removeChannel(channel);
  }

  Future<void> _removeChannel(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Friends channel removal failed');
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _channelOperation.then(
      (_) => action(),
      onError: (_) => action(),
    );
    _channelOperation = operation;
    return operation;
  }
}
