import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/features/notifications/data/data.dart';
import 'package:yap_chat/repositories/notifications/abstract_push_notifications_repository.dart';
import 'package:yap_chat/repositories/notifications/android_notification_service.dart';

class PushNotificationsRepository implements IPushNotificationsRepository {
  PushNotificationsRepository({
    required SupabaseClient client,
    required FirebaseMessaging messaging,
    required SharedPreferences preferences,
    required Talker talker,
    AndroidNotificationService? notificationService,
  }) : _client = client,
       _messaging = messaging,
       _preferences = preferences,
       _talker = talker,
       _notificationService =
           notificationService ?? AndroidNotificationService();

  static const currentUserPreferenceKey = 'push_notifications_user_id';
  static const _senderIdPreferenceKey = 'push_notifications_sender_id';

  final SupabaseClient _client;
  final FirebaseMessaging _messaging;
  final SharedPreferences _preferences;
  final Talker _talker;
  final AndroidNotificationService _notificationService;
  final StreamController<String> _openedConversationController =
      StreamController.broadcast(sync: true);

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  StreamSubscription<PushNotificationPayload>? _localOpenSubscription;
  Future<void> _operationQueue = Future<void>.value();
  String? _currentUserId;
  String? _activeConversationId;
  bool _isAppForeground = true;
  bool _listenersBound = false;
  bool _disposed = false;

  @override
  Stream<String> get openedConversationIds =>
      _openedConversationController.stream;

  @override
  Future<void> setAuthenticatedUser(String? userId) => _enqueue(() async {
    if (_disposed) return;
    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      _currentUserId = null;
      _activeConversationId = null;
      await _preferences.remove(currentUserPreferenceKey);
      return;
    }
    if (_currentUserId == normalizedUserId) return;

    _currentUserId = normalizedUserId;
    _activeConversationId = null;
    await _preferences.setString(currentUserPreferenceKey, normalizedUserId);
    await _bindListeners();
    await _requestPermissionAndRegisterToken();
    await _consumeInitialFirebaseMessage();
  });

  @override
  Future<void> setActiveConversation(String? conversationId) async {
    final normalizedId = conversationId?.trim();
    _activeConversationId = normalizedId == null || normalizedId.isEmpty
        ? null
        : normalizedId;
    if (_activeConversationId != null) {
      await _notificationService.cancelConversation(_activeConversationId!);
    }
  }

  @override
  Future<void> setAppForeground(bool isForeground) async {
    _isAppForeground = isForeground;
  }

  @override
  Future<void> unregisterCurrentDevice() => _enqueue(() async {
    final userId = _currentUserId;
    _currentUserId = null;
    _activeConversationId = null;
    await _preferences.remove(currentUserPreferenceKey);
    if (userId == null) return;

    String? token;
    try {
      token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _client.rpc(
          'unregister_push_device',
          params: {'device_token': token},
        );
      }
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Push token unregister failed');
    } finally {
      try {
        await _messaging.deleteToken();
      } catch (error, stackTrace) {
        _talker.handle(error, stackTrace, 'FCM token deletion failed');
      }
    }
  });

  Future<void> _bindListeners() async {
    if (_listenersBound) return;
    _listenersBound = true;

    _localOpenSubscription = _notificationService.openedPayloads.listen(
      _handleOpenedPayload,
    );
    await _notificationService.initialize();

    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (token) => unawaited(_registerToken(token)),
      onError: (Object error, StackTrace stackTrace) {
        _talker.handle(error, stackTrace, 'FCM token stream failed');
      },
    );
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      (message) => unawaited(_handleForegroundMessage(message)),
      onError: (Object error, StackTrace stackTrace) {
        _talker.handle(error, stackTrace, 'Foreground push stream failed');
      },
    );
    _openedMessageSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleRemoteOpenedMessage,
      onError: (Object error, StackTrace stackTrace) {
        _talker.handle(error, stackTrace, 'Opened push stream failed');
      },
    );
  }

  Future<void> _requestPermissionAndRegisterToken() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final isAllowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!isAllowed || _currentUserId == null) return;

      await _resetTokenAfterSenderChange();
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) await _registerToken(token);
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Push permission setup failed');
    }
  }

  Future<void> _resetTokenAfterSenderChange() async {
    final senderId = Firebase.app().options.messagingSenderId.trim();
    if (senderId.isEmpty) return;
    if (_preferences.getString(_senderIdPreferenceKey) == senderId) return;

    try {
      await _messaging.deleteToken();
      await _preferences.setString(_senderIdPreferenceKey, senderId);
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'FCM sender migration failed');
    }
  }

  Future<void> _registerToken(String token) async {
    if (_currentUserId == null || token.isEmpty) return;

    try {
      await _client.rpc(
        'register_push_device',
        params: {
          'device_token': token,
          'device_locale': _deviceLanguageCode,
          'device_app_version': null,
        },
      );
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Push token registration failed');
    }
  }

  Future<void> _consumeInitialFirebaseMessage() async {
    try {
      final message = await _messaging.getInitialMessage();
      if (message != null) {
        _handleOpenedPayload(PushNotificationPayload.fromData(message.data));
      }
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Initial push handling failed');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    try {
      final payload = PushNotificationPayload.fromData(message.data);
      if (!_belongsToCurrentUser(payload) || !payload.isValid) return;
      if (_isAppForeground && _activeConversationId == payload.conversationId) {
        return;
      }
      await _notificationService.show(payload);
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Foreground push handling failed');
    }
  }

  void _handleOpenedPayload(PushNotificationPayload payload) {
    if (_disposed || !_belongsToCurrentUser(payload) || !payload.isValid) {
      return;
    }
    _openedConversationController.add(payload.conversationId);
  }

  void _handleRemoteOpenedMessage(RemoteMessage message) {
    try {
      _handleOpenedPayload(PushNotificationPayload.fromData(message.data));
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, 'Opened push handling failed');
    }
  }

  bool _belongsToCurrentUser(PushNotificationPayload payload) =>
      _currentUserId != null && payload.recipientId == _currentUserId;

  String get _deviceLanguageCode {
    final languageCode = PlatformDispatcher.instance.locale.languageCode;
    return languageCode == 'en' ? 'en' : 'ru';
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _operationQueue = _operationQueue.then((_) => operation()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _talker.handle(error, stackTrace, 'Push repository operation failed');
    });
    return _operationQueue;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([
      _tokenSubscription?.cancel() ?? Future<void>.value(),
      _foregroundMessageSubscription?.cancel() ?? Future<void>.value(),
      _openedMessageSubscription?.cancel() ?? Future<void>.value(),
      _localOpenSubscription?.cancel() ?? Future<void>.value(),
    ]);
    await _notificationService.dispose();
    await _openedConversationController.close();
  }
}
