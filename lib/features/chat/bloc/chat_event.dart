import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chat/data/data.dart';

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

class ChatMessageSent extends ChatEvent {
  final String text;
  const ChatMessageSent(this.text);

  @override
  List<Object?> get props => [text];
}

class ChatMessageImagesSent extends ChatEvent {
  final List<String> imagePaths;
  const ChatMessageImagesSent(this.imagePaths);

  @override
  List<Object?> get props => [imagePaths];
}

class ChatMessageAudioSent extends ChatEvent {
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

class ChatLocationSent extends ChatEvent {
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
