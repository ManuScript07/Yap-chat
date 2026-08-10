import 'dart:async';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/repositories/abstract_chat_repository.dart';

class MockChatRepository implements IChatRepository {
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [];

  MockChatRepository() {
    final now = DateTime.now();

    _messages.addAll([
      // Сегодня
      ChatMessage(
        id: '1',
        chatId: '1',
        senderId: 'other',
        text: 'Привет! Как продвигается проект?',
        timestamp: now.subtract(const Duration(minutes: 30)),
        isMine: false,
        status: MessageStatus.read,
      ),
      ChatMessage(
        id: '2',
        chatId: '1',
        senderId: 'me',
        text: 'Привет! Все отлично, скоро закончим верстку.',
        timestamp: now.subtract(const Duration(minutes: 25)),
        isMine: true,
        status: MessageStatus.read,
      ),
      // Вчера
      ChatMessage(
        id: '3',
        chatId: '1',
        senderId: 'other',
        text: 'Скинул новые макеты в Figma, посмотри при свободной минуте.',
        timestamp: now.subtract(const Duration(days: 1, hours: 2)),
        isMine: false,
        status: MessageStatus.read,
      ),
      // Текущий год (например, 5 июня)
      ChatMessage(
        id: '4',
        chatId: '1',
        senderId: 'me',
        text: 'Договорились, завтра приступлю к задаче.',
        timestamp: DateTime(now.year, 6, 5, 14, 20),
        isMine: true,
        status: MessageStatus.read,
      ),
      // Прошлый год (24 августа 2024)
      ChatMessage(
        id: '5',
        chatId: '1',
        senderId: 'other',
        text: 'Старт проекта зафиксирован!',
        timestamp: DateTime(2024, 8, 24, 10, 0),
        isMine: false,
        status: MessageStatus.read,
      ),
    ]);

    _messagesController.add(List.unmodifiable(_messages));
  }

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) async* {
    // Yield current messages immediately upon subscription
    yield List.unmodifiable(_messages);
    // Then yield subsequent updates
    yield* _messagesController.stream;
  }

  @override
  Future<void> sendMessage(String chatId, String text) async {
    final newMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      chatId: chatId,
      senderId: 'me',
      text: text,
      timestamp: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
    );

    _messages.insert(0, newMessage);
    _messagesController.add(List.unmodifiable(_messages));

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    final index = _messages.indexWhere((m) => m.id == newMessage.id);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(status: MessageStatus.sent);
      _messagesController.add(List.unmodifiable(_messages));
    }

    // Simulate response
    await Future.delayed(const Duration(seconds: 2));
    final responseMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      chatId: chatId,
      senderId: 'other',
      text: 'Получил: "$text"',
      timestamp: DateTime.now(),
      isMine: false,
      status: MessageStatus.sent,
    );
    _messages.insert(0, responseMessage);
    _messagesController.add(List.unmodifiable(_messages));
  }
}
