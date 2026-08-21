import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

enum PushMessageType { text, image, audio, location }

class PushNotificationPayload extends Equatable {
  const PushNotificationPayload({
    required this.conversationId,
    required this.messageId,
    required this.recipientId,
    required this.senderId,
    required this.senderName,
    required this.messageType,
    required this.messageText,
    required this.sentAt,
  });

  factory PushNotificationPayload.fromData(Map<String, dynamic> data) {
    final sentAt = DateTime.tryParse(_stringValue(data['sent_at']));
    final contentType = _stringValue(
      data['content_type'] ?? data['message_type'],
    );
    return PushNotificationPayload(
      conversationId: _stringValue(data['conversation_id']),
      messageId: _stringValue(data['message_id']),
      recipientId: _stringValue(data['recipient_id']),
      senderId: _stringValue(data['sender_id']),
      senderName: _stringValue(data['sender_name']),
      messageType: PushMessageType.values.firstWhere(
        (type) => type.name == contentType,
        orElse: () => PushMessageType.text,
      ),
      messageText: _stringValue(data['message_text']),
      sentAt: sentAt?.toLocal() ?? DateTime.now(),
    );
  }

  factory PushNotificationPayload.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid push notification payload');
    }
    return PushNotificationPayload.fromData(decoded);
  }

  final String conversationId;
  final String messageId;
  final String recipientId;
  final String senderId;
  final String senderName;
  final PushMessageType messageType;
  final String messageText;
  final DateTime sentAt;

  bool get isValid =>
      conversationId.isNotEmpty &&
      messageId.isNotEmpty &&
      recipientId.isNotEmpty &&
      senderId.isNotEmpty;

  String localizedBody(AppLocalizations l10n) => switch (messageType) {
    PushMessageType.text => messageText,
    PushMessageType.image => l10n.notificationPhoto,
    PushMessageType.audio => l10n.notificationAudio,
    PushMessageType.location => l10n.notificationLocation,
  };

  String toJson() => jsonEncode({
    'conversation_id': conversationId,
    'message_id': messageId,
    'recipient_id': recipientId,
    'sender_id': senderId,
    'sender_name': senderName,
    'message_type': messageType.name,
    'message_text': messageText,
    'sent_at': sentAt.toUtc().toIso8601String(),
  });

  static String _stringValue(Object? value) => value?.toString().trim() ?? '';

  @override
  List<Object?> get props => [
    conversationId,
    messageId,
    recipientId,
    senderId,
    senderName,
    messageType,
    messageText,
    sentAt,
  ];
}
