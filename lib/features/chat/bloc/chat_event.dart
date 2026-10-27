import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class ChatStarted extends ChatEvent {
  final String chatId;
  const ChatStarted(this.chatId);

  @override
  List<Object?> get props => [chatId];
}

class ChatDraftResolved extends ChatEvent {
  const ChatDraftResolved({required this.peerId, required this.chat});

  final String peerId;
  final Chat chat;

  @override
  List<Object?> get props => [peerId, chat];
}

sealed class ChatOutgoingEvent extends ChatEvent {
  const ChatOutgoingEvent();
}

/// UI awaits local acceptance before releasing its prepared content. Remote
/// delivery remains owned by the existing durable outbox.
class ChatSendRequested extends ChatEvent {
  ChatSendRequested(this.message);

  final ChatOutgoingEvent message;
  final completion = Completer<bool>();

  @override
  List<Object?> get props => [message, completion];
}

class ChatMessageSent extends ChatOutgoingEvent {
  final String text;
  const ChatMessageSent(this.text);

  @override
  List<Object?> get props => [text];
}

class ChatMessageImagesSent extends ChatOutgoingEvent {
  final List<String> imagePaths;
  const ChatMessageImagesSent(this.imagePaths);

  @override
  List<Object?> get props => [imagePaths];
}

class ChatMessageAudioSent extends ChatOutgoingEvent {
  const ChatMessageAudioSent({
    required this.audioPath,
    required this.duration,
    required this.waveform,
  });

  final String audioPath;
  final Duration duration;
  final List<double> waveform;

  @override
  List<Object?> get props => [audioPath, duration, waveform];
}

class ChatMessageRetryRequested extends ChatEvent {
  const ChatMessageRetryRequested(this.message);

  final ChatMessage message;

  @override
  List<Object?> get props => [message];
}

class ChatLocationSent extends ChatOutgoingEvent {
  const ChatLocationSent({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  List<Object?> get props => [latitude, longitude];
}

class ChatMessagesReceived extends ChatEvent {
  final List<ChatMessage> messages;
  const ChatMessagesReceived(this.messages);

  @override
  List<Object?> get props => [messages];
}

class ChatOlderMessagesRequested extends ChatEvent {
  const ChatOlderMessagesRequested();
}

class ChatReplySelected extends ChatEvent {
  const ChatReplySelected(this.message);

  final ChatMessage message;

  @override
  List<Object?> get props => [message];
}

class ChatReplyCleared extends ChatEvent {
  const ChatReplyCleared();
}

class ChatMessageDeleteRequested extends ChatEvent {
  const ChatMessageDeleteRequested(this.message);

  final ChatMessage message;

  @override
  List<Object?> get props => [message];
}
