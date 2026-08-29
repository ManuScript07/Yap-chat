import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in the platform protected key store.
///
/// A release upgrade may still have the session in the old SharedPreferences
/// key. It is copied once and the plaintext value is removed only after the
/// secure write succeeds.
class SecureSupabaseSessionStorage extends LocalStorage {
  SecureSupabaseSessionStorage({
    required String key,
    required SharedPreferences legacyPreferences,
    FlutterSecureStorage? storage,
  }) : _key = key,
       _legacyPreferences = legacyPreferences,
       _storage = storage ?? const FlutterSecureStorage();

  final String _key;
  final SharedPreferences _legacyPreferences;
  final FlutterSecureStorage _storage;
  Future<void>? _initialization;

  @override
  Future<void> initialize() => _initialization ??= _migrateLegacySession();

  @override
  Future<bool> hasAccessToken() async {
    await initialize();
    return (await _storage.read(key: _key)) != null;
  }

  @override
  Future<String?> accessToken() async {
    await initialize();
    return _storage.read(key: _key);
  }

  @override
  Future<void> removePersistedSession() async {
    await initialize();
    await _storage.delete(key: _key);
    await _legacyPreferences.remove(_key);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await initialize();
    await _storage.write(key: _key, value: persistSessionString);
    await _legacyPreferences.remove(_key);
  }

  Future<void> _migrateLegacySession() async {
    final secureValue = await _storage.read(key: _key);
    if (secureValue != null) {
      await _legacyPreferences.remove(_key);
      return;
    }

    final legacyValue = _legacyPreferences.getString(_key);
    if (legacyValue == null || legacyValue.isEmpty) return;
    await _storage.write(key: _key, value: legacyValue);
    await _legacyPreferences.remove(_key);
  }
}

/// Stores transient PKCE verifiers in the same protected key store as the
/// session. Old verifiers are deliberately not migrated: an OAuth attempt in
/// flight is safer to cancel than to keep its verifier in plaintext storage.
class SecureSupabasePkceStorage extends GotrueAsyncStorage {
  static const legacySharedPreferencesKey = 'supabase.auth.token-code-verifier';

  SecureSupabasePkceStorage({
    required String namespace,
    FlutterSecureStorage? storage,
  }) : _namespace = namespace,
       _storage = storage ?? const FlutterSecureStorage();

  final String _namespace;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: _storageKey(key));

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: _storageKey(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: _storageKey(key), value: value);

  String _storageKey(String key) => 'supabase.pkce.$_namespace.$key';
}
