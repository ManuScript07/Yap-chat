import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/chats/repositories/abstract_chats_repository.dart';
import 'package:yap_chat/features/chats/repositories/mock_chats_repository.dart';

/// Production-адаптер репозитория чатов.
///
/// Здесь находится единственная точка подключения Supabase/REST-клиента для
/// модуля chats. Пока backend-клиент не добавлен в [AppConfig], реализация
/// делегирует операции локальному источнику, сохраняя контракт фичи стабильным.
class ChatsRepository implements IChatsRepository {
  ChatsRepository({
    required this._config,
  }) : _fallback = MockChatsRepository();

  final AppConfig _config;
  final MockChatsRepository _fallback;

  @override
  Future<List<Chat>> getChats() {
    _config.talker.debug('ChatsRepository.getChats');
    return _fallback.getChats();
  }

  @override
  Future<void> deleteChats(Set<String> ids) {
    _config.talker.debug('ChatsRepository.deleteChats: $ids');
    return _fallback.deleteChats(ids);
  }

  @override
  Future<void> markAsRead(Set<String> ids) {
    _config.talker.debug('ChatsRepository.markAsRead: $ids');
    return _fallback.markAsRead(ids);
  }

  @override
  Future<void> toggleMute(Set<String> ids) {
    _config.talker.debug('ChatsRepository.toggleMute: $ids');
    return _fallback.toggleMute(ids);
  }
}
