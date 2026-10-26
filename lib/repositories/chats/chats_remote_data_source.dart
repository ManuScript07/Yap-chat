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

  Future<T> _readRpc<T>(String rpc, {Map<String, dynamic>? params}) async {
    final abort = Completer<void>();
    _summaryRequests.add(abort);
    try {
      return await measureRpc(
        _diagnostics,
        rpc,
        () => _client
            .rpc<T>(rpc, params: params)
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
    final response = await _readRpc<List<dynamic>>('get_chat_summaries');
    return _mapSummaries(response, presenceTicket);
  }

  Future<List<Chat>> fetchChatsByIds(Set<String> ids) async {
    if (ids.isEmpty) return const [];
    if (ids.length > summaryBatchSize || ids.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Invalid chat summary batch');
    }
    final presenceTicket = _presenceStore?.captureSnapshot();
    final response = await _readRpc<List<dynamic>>(
      'get_chat_summaries_by_ids',
      params: {'conversation_ids': ids.toList(growable: false)},
    );
    return _mapSummaries(response, presenceTicket);
  }

  /// Read an existing visible conversation only; never create/reopen one.
  Future<Chat?> fetchChatByPeerId(String peerId) async {
    final peer = peerId.trim();
    if (peer.isEmpty || peer == currentUserId) {
      throw ArgumentError('Invalid direct chat peer');
    }
    final ticket = _presenceStore?.captureSnapshot();
    final response = await _readRpc<List<dynamic>>(
      'get_direct_chat_summary',
      params: {'peer_user_id': peer},
    );
    if (response.length > 1 ||
        response.any(
          (row) =>
              row is! Map ||
              row['peer_id'] != peer ||
              row['id'] is! String ||
              (row['id'] as String).isEmpty,
        )) {
      throw const FormatException('Invalid direct chat summary');
    }
    final chats = _mapSummaries(response, ticket);
    return chats.isEmpty ? null : chats.single;
  }

  /// Prepared for the paged repository: combine metadata and the global badge
  /// in one existing-client read, never a separate background polling loop.
  Future<ChatUnreadState> fetchUnreadState({
    Set<String> conversationIds = const {},
  }) async {
    if (conversationIds.length > summaryBatchSize ||
        conversationIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Invalid unread summary selection');
    }
    final ticket = _presenceStore?.captureSnapshot();
    final response = await _readRpc<Map<String, dynamic>>(
      'get_chat_unread_state',
      params: {'conversation_ids': conversationIds.toList(growable: false)},
    );
    final total = response['unread_total'];
    final rows = response['items'];
    if (total is! int ||
        total < 0 ||
        rows is! List ||
        rows.length > conversationIds.length) {
      throw const FormatException('Invalid unread state');
    }
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          !conversationIds.contains(row['id']) ||
          !ids.add(row['id'] as String)) {
        throw const FormatException('Invalid unread summary rows');
      }
    }
    return ChatUnreadState(
      chats: _mapSummaries(rows, ticket),
      unreadTotal: total,
    );
  }

  /// Prepared for the paged repository contract; the active list does not yet
  /// treat these partial results as its complete authoritative snapshot.
  Future<ChatListPage> fetchChatListPage({
    ChatListPageCursor? after,
    int pageSize = summaryBatchSize,
    String searchQuery = '',
  }) async {
    final query = searchQuery.trim().toLowerCase();
    if (pageSize < 1 ||
        pageSize > summaryBatchSize ||
        query.runes.length > 100 ||
        after != null &&
            (after.query != query || after.conversationId.trim().isEmpty)) {
      throw ArgumentError(
        'Invalid chat page or cursor from a different search',
      );
    }
    final ticket = _presenceStore?.captureSnapshot();
    final response = await _readRpc<Map<String, dynamic>>(
      'get_chat_list_page',
      params: {
        'after_activity_at': after?.activityAt.toUtc().toIso8601String(),
        'after_conversation_id': after?.conversationId,
        'page_size': pageSize,
        'search_query': query,
      },
    );
    final rawItems = response['items'];
    final unreadTotal = response['unread_total'];
    if (response.containsKey('unread_total') &&
        (unreadTotal is! int || unreadTotal < 0)) {
      throw const FormatException('Invalid page unread total');
    }
    final more = response['has_more'];
    if (rawItems is! List ||
        rawItems.length > pageSize ||
        more is! bool ||
        response['query'] != query) {
      throw const FormatException('Invalid chat page response');
    }
    final rows = <Map<String, dynamic>>[];
    final times = <DateTime>[];
    final ids = <String>{};
    for (final value in rawItems) {
      if (value is! Map) throw const FormatException('Invalid chat page item');
      final row = Map<String, dynamic>.from(value);
      final id = row['id'];
      final activity = row['list_activity_at'];
      final time = activity is String ? DateTime.tryParse(activity) : null;
      if (id is! String || id.isEmpty || !ids.add(id) || time == null) {
        throw const FormatException('Invalid chat page identity or activity');
      }
      if (rows.isNotEmpty &&
          _comparePagePosition(
                times.last,
                rows.last['id'] as String,
                time,
                id,
              ) <=
              0) {
        throw const FormatException('Chat page is not in cursor order');
      }
      rows.add(row);
      times.add(time.toUtc());
    }
    ChatListPageCursor? next;
    final rawCursor = response['next_cursor'];
    if (more) {
      if (rawCursor is! Map ||
          rawCursor['query'] != query ||
          rawCursor['activity_at'] is! String ||
          rawCursor['conversation_id'] is! String) {
        throw const FormatException('Missing chat page cursor');
      }
      final time = DateTime.tryParse(rawCursor['activity_at'] as String);
      final id = rawCursor['conversation_id'] as String;
      if (time == null ||
          id.isEmpty ||
          after != null &&
              _comparePagePosition(
                    after.activityAt,
                    after.conversationId,
                    time,
                    id,
                  ) <=
                  0 ||
          rows.isNotEmpty &&
              _comparePagePosition(
                    times.last,
                    rows.last['id'] as String,
                    time,
                    id,
                  ) <
                  0) {
        throw const FormatException('Chat page cursor did not advance');
      }
      next = ChatListPageCursor(
        activityAt: time.toUtc(),
        conversationId: id,
        query: query,
      );
    } else if (rawCursor != null) {
      throw const FormatException('Unexpected final-page cursor');
    }
    if (after != null &&
        rows.isNotEmpty &&
        _comparePagePosition(
              after.activityAt,
              after.conversationId,
              times.first,
              rows.first['id'] as String,
            ) <=
            0) {
      throw const FormatException('Chat page crossed its cursor boundary');
    }
    final chats = _mapSummaries(rows, ticket);
    return ChatListPage(
      items: [
        for (var i = 0; i < chats.length; i++)
          ChatListPageItem(chat: chats[i], activityAt: times[i]),
      ],
      query: query,
      nextCursor: next,
      unreadTotal: unreadTotal as int?,
    );
  }

  static int _comparePagePosition(
    DateTime firstAt,
    String firstId,
    DateTime secondAt,
    String secondId,
  ) {
    final time = firstAt.compareTo(secondAt);
    return time == 0 ? firstId.compareTo(secondId) : time;
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
