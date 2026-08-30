import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/app_content/abstract_app_public_content_repository.dart';

class MockAppPublicContentRepository implements IAppPublicContentRepository {
  const MockAppPublicContentRepository();

  @override
  Future<AppPublicContent?> readCached() async => null;

  @override
  Future<AppPublicContent?> refresh() async => null;
}
