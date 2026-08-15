import 'package:equatable/equatable.dart';

enum MessageStatus { sending, sent, read, error }

enum MessageType { text, image, location, audio }

class ChatMessage extends Equatable {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isMine;
  final MessageStatus status;
  final MessageType type;
  final List<String> mediaUrls;
  final double? latitude;
  final double? longitude;
  final String? audioUrl;
  final Duration? audioDuration;
  final List<double> audioWaveform;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.isMine,
    this.status = MessageStatus.sent,
    this.type = MessageType.text,
    this.mediaUrls = const [],
    this.latitude,
    this.longitude,
    this.audioUrl,
    this.audioDuration,
    this.audioWaveform = const [],
  });

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? text,
    DateTime? timestamp,
    bool? isMine,
    MessageStatus? status,
    MessageType? type,
    List<String>? mediaUrls,
    double? latitude,
    double? longitude,
    String? audioUrl,
    Duration? audioDuration,
    List<double>? audioWaveform,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isMine: isMine ?? this.isMine,
      status: status ?? this.status,
      type: type ?? this.type,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      audioUrl: audioUrl ?? this.audioUrl,
      audioDuration: audioDuration ?? this.audioDuration,
      audioWaveform: audioWaveform ?? this.audioWaveform,
    );
  }

  @override
  List<Object?> get props => [
        id,
        chatId,
        senderId,
        text,
        timestamp,
        isMine,
        status,
        type,
        mediaUrls,
        latitude,
        longitude,
        audioUrl,
        audioDuration,
        audioWaveform,
      ];
}
