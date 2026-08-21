import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:yap_chat/features/notifications/data/data.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

class AndroidNotificationService {
  AndroidNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    bool readLaunchDetails = true,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _readLaunchDetails = readLaunchDetails;

  static const channelId = 'chat_messages';
  static const groupKey = 'com.yapchat.app.chat_messages';
  static const _maxMessagesPerConversation = 10;

  final FlutterLocalNotificationsPlugin _plugin;
  final bool _readLaunchDetails;
  final StreamController<PushNotificationPayload> _openedController =
      StreamController.broadcast(sync: true);
  Future<void>? _initialization;

  Stream<PushNotificationPayload> get openedPayloads =>
      _openedController.stream;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!_isAndroid) return;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        _emitPayload(response.payload);
      },
    );

    final l10n = _localizations();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            channelId,
            l10n.notificationsChannelName,
            description: l10n.notificationsChannelDescription,
            importance: Importance.high,
          ),
        );

    if (_readLaunchDetails) {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _emitPayload(launchDetails?.notificationResponse?.payload);
      }
    }
  }

  Future<void> show(PushNotificationPayload payload) async {
    if (!_isAndroid || !payload.isValid) return;
    await initialize();

    final l10n = _localizations();
    final notificationId = notificationIdFor(payload.conversationId);
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    MessagingStyleInformation? activeStyle;
    try {
      activeStyle = await androidPlugin?.getActiveNotificationMessagingStyle(
        id: notificationId,
      );
    } catch (_) {
      activeStyle = null;
    }

    final sender = Person(
      key: payload.senderId,
      name: payload.senderName,
      important: true,
    );
    final messages = <Message>[
      ...?activeStyle?.messages,
      Message(payload.localizedBody(l10n), payload.sentAt, sender),
    ];
    final visibleMessages = messages.length <= _maxMessagesPerConversation
        ? messages
        : messages.sublist(messages.length - _maxMessagesPerConversation);

    final style = MessagingStyleInformation(
      Person(name: l10n.notificationYou),
      conversationTitle: payload.senderName,
      groupConversation: false,
      messages: visibleMessages,
    );
    final androidDetails = AndroidNotificationDetails(
      channelId,
      l10n.notificationsChannelName,
      channelDescription: l10n.notificationsChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.private,
      groupKey: groupKey,
      styleInformation: style,
    );

    await _plugin.show(
      id: notificationId,
      title: payload.senderName,
      body: payload.localizedBody(l10n),
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: payload.toJson(),
    );
  }

  Future<void> cancelConversation(String conversationId) async {
    if (!_isAndroid || conversationId.isEmpty) return;
    await initialize();
    await _plugin.cancel(id: notificationIdFor(conversationId));
  }

  int notificationIdFor(String conversationId) {
    var hash = 0x811c9dc5;
    for (final codeUnit in conversationId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  void _emitPayload(String? source) {
    if (source == null || source.isEmpty || _openedController.isClosed) return;
    try {
      final payload = PushNotificationPayload.fromJson(source);
      if (payload.isValid) _openedController.add(payload);
    } catch (_) {
      return;
    }
  }

  AppLocalizations _localizations() {
    final locale = PlatformDispatcher.instance.locale;
    final supportedLocale =
        AppLocalizations.supportedLocales.any(
          (item) => item.languageCode == locale.languageCode,
        )
        ? Locale(locale.languageCode)
        : const Locale('ru');
    return lookupAppLocalizations(supportedLocale);
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> dispose() => _openedController.close();
}
