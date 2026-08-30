import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/app_content/abstract_app_public_content_repository.dart';
import 'package:yap_chat/repositories/app_content/app_public_content_cache_data_source.dart';
import 'package:yap_chat/repositories/app_content/app_public_content_remote_data_source.dart';

class AppPublicContentRepository implements IAppPublicContentRepository {
  AppPublicContentRepository({
    required this._cache,
    required this._remote,
  });

  final AppPublicContentCacheDataSource _cache;
  final AppPublicContentRemoteDataSource _remote;

  @override
  Future<AppPublicContent?> readCached() => _cache.read();

  @override
  Future<AppPublicContent?> refresh() async {
    final content = await _remote.fetch();
    if (content != null) await _cache.write(content);
    return content;
  }
}
