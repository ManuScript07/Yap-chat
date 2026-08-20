import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/repositories/repositories.dart';

/// Единственная точка, которая переводит сетевые репозитории между foreground
/// и background. Повторные lifecycle/auth-события выполняются последовательно.
class AppConnectionCoordinator {
  AppConnectionCoordinator({
    required IChatsRepository chatsRepository,
    required IChatRepository chatRepository,
    required IPresenceRepository presenceRepository,
    required Talker talker,
  }) : _chatsRepository = chatsRepository,
       _chatRepository = chatRepository,
       _presenceRepository = presenceRepository,
       _talker = talker;

  final IChatsRepository _chatsRepository;
  final IChatRepository _chatRepository;
  final IPresenceRepository _presenceRepository;
  final Talker _talker;

  Future<void> _operation = Future<void>.value();
  bool _isForeground = true;
  bool _isConnected = false;
  bool _isDisposed = false;
  String? _desiredUserId;
  String? _connectedUserId;

  Future<void> setForeground(bool isForeground) {
    if (_isDisposed || _isForeground == isForeground) return _operation;
    _isForeground = isForeground;
    return _enqueueReconciliation();
  }

  Future<void> setAuthenticatedUser(String? userId) {
    if (_isDisposed || _desiredUserId == userId) return _operation;
    _desiredUserId = userId;
    return _enqueueReconciliation();
  }

  Future<void> dispose() {
    if (_isDisposed) return _operation;
    _isDisposed = true;
    _isForeground = false;
    _desiredUserId = null;
    return _enqueueReconciliation(allowDisposed: true);
  }

  Future<void> _enqueueReconciliation({bool allowDisposed = false}) {
    final operation = _operation.then(
      (_) => _reconcile(allowDisposed: allowDisposed),
      onError: (_) => _reconcile(allowDisposed: allowDisposed),
    );
    _operation = operation;
    return operation;
  }

  Future<void> _reconcile({required bool allowDisposed}) async {
    if (_isDisposed && !allowDisposed) return;
    final desiredUserId = _desiredUserId;

    if (!_isForeground || desiredUserId == null) {
      if (!_isConnected) return;
      _isConnected = false;
      _connectedUserId = null;
      await Future.wait([
        _guard('Chats realtime pause failed', _chatsRepository.pauseRealtime),
        _guard('Chat network pause failed', _chatRepository.pauseNetwork),
        _guard('Presence disconnect failed', _presenceRepository.disconnect),
      ]);
      return;
    }

    if (_isConnected && _connectedUserId == desiredUserId) return;
    if (_isConnected) {
      _isConnected = false;
      _connectedUserId = null;
      await Future.wait([
        _guard('Chats realtime pause failed', _chatsRepository.pauseRealtime),
        _guard('Chat network pause failed', _chatRepository.pauseNetwork),
        _guard('Presence disconnect failed', _presenceRepository.disconnect),
      ]);
    }

    _isConnected = true;
    _connectedUserId = desiredUserId;
    await Future.wait([
      _guard('Chats realtime resume failed', _chatsRepository.resumeRealtime),
      _guard(
        'Open chats synchronization failed',
        _chatRepository.synchronizeOpenChats,
      ),
      _guard(
        'Presence connect failed',
        () => _presenceRepository.connect(desiredUserId),
      ),
    ]);
  }

  Future<void> _guard(String message, Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error, stackTrace) {
      _talker.handle(error, stackTrace, message);
    }
  }
}
