import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/chat/data/models/message_reply.dart';

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
  final List<String> mediaStoragePaths;
  final double? latitude;
  final double? longitude;
  final String? audioUrl;
  final String? audioStoragePath;
  final Duration? audioDuration;
  final List<double> audioWaveform;
  final MessageReply? replyTo;
  final DateTime? readAt;

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
    this.mediaStoragePaths = const [],
    this.latitude,
    this.longitude,
    this.audioUrl,
    this.audioStoragePath,
    this.audioDuration,
    this.audioWaveform = const [],
    this.replyTo,
    this.readAt,
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
    List<String>? mediaStoragePaths,
    double? latitude,
    double? longitude,
    String? audioUrl,
    String? audioStoragePath,
    Duration? audioDuration,
    List<double>? audioWaveform,
    MessageReply? replyTo,
    DateTime? readAt,
    bool clearReplyTo = false,
    bool clearReadAt = false,
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
      mediaStoragePaths: mediaStoragePaths ?? this.mediaStoragePaths,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      audioUrl: audioUrl ?? this.audioUrl,
      audioStoragePath: audioStoragePath ?? this.audioStoragePath,
      audioDuration: audioDuration ?? this.audioDuration,
      audioWaveform: audioWaveform ?? this.audioWaveform,
      replyTo: clearReplyTo ? null : replyTo ?? this.replyTo,
      readAt: clearReadAt ? null : readAt ?? this.readAt,
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
    mediaStoragePaths,
    latitude,
    longitude,
    audioUrl,
    audioStoragePath,
    audioDuration,
    audioWaveform,
    replyTo,
    readAt,
  ];
}
