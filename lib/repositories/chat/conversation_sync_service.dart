import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
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
    required AccountSessionController accountSessionController,
  }) : _cache = cache,
       _remote = remote,
       _hydrator = hydrator,
       _chatsCache = chatsCache,
       _accountSessionController = accountSessionController;

  static const pageSize = 60;

  final ChatCacheDataSource _cache;
  final ChatRemoteDataSource _remote;
  final ChatMessageHydrator _hydrator;
  final ChatsCacheDataSource _chatsCache;
  final AccountSessionController _accountSessionController;
  final Map<String, Future<List<ChatMessage>>> _activeSyncs = {};
  final Map<String, int> _openConversationCounts = {};
  String? _openConversationPrefix;

  bool isConversationOpen(String chatId) {
    final scope = _accountSessionController.capture();
    if (_openConversationPrefix != _operationKey(scope, '')) return false;
    return (_openConversationCounts[_operationKey(scope, chatId)] ?? 0) > 0;
  }

  Set<String> get openConversationIds {
    final scope = _accountSessionController.capture();
    final prefix = _operationKey(scope, '');
    if (_openConversationPrefix != prefix) return const <String>{};
    return Set<String>.unmodifiable(
      _openConversationCounts.keys
          .where((key) => key.startsWith(prefix))
          .map((key) => key.substring(prefix.length)),
    );
  }

  void openConversation(String chatId, {AccountSessionSnapshot? session}) {
    final scope = session ?? _accountSessionController.capture();
    final prefix = _operationKey(scope, '');
    if (_openConversationPrefix != prefix) {
      _openConversationCounts.clear();
      _openConversationPrefix = prefix;
    }
    final key = _operationKey(scope, chatId);
    _openConversationCounts.update(
      key,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void closeConversation(String chatId, {AccountSessionSnapshot? session}) {
    final scope = session;
    if (scope == null) return;
    if (_openConversationPrefix != _operationKey(scope, '')) return;
    final key = _operationKey(scope, chatId);
    final count = _openConversationCounts[key] ?? 0;
    if (count <= 1) {
      _openConversationCounts.remove(key);
    } else {
      _openConversationCounts[key] = count - 1;
    }
  }

  Future<List<ChatMessage>> synchronizeRecent(
    String chatId, {
    bool refreshAfterActive = false,
  }) async {
    final scope = _accountSessionController.capture();
    final operationKey = _operationKey(scope, chatId);
    final active = _activeSyncs[operationKey];
    if (active != null) {
      final messages = await active;
      if (!refreshAfterActive) return messages;

      final newerSync = _activeSyncs[operationKey];
      if (newerSync != null && !identical(newerSync, active)) {
        return newerSync;
      }
    }

    final sync = _performSync(chatId, scope);
    _activeSyncs[operationKey] = sync;
    return sync.whenComplete(() {
      if (identical(_activeSyncs[operationKey], sync)) {
        _activeSyncs.remove(operationKey);
      }
    });
  }

  Future<List<ChatMessage>> hydrateAll(
    List<ChatMessage> messages, {
    String? ownerUserId,
  }) {
    return _hydrator.hydrateAll(messages, ownerUserId: ownerUserId);
  }

  Future<void> reflectLocalMessage(ChatMessage message, {String? ownerUserId}) {
    return _chatsCache.updateLastMessage(message, ownerUserId: ownerUserId);
  }

  Future<void> refreshLocalPreview(String chatId, {String? ownerUserId}) async {
    final owner = ownerUserId ?? _remote.currentUserId;
    final messages = await _cache.readMessages(chatId, currentUserId: owner);
    final latest = messages.firstOrNull;
    if (latest != null) {
      await _chatsCache.updateLastMessage(latest, ownerUserId: owner);
    }
  }

  Future<List<ChatMessage>> _performSync(
    String chatId,
    AccountSessionSnapshot scope,
  ) async {
    final messages = await _remote.fetchMessages(chatId, pageSize: pageSize);
    _accountSessionController.ensureCurrent(scope);
    final hydrated = await _hydrator.hydrateAll(
      messages,
      ownerUserId: scope.userId,
    );
    await _accountSessionController.commit(scope, () async {
      await _cache.replaceRecentMessages(
        chatId,
        hydrated,
        ownerUserId: scope.userId,
      );
      await refreshLocalPreview(chatId, ownerUserId: scope.userId);
    });
    return hydrated;
  }

  void resetForAccountChange() {
    _activeSyncs.clear();
    _openConversationCounts.clear();
    _openConversationPrefix = null;
  }

  String _operationKey(AccountSessionSnapshot scope, String chatId) =>
      '${scope.generation}\u0000${scope.userId}\u0000$chatId';
}
