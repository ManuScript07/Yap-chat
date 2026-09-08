import 'package:yap_chat/features/settings/data/data.dart';

/// A cached public manifest and the time it was successfully downloaded.
///
/// [fetchedAt] is deliberately local metadata: the server-side document update
/// time cannot tell whether this device already has the latest manifest.
class CachedAppPublicContent {
  const CachedAppPublicContent({
    required this.content,
    required this.fetchedAt,
  });

  final AppPublicContent content;
  final DateTime? fetchedAt;

  bool isFresh({required DateTime now, required Duration maxAge}) {
    final value = fetchedAt;
    return value != null && !now.toUtc().difference(value).isNegative &&
        now.toUtc().difference(value) < maxAge;
  }
}

abstract interface class IAppPublicContentRepository {
  Future<CachedAppPublicContent?> readCached();
  Future<AppPublicContent?> refresh();
}
