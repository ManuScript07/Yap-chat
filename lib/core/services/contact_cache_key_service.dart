import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class IContactCacheKeyService {
  Future<String> createKey(String normalizedPhone);
}

class ContactCacheKeyService implements IContactCacheKeyService {
  ContactCacheKeyService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'contact_match_cache_hmac_key_v1';

  final FlutterSecureStorage _storage;
  Future<List<int>>? _activeSecret;

  @override
  Future<String> createKey(String normalizedPhone) async {
    final secret = await (_activeSecret ??= _loadOrCreateSecret());
    return Hmac(sha256, secret).convert(utf8.encode(normalizedPhone)).toString();
  }

  Future<List<int>> _loadOrCreateSecret() async {
    final stored = await _storage.read(key: _storageKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        final decoded = base64Url.decode(stored);
        if (decoded.length == 32) return decoded;
      } catch (_) {
        // A damaged key makes old opaque cache rows unreadable; replace it.
      }
    }

    final random = Random.secure();
    final secret = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: _storageKey, value: base64Url.encode(secret));
    return secret;
  }
}
