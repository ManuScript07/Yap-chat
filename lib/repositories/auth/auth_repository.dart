import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/repositories/auth/abstract_auth_repository.dart';

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required SupabaseClient client,
    required String redirectUrl,
    bool useAnonymousSignIn = false,
  }) : _client = client,
       _redirectUrl = redirectUrl,
       _useAnonymousSignIn = useAnonymousSignIn;

  final SupabaseClient _client;
  final String _redirectUrl;
  final bool _useAnonymousSignIn;

  @override
  AuthSession? get currentSession => _mapSession(_client.auth.currentSession);

  @override
  Stream<AuthSession?> observeSession() {
    final initialSession = currentSession;
    var initialEventSkipped = false;

    return _client.auth.onAuthStateChange
        .map((authState) => _mapSession(authState.session))
        .where((session) {
          if (!initialEventSkipped && session == initialSession) {
            initialEventSkipped = true;
            return false;
          }
          return true;
        })
        .distinct();
  }

  @override
  Future<void> signInWithYandex() async {
    if (_useAnonymousSignIn) {
      await _client.auth.signInAnonymously();
      return;
    }
    await _client.auth.signInWithOAuth(
      OAuthProvider('custom:yandex'),
      redirectTo: kIsWeb ? null : _redirectUrl,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  AuthSession? _mapSession(Session? session) {
    final user = session?.user;
    if (user == null) return null;

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return AuthSession(
      userId: user.id,
      email:
          user.email ??
          _firstString(metadata, const ['email', 'default_email']),
      displayName: _firstString(metadata, const [
        'name',
        'full_name',
        'display_name',
        'real_name',
      ]),
      birthDate: _firstDate(metadata, const ['birth_date', 'birthday']),
      avatarUrl: _firstString(metadata, const [
        'avatar_url',
        'picture',
        'avatar',
      ]),
    );
  }

  String? _firstString(Map<String, dynamic> metadata, List<String> keys) {
    for (final key in keys) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  DateTime? _firstDate(Map<String, dynamic> metadata, List<String> keys) {
    final value = _firstString(metadata, keys);
    return value == null ? null : DateTime.tryParse(value);
  }
}
