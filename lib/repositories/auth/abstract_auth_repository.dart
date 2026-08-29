import 'package:yap_chat/features/auth/data/data.dart';

abstract interface class IAuthRepository {
  AuthSession? get currentSession;

  bool get isSignInCallbackProcessing;

  Stream<AuthSession?> observeSession();

  Future<void> signInWithYandex();

  Future<void> cancelPendingSignIn();

  Future<void> signOut();
}
