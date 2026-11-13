import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/core/services/secure_supabase_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'migrates the old session once, then removes its plaintext copy',
    () async {
      const key = 'sb-project-auth-token';
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, 'legacy-session');
      final secureStorage = _MemorySecureStorage();
      final storage = SecureSupabaseSessionStorage(
        key: key,
        legacyPreferences: preferences,
        storage: secureStorage,
      );

      expect(await storage.accessToken(), 'legacy-session');
      expect(preferences.containsKey(key), isFalse);
      expect(await secureStorage.read(key: key), 'legacy-session');
    },
  );

  test('removing a session clears both protected and legacy storage', () async {
    const key = 'sb-project-auth-token';
    final preferences = await SharedPreferences.getInstance();
    final secureStorage = _MemorySecureStorage()..values[key] = 'session';
    await preferences.setString(key, 'stale-plaintext-session');
    final storage = SecureSupabaseSessionStorage(
      key: key,
      legacyPreferences: preferences,
      storage: secureStorage,
    );

    await storage.removePersistedSession();

    expect(await secureStorage.read(key: key), isNull);
    expect(preferences.containsKey(key), isFalse);
  });

  test(
    'namespaces PKCE values away from the session and other environments',
    () async {
      final secureStorage = _MemorySecureStorage();
      final prod = SecureSupabasePkceStorage(
        namespace: 'prod',
        storage: secureStorage,
      );
      final local = SecureSupabasePkceStorage(
        namespace: 'local',
        storage: secureStorage,
      );

      await prod.setItem(key: 'verifier', value: 'prod-value');

      expect(await prod.getItem(key: 'verifier'), 'prod-value');
      expect(await local.getItem(key: 'verifier'), isNull);
    },
  );
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}
