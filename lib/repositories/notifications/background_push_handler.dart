import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/notifications/data/data.dart';
import 'package:yap_chat/repositories/notifications/android_notification_service.dart';
import 'package:yap_chat/repositories/notifications/push_notifications_repository.dart';

@pragma('vm:entry-point')
Future<void> handlePushNotificationInBackground(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();

    if (message.notification != null) return;

    final payload = PushNotificationPayload.fromData(message.data);
    if (!payload.isValid) return;

    final preferences = await SharedPreferences.getInstance();
    final currentUserId = preferences.getString(
      PushNotificationsRepository.currentUserPreferenceKey,
    );
    if (currentUserId == null || currentUserId != payload.recipientId) return;

    final service = AndroidNotificationService(readLaunchDetails: false);
    await service.show(payload);
    await service.dispose();
  } catch (error, stackTrace) {
    debugPrint('Background push handling failed: $error\n$stackTrace');
  }
}
