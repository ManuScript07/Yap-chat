import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:yap_chat/features/notifications/data/data.dart';
import 'package:yap_chat/repositories/notifications/notifications.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.platformDispatcher.clearLocaleTestValue();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final scenario in [
    (saved: null, device: 'ru', icon: 'ic_notification_ru'),
    (saved: null, device: 'en', icon: 'ic_notification_en'),
    (saved: null, device: 'de', icon: 'ic_notification_en'),
    (saved: 'ru', device: 'en', icon: 'ic_notification_ru'),
    (saved: 'en', device: 'ru', icon: 'ic_notification_en'),
    (saved: 'invalid', device: 'ru', icon: 'ic_notification_ru'),
    (saved: 'throw', device: 'ru', icon: 'ic_notification_ru'),
  ]) {
    test('notification locale $scenario', () async {
      binding.platformDispatcher.localeTestValue = Locale(scenario.device);
      final shown = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'show') shown.add(call.arguments as Map);
            return call.method == 'initialize' ? true : null;
          });
      final service = AndroidNotificationService(
        readLaunchDetails: false,
        languageReader: () async {
          if (scenario.saved == 'throw') {
            throw StateError('storage unavailable');
          }
          return scenario.saved;
        },
        deviceLocale: () => Locale(scenario.device),
      );
      addTearDown(service.dispose);
      await service.show(
        PushNotificationPayload.fromData({
          'message_id': 'message',
          'conversation_id': 'conversation',
          'recipient_id': 'recipient',
          'sender_id': 'sender',
          'sender_name': 'Peer',
          'message_type': 'text',
          'message_text': 'hello',
          'sent_at': '2026-11-02T10:00:00Z',
        }),
      );
      expect(shown, hasLength(1));
      final details = shown.single['platformSpecifics'] as Map;
      expect(details['icon'], scenario.icon);
      expect(details['channelId'], AndroidNotificationService.channelId);
      expect(details['groupKey'], AndroidNotificationService.groupKey);
    });
  }

  test(
    'background/foreground notification reads the latest selected language and preserves grouping',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'initialize' ? true : null;
          });
      var language = 'en';
      final service = AndroidNotificationService(
        readLaunchDetails: false,
        languageReader: () async => language,
      );
      final payload = PushNotificationPayload.fromData({
        'message_id': 'message',
        'conversation_id': 'conversation',
        'recipient_id': 'recipient',
        'sender_id': 'sender',
        'sender_name': 'Peer',
        'message_type': 'text',
        'message_text': 'hello',
        'sent_at': '2026-11-02T10:00:00Z',
      });
      expect(payload.isValid, isTrue);
      await service.show(payload);
      language = 'ru';
      await service.show(payload);
      final shown = calls
          .where((c) => c.method == 'show')
          .map((c) => c.arguments as Map)
          .toList();
      expect(shown, hasLength(2));
      expect(
        (shown[0]['platformSpecifics'] as Map)['icon'],
        'ic_notification_en',
      );
      expect(
        (shown[1]['platformSpecifics'] as Map)['icon'],
        'ic_notification_ru',
      );
      expect(shown[0]['id'], shown[1]['id']);
      expect(shown[0]['payload'], payload.toJson());
      expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
      expect(
        calls.where((c) => c.method == 'getNotificationAppLaunchDetails'),
        isEmpty,
      );
      await service.dispose();
    },
  );
}
