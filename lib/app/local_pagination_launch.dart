import 'dart:convert';

/// Explicit, local-only launch overrides for the persistent pagination lab.
/// No overrides means the normal application configuration is returned intact.
class LocalPaginationLaunch {
  const LocalPaginationLaunch({
    required this.url,
    required this.publishableKey,
    required this.ownerId,
    required this.refreshToken,
  });

  const LocalPaginationLaunch.fromDefines()
    : url = const String.fromEnvironment('PAGINATION_LAB_URL'),
      publishableKey = const String.fromEnvironment('PAGINATION_LAB_KEY'),
      ownerId = const String.fromEnvironment('PAGINATION_LAB_OWNER_ID'),
      refreshToken = const String.fromEnvironment(
        'PAGINATION_LAB_REFRESH_TOKEN',
      );

  final String url, publishableKey, ownerId, refreshToken;
  bool get enabled =>
      [url, publishableKey, ownerId, refreshToken].any((v) => v.isNotEmpty);

  Map<String, String> apply(Map<String, String> base, {required bool release}) {
    if (!enabled) return base;
    if (release) {
      throw StateError('Pagination lab cannot run in a release build');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'http' ||
        !const {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(ownerId) ||
        refreshToken.isEmpty) {
      throw StateError(
        'Pagination lab requires a loopback URL and a local test session',
      );
    }
    var publicKey = publishableKey.startsWith('sb_publishable_');
    if (!publicKey) {
      try {
        final claims = jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(publishableKey.split('.')[1])),
          ),
        );
        publicKey = claims is Map && claims['role'] == 'anon';
      } catch (_) {
        publicKey = false;
      }
    }
    if (!publicKey) {
      throw StateError('Pagination lab requires a public client key');
    }
    return {
      ...base,
      'APP_ENV': 'local',
      'SUPABASE_URL': url,
      'SUPABASE_PUBLISHABLE_KEY': publishableKey,
    };
  }
}
