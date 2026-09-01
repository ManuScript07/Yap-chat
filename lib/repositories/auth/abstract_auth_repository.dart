import 'package:yap_chat/features/auth/data/data.dart';

abstract interface class IAuthRepository {
  AuthSession? get currentSession;

  bool get isSignInCallbackProcessing;

  Stream<AuthSession?> observeSession();

  /// Checks a restored/OAuth session before the app opens account data.
  /// Network errors intentionally propagate so AuthBloc can keep the existing
  /// offline-cache behavior for ordinary users.
  Future<AuthAccountAccess> getAccountAccess();

  Future<void> signInWithYandex();

  Future<void> cancelPendingSignIn();

  Future<void> signOut();
}
