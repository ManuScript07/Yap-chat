import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/repositories/auth/abstract_auth_repository.dart';

class MockAuthRepository implements IAuthRepository {
  MockAuthRepository({required SharedPreferences preferences})
    : _preferences = preferences {
    if (_preferences.getBool(_signedInKey) ?? false) {
      _currentSession = _mockSession;
    }
  }

  static const _signedInKey = 'mock_auth_signed_in';
  static final _mockSession = AuthSession(
    userId: 'mock-yandex-user',
    email: 'user@yandex.ru',
    displayName: 'Пользователь Яндекса',
    birthDate: DateTime(2000, 1, 1),
  );

  final SharedPreferences _preferences;
  final _sessionController = StreamController<AuthSession?>.broadcast();
  AuthSession? _currentSession;

  @override
  AuthSession? get currentSession => _currentSession;

  @override
  Stream<AuthSession?> observeSession() => _sessionController.stream.distinct();

  @override
  Future<void> signInWithYandex() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _currentSession = _mockSession;
    await _preferences.setBool(_signedInKey, true);
    _sessionController.add(_currentSession);
  }

  @override
  Future<void> signOut() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _currentSession = null;
    await _preferences.remove(_signedInKey);
    _sessionController.add(null);
  }
}
