import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat_cache_data_source.dart';
import 'package:yap_chat/repositories/chat/chat_message_hydrator.dart';
import 'package:yap_chat/repositories/chat/chat_remote_data_source.dart';
import 'package:yap_chat/repositories/chats/chats_cache_data_source.dart';

class ConversationSyncService {
  ConversationSyncService({
    required ChatCacheDataSource cache,
    required ChatRemoteDataSource remote,
    required ChatMessageHydrator hydrator,
    required ChatsCacheDataSource chatsCache,
  }) : _cache = cache,
       _remote = remote,
       _hydrator = hydrator,
       _chatsCache = chatsCache;

  static const pageSize = 60;

  final ChatCacheDataSource _cache;
  final ChatRemoteDataSource _remote;
  final ChatMessageHydrator _hydrator;
  final ChatsCacheDataSource _chatsCache;
  final Map<String, Future<List<ChatMessage>>> _activeSyncs = {};
  final Map<String, int> _openConversationCounts = {};

  bool isConversationOpen(String chatId) {
    return (_openConversationCounts[chatId] ?? 0) > 0;
  }

  void openConversation(String chatId) {
    _openConversationCounts.update(
      chatId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void closeConversation(String chatId) {
    final count = _openConversationCounts[chatId] ?? 0;
    if (count <= 1) {
      _openConversationCounts.remove(chatId);
    } else {
      _openConversationCounts[chatId] = count - 1;
    }
  }

  Future<List<ChatMessage>> synchronizeRecent(
    String chatId, {
    bool refreshAfterActive = false,
  }) async {
    final active = _activeSyncs[chatId];
    if (active != null) {
      final messages = await active;
      if (!refreshAfterActive) return messages;

      final newerSync = _activeSyncs[chatId];
      if (newerSync != null && !identical(newerSync, active)) {
        return newerSync;
      }
    }

    final sync = _performSync(chatId);
    _activeSyncs[chatId] = sync;
    return sync.whenComplete(() {
      if (identical(_activeSyncs[chatId], sync)) _activeSyncs.remove(chatId);
    });
  }

  Future<List<ChatMessage>> hydrateAll(List<ChatMessage> messages) {
    return _hydrator.hydrateAll(messages);
  }

  Future<void> reflectLocalMessage(ChatMessage message) {
    return _chatsCache.updateLastMessage(message);
  }

  Future<void> refreshLocalPreview(String chatId) async {
    final messages = await _cache.readMessages(
      chatId,
      currentUserId: _remote.currentUserId,
    );
    final latest = messages.firstOrNull;
    if (latest != null) await _chatsCache.updateLastMessage(latest);
  }

  Future<List<ChatMessage>> _performSync(String chatId) async {
    final messages = await _remote.fetchMessages(chatId, pageSize: pageSize);
    final hydrated = await _hydrator.hydrateAll(messages);
    await _cache.replaceRecentMessages(chatId, hydrated);
    await refreshLocalPreview(chatId);
    return hydrated;
  }
}
