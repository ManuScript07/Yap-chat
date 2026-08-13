import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/repositories/chat/abstract_local_media_repository.dart';

class LocalMediaRepository implements ILocalMediaRepository {
  LocalMediaRepository({
    required SharedPreferences preferences,
  }) : _prefs = preferences;

  final SharedPreferences _prefs;
  static const _storageKey = 'recent_chat_media_paths';
  static const _pendingStorageKey = 'pending_chat_media_path';
  static const _pendingChatStorageKey = 'pending_chat_id';

  @override
  Future<String?> persistMedia(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return null;

    final directory = await getApplicationDocumentsDirectory();
    final extension = path.extension(sourcePath);
    final fileName =
        'chat_media_${DateTime.now().microsecondsSinceEpoch}$extension';
    final destination = await sourceFile.copy(
      path.join(directory.path, fileName),
    );

    final current = getRecentMediaPaths()
        .where((storedPath) => File(storedPath).existsSync())
        .toList();
    final updated = [destination.path, ...current].take(20).toList();
    await _prefs.setStringList(_storageKey, updated);
    return destination.path;
  }

  @override
  List<String> getRecentMediaPaths() {
    return _prefs.getStringList(_storageKey) ?? [];
  }

  @override
  Future<void> deleteMedia(String mediaPath) async {
    final updated = getRecentMediaPaths()
        .where((storedPath) => storedPath != mediaPath)
        .toList();
    await _prefs.setStringList(_storageKey, updated);
  }

  @override
  Future<void> savePendingMedia(String mediaPath) async {
    await _prefs.setString(_pendingStorageKey, mediaPath);
  }

  @override
  Future<String?> consumePendingMedia() async {
    final pendingPath = _prefs.getString(_pendingStorageKey);
    if (pendingPath == null) return null;

    await _prefs.remove(_pendingStorageKey);
    return pendingPath;
  }

  @override
  Future<void> savePendingChatId(String chatId) async {
    await _prefs.setString(_pendingChatStorageKey, chatId);
  }

  @override
  Future<String?> consumePendingChatId() async {
    final chatId = _prefs.getString(_pendingChatStorageKey);
    if (chatId == null) return null;

    await _prefs.remove(_pendingChatStorageKey);
    return chatId;
  }

  @override
  Future<void> clearPendingChatId() async {
    await _prefs.remove(_pendingChatStorageKey);
  }
}
