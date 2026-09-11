import 'package:yap_chat/features/auth/data/data.dart';

abstract interface class IAuthRepository {
  AuthSession? get currentSession;

  bool get isSignInCallbackProcessing;

  Stream<AuthSession?> observeSession();

  /// Checks a restored/OAuth session before the app opens account data.
  /// Network errors intentionally propagate so AuthBloc can keep the existing
  /// offline-cache behavior for ordinary users.
  Future<AuthAccountAccess> getAccountAccess();

  Future<AuthAccountAccess?> getCachedAccountAccess(String userId);

  Future<void> cacheAccountAccess(String userId, AuthAccountAccess access);

  Future<void> signInWithYandex();

  Future<void> cancelPendingSignIn();

  /// Starts the reversible thirty-day deletion window for the signed-in user.
  Future<DateTime?> requestAccountDeletion();

  /// Restores the signed-in account while its deletion window is still open.
  Future<void> restoreAccountDeletion();

  Future<void> signOut({bool preserveAccountAccess = false});
}
