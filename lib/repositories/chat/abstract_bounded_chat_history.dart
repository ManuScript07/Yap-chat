import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_chat_repository.dart';

/// A small live head plus an independently anchored history viewport. Simple
/// mock repositories can keep the original growing-feed pagination contract.
abstract interface class IBoundedChatHistory implements IChatRepository {
  Future<List<ChatMessage>> loadHistoryOlder(String chatId, ChatMessage oldest);
  Future<List<ChatMessage>> loadHistoryNewer(String chatId, ChatMessage newest);
  Future<List<ChatMessage>> refreshHistoryMessages(
    String chatId,
    Set<String> ids,
  );
  Future<List<ChatMessage>?> readCachedHistoryWindow(
    String chatId,
    String messageId, {
    bool allowUnverified = false,
  });
}
