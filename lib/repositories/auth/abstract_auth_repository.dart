import 'package:yap_chat/features/auth/data/data.dart';

abstract interface class IAuthRepository {
  AuthSession? get currentSession;

  Stream<AuthSession?> observeSession();

  Future<void> signInWithYandex();

  Future<void> signOut();
}
