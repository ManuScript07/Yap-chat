import 'package:yap_chat/features/settings/data/data.dart';

abstract interface class IAppPublicContentRepository {
  Future<AppPublicContent?> readCached();
  Future<AppPublicContent?> refresh();
}
