import 'dart:async';
import 'dart:io';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_chat_repository.dart';

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
        readAt: now.subtract(const Duration(minutes: 12)),
      ),
      ChatMessage(
        id: 'reply-1',
        chatId: '1',
        senderId: 'other',
        text: 'Да, давай покажем результат на следующей встрече.',
        timestamp: now.subtract(const Duration(minutes: 20)),
        isMine: false,
        status: MessageStatus.read,
        replyTo: const MessageReply(
          messageId: '2',
          senderId: 'me',
          isMine: true,
          type: MessageType.text,
          text: 'Привет! Все отлично, скоро закончим верстку.',
        ),
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
        readAt: DateTime(now.year, 6, 5, 14, 24),
      ),
      ChatMessage(
        id: '6',
        chatId: '1',
        senderId: 'me',
        text: 'Сохранил основные договоренности по проекту.',
        timestamp: DateTime(now.year - 1, 5, 27, 17, 40),
        isMine: true,
        status: MessageStatus.read,
        readAt: DateTime(now.year - 1, 5, 27, 17, 45),
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
  Future<bool> loadMoreMessages(String chatId) async => false;

  @override
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToMessageId,
  }) async {
    final newMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      chatId: chatId,
      senderId: 'me',
      text: text,
      timestamp: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      replyTo: _createReply(replyToMessageId),
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
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        status: MessageStatus.read,
        readAt: DateTime.now(),
      );
      _messagesController.add(List.unmodifiable(_messages));
    }
    _messages.insert(0, responseMessage);
    _messagesController.add(List.unmodifiable(_messages));
  }

  @override
  Future<void> sendImages(
    String chatId,
    List<String> imagePaths, {
    String? replyToMessageId,
  }) async {
    final newMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      chatId: chatId,
      senderId: 'me',
      text: '',
      timestamp: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      type: MessageType.image,
      mediaUrls: imagePaths,
      replyTo: _createReply(replyToMessageId),
    );

    _messages.insert(0, newMessage);
    _messagesController.add(List.unmodifiable(_messages));

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    final index = _messages.indexWhere((m) => m.id == newMessage.id);
    if (index != -1) {
      final hasMissingFile = imagePaths.any(
        (path) => !path.startsWith('http') && !File(path).existsSync(),
      );
      _messages[index] = _messages[index].copyWith(
        status: hasMissingFile ? MessageStatus.error : MessageStatus.sent,
      );
      _messagesController.add(List.unmodifiable(_messages));
    }
  }

  @override
  Future<void> sendAudio(
    String chatId,
    String audioPath,
    Duration duration,
    List<double> waveform, {
    String? replyToMessageId,
  }) async {
    final newMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      chatId: chatId,
      senderId: 'me',
      text: '',
      timestamp: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      type: MessageType.audio,
      audioUrl: audioPath,
      audioDuration: duration,
      audioWaveform: waveform,
      replyTo: _createReply(replyToMessageId),
    );

    _messages.insert(0, newMessage);
    _messagesController.add(List.unmodifiable(_messages));

    await Future<void>.delayed(const Duration(seconds: 1));
    final index = _messages.indexWhere(
      (message) => message.id == newMessage.id,
    );
    if (index == -1) return;

    _messages[index] = _messages[index].copyWith(status: MessageStatus.sent);
    _messagesController.add(List.unmodifiable(_messages));
  }

  @override
  Future<void> retryImages(String chatId, ChatMessage message) async {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;

    _messages[index] = message.copyWith(status: MessageStatus.sending);
    _messagesController.add(List.unmodifiable(_messages));

    await Future<void>.delayed(const Duration(seconds: 1));

    final hasMissingFile = message.mediaUrls.any(
      (path) => !path.startsWith('http') && !File(path).existsSync(),
    );
    _messages[index] = _messages[index].copyWith(
      status: hasMissingFile ? MessageStatus.error : MessageStatus.sent,
    );
    _messagesController.add(List.unmodifiable(_messages));
  }

  @override
  Future<void> sendLocation(
    String chatId,
    double latitude,
    double longitude, {
    String? replyToMessageId,
  }) async {
    final message = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      chatId: chatId,
      senderId: 'me',
      text: '',
      timestamp: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      type: MessageType.location,
      latitude: latitude,
      longitude: longitude,
      replyTo: _createReply(replyToMessageId),
    );

    _messages.insert(0, message);
    _messagesController.add(List.unmodifiable(_messages));
    await Future<void>.delayed(const Duration(seconds: 1));

    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;
    _messages[index] = _messages[index].copyWith(status: MessageStatus.sent);
    _messagesController.add(List.unmodifiable(_messages));
  }

  @override
  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required bool deleteForEveryone,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _messages.removeWhere((message) => message.id == messageId);
    _messagesController.add(List.unmodifiable(_messages));
  }

  @override
  Future<void> synchronizeOpenChats() async {}

  @override
  Future<void> pauseNetwork() async {}

  MessageReply? _createReply(String? messageId) {
    if (messageId == null) return null;

    final messageIndex = _messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex == -1) return null;
    return MessageReply.fromMessage(_messages[messageIndex]);
  }
}
