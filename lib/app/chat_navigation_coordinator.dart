import 'package:flutter/widgets.dart';
import 'package:yap_chat/features/chats/data/data.dart';

class ChatNavigationCoordinator {
  ChatNavigationCoordinator({
    required Future<Chat?> Function(String chatId) loadChat,
    required Future<void> Function(Chat chat) navigateToChat,
    required bool Function(String chatId) isConversationVisible,
    required bool Function() isActive,
    required void Function(Object error, StackTrace stackTrace, String message)
    onError,
    Future<void> Function()? waitForFrame,
  }) : _loadChat = loadChat,
       _navigateToChat = navigateToChat,
       _isConversationVisible = isConversationVisible,
       _isActive = isActive,
       _onError = onError,
       _waitForFrame = waitForFrame ?? _waitForNextFrame;

  final Future<Chat?> Function(String chatId) _loadChat;
  final Future<void> Function(Chat chat) _navigateToChat;
  final bool Function(String chatId) _isConversationVisible;
  final bool Function() _isActive;
  final void Function(Object error, StackTrace stackTrace, String message)
  _onError;
  final Future<void> Function() _waitForFrame;

  Future<void> _queue = Future<void>.value();
  final Set<String> _queuedChatIds = <String>{};

  Future<void> open(Chat chat) {
    final normalizedChatId = chat.id.trim();
    if (normalizedChatId.isEmpty ||
        _isConversationVisible(normalizedChatId) ||
        !_queuedChatIds.add(normalizedChatId)) {
      return _queue;
    }

    _queue = _queue.then<void>((_) => _openQueuedChat(chat));
    return _queue;
  }

  Future<void> openById(String chatId) {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty ||
        _isConversationVisible(normalizedChatId) ||
        !_queuedChatIds.add(normalizedChatId)) {
      return _queue;
    }

    _queue = _queue.then<void>((_) => _openById(normalizedChatId));
    return _queue;
  }

  Future<void> _openQueuedChat(Chat chat) async {
    final chatId = chat.id.trim();
    try {
      await _waitForFrame();
      if (!_isActive() || _isConversationVisible(chatId)) return;

      await _navigateToChat(chat);
    } catch (error, stackTrace) {
      _onError(error, stackTrace, 'Chat navigation failed');
    } finally {
      _queuedChatIds.remove(chatId);
    }
  }

  Future<void> _openById(String chatId) async {
    try {
      await _waitForFrame();
      if (!_isActive() || _isConversationVisible(chatId)) return;

      final chat = await _loadChat(chatId);
      if (!_isActive() || _isConversationVisible(chatId)) return;
      if (chat == null) return;

      await _waitForFrame();
      if (!_isActive() || _isConversationVisible(chatId)) return;

      await _navigateToChat(chat);
    } catch (error, stackTrace) {
      _onError(error, stackTrace, 'Chat navigation failed');
    } finally {
      _queuedChatIds.remove(chatId);
    }
  }

  static Future<void> _waitForNextFrame() => WidgetsBinding.instance.endOfFrame;
}
