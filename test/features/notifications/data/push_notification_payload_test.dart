import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/notifications/data/data.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

void main() {
  group('PushNotificationPayload.fromData', () {
    test(
      'reaction notification keeps chat navigation and survives serialization',
      () {
        final payload = PushNotificationPayload.fromData({
          ..._requiredData,
          'notification_type': 'message_reaction',
          'message_text': 'hello',
        });
        expect(payload.kind, PushNotificationKind.messageReaction);
        expect(payload.isValid, isTrue);
        expect(payload.isChatMessage, isTrue);
        expect(
          payload.localizedBody(lookupAppLocalizations(const Locale('ru'))),
          'Поставил реакцию на «hello»',
        );
        expect(PushNotificationPayload.fromJson(payload.toJson()), payload);
      },
    );
    test('reads the FCM-safe content type key', () {
      final payload = PushNotificationPayload.fromData({
        ..._requiredData,
        'content_type': 'audio',
      });

      expect(payload.messageType, PushMessageType.audio);
    });

    test('keeps compatibility with local notification payloads', () {
      final payload = PushNotificationPayload.fromData({
        ..._requiredData,
        'message_type': 'image',
      });

      expect(payload.messageType, PushMessageType.image);
    });

    test('accepts friend requests without chat navigation fields', () {
      final payload = PushNotificationPayload.fromData({
        'notification_type': 'friend_request',
        'friend_request_id': 'request-id',
        'recipient_id': 'recipient-id',
        'sender_id': 'sender-id',
        'sender_name': 'Sender',
        'sent_at': '2026-08-24T00:00:00Z',
      });

      expect(payload.kind, PushNotificationKind.friendRequest);
      expect(payload.isChatMessage, isFalse);
      expect(payload.isValid, isTrue);
    });

    test('shows the sender and text from a validated data payload', () {
      final payload = PushNotificationPayload.fromData({
        ..._requiredData,
        'message_text': 'private message',
      });

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(payload.localizedTitle(l10n), 'Sender');
      expect(payload.localizedBody(l10n), 'private message');
    });
  });
}

final _requiredData = <String, dynamic>{
  'conversation_id': 'conversation-id',
  'message_id': 'message-id',
  'recipient_id': 'recipient-id',
  'sender_id': 'sender-id',
  'sender_name': 'Sender',
  'message_text': '',
  'sent_at': '2026-08-21T00:00:00Z',
};
