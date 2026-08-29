import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/chat/abstract_local_media_repository.dart';

class LocalMediaRepository implements ILocalMediaRepository {
  LocalMediaRepository({
    required SharedPreferences preferences,
    required AppDatabase database,
    required String? Function() ownerUserIdProvider,
    required String environment,
    required AccountSessionController accountSessionController,
    Future<Directory> Function()? documentsDirectoryProvider,
  }) : _prefs = preferences,
       _database = database,
       _ownerUserIdProvider = ownerUserIdProvider,
       _environment = environment,
       _accountSessionController = accountSessionController,
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final SharedPreferences _prefs;
  final AppDatabase _database;
  final String? Function() _ownerUserIdProvider;
  final String _environment;
  final AccountSessionController _accountSessionController;
  final Future<Directory> Function() _documentsDirectoryProvider;
  static const _legacyStorageKey = 'recent_chat_media_paths';
  static const _legacyPendingStorageKey = 'pending_chat_media_path';
  static const _legacyPendingChatStorageKey = 'pending_chat_id';
  static const _legacyOwnerKey = 'recent_chat_media_legacy_owner';
  static const maxRecentMediaCount = 50;

  @override
  Future<String?> persistMedia(String sourcePath) async {
    final scope = _captureScope();
    if (scope == null) return null;
    final ownerUserId = scope.userId;
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return null;

    final directory = await _userDirectory(ownerUserId);
    await directory.create(recursive: true);
    final extension = path.extension(sourcePath);
    final fileName =
        'chat_media_${DateTime.now().microsecondsSinceEpoch}$extension';
    final destination = await sourceFile.copy(
      path.join(directory.path, fileName),
    );

    try {
      return await _accountSessionController.commit(scope, () async {
        final current = _recentMediaPaths(
          ownerUserId,
        ).where((storedPath) => File(storedPath).existsSync()).toList();
        final updated = [
          destination.path,
          ...current,
        ].take(maxRecentMediaCount).toList();
        await _prefs.setStringList(_storageKey(ownerUserId), updated);
        unawaited(_collectGarbage(ownerUserId));
        return destination.path;
      });
    } on StaleAccountSessionException {
      if (await destination.exists()) await destination.delete();
      return null;
    }
  }

  @override
  List<String> getRecentMediaPaths() {
    final ownerUserId = _ownerUserIdProvider();
    if (ownerUserId == null || ownerUserId.isEmpty) return const [];
    return _recentMediaPaths(ownerUserId);
  }

  @override
  Future<void> deleteMedia(String mediaPath) async {
    final scope = _captureScope();
    if (scope == null) return;
    await _accountSessionController.commit(scope, () async {
      final updated = _recentMediaPaths(
        scope.userId,
      ).where((storedPath) => storedPath != mediaPath).toList();
      await _prefs.setStringList(_storageKey(scope.userId), updated);
      await _collectGarbage(scope.userId);
    });
  }

  @override
  Future<void> savePendingMedia(String mediaPath) async {
    final scope = _captureScope();
    if (scope == null) return;
    await _accountSessionController.commit(
      scope,
      () => _prefs.setString(_pendingStorageKey(scope.userId), mediaPath),
    );
  }

  @override
  Future<String?> consumePendingMedia() async {
    final scope = _captureScope();
    if (scope == null) return null;
    return _accountSessionController.commit(scope, () async {
      _claimLegacyData(scope.userId);
      final key = _pendingStorageKey(scope.userId);
      final pendingPath = _prefs.getString(key);
      if (pendingPath == null) return null;
      await _prefs.remove(key);
      return pendingPath;
    });
  }

  @override
  Future<void> savePendingChatId(String chatId) async {
    final scope = _captureScope();
    if (scope == null) return;
    await _accountSessionController.commit(
      scope,
      () => _prefs.setString(_pendingChatStorageKey(scope.userId), chatId),
    );
  }

  @override
  Future<String?> consumePendingChatId() async {
    final scope = _captureScope();
    if (scope == null) return null;
    return _accountSessionController.commit(scope, () async {
      _claimLegacyData(scope.userId);
      final key = _pendingChatStorageKey(scope.userId);
      final chatId = _prefs.getString(key);
      if (chatId == null) return null;
      await _prefs.remove(key);
      return chatId;
    });
  }

  @override
  Future<void> clearPendingChatId() async {
    final scope = _captureScope();
    if (scope == null) return;
    await _accountSessionController.commit(
      scope,
      () => _prefs.remove(_pendingChatStorageKey(scope.userId)),
    );
  }

  @override
  Future<void> collectGarbage() async {
    final scope = _captureScope();
    if (scope == null) return;
    await _accountSessionController.commit(
      scope,
      () => _collectGarbage(scope.userId),
    );
  }

  @override
  Future<void> clearUser(String ownerUserId) async {
    if (ownerUserId.isEmpty) return;
    _claimLegacyData(ownerUserId);
    final recentPaths = _recentMediaPaths(ownerUserId);
    final pendingPath = _prefs.getString(_pendingStorageKey(ownerUserId));
    final directory = await _userDirectory(ownerUserId);
    if (await directory.exists()) await directory.delete(recursive: true);

    final documents = await _documentsDirectoryProvider();
    for (final value in {
      ...recentPaths,
      if (pendingPath != null) pendingPath,
    }) {
      final file = File(value);
      if (_isLegacyOwnedFile(file, documents) && await file.exists()) {
        await file.delete();
      }
    }
    if (_prefs.getString(_legacyOwnerKey) == _ownerKey(ownerUserId) &&
        await documents.exists()) {
      await for (final entity in documents.list()) {
        if (entity is File && _isLegacyOwnedFile(entity, documents)) {
          await entity.delete();
        }
      }
    }
    await Future.wait([
      _prefs.remove(_storageKey(ownerUserId)),
      _prefs.remove(_pendingStorageKey(ownerUserId)),
      _prefs.remove(_pendingChatStorageKey(ownerUserId)),
    ]);
  }

  List<String> _recentMediaPaths(String ownerUserId) {
    _claimLegacyData(ownerUserId);
    return _prefs.getStringList(_storageKey(ownerUserId)) ?? const [];
  }

  void _claimLegacyData(String ownerUserId) {
    final claimedOwner = _prefs.getString(_legacyOwnerKey);
    if (claimedOwner != null) return;
    _prefs.setString(_legacyOwnerKey, _ownerKey(ownerUserId));
    final legacyRecent = _prefs.getStringList(_legacyStorageKey);
    if (legacyRecent != null) {
      _prefs.setStringList(_storageKey(ownerUserId), legacyRecent);
      _prefs.remove(_legacyStorageKey);
    }
    final legacyPending = _prefs.getString(_legacyPendingStorageKey);
    if (legacyPending != null) {
      _prefs.setString(_pendingStorageKey(ownerUserId), legacyPending);
      _prefs.remove(_legacyPendingStorageKey);
    }
    final legacyChatId = _prefs.getString(_legacyPendingChatStorageKey);
    if (legacyChatId != null) {
      _prefs.setString(_pendingChatStorageKey(ownerUserId), legacyChatId);
      _prefs.remove(_legacyPendingChatStorageKey);
    }
  }

  Future<void> _collectGarbage(String ownerUserId) async {
    final protectedPaths = <String>{
      ..._recentMediaPaths(ownerUserId),
      if (_prefs.getString(_pendingStorageKey(ownerUserId)) case final value?)
        value,
    };
    final operations = await (_database.select(
      _database.pendingChatOperations,
    )..where((table) => table.ownerUserId.equals(ownerUserId))).get();
    for (final operation in operations) {
      try {
        final payload = jsonDecode(operation.payloadJson);
        if (payload is! Map) continue;
        final imagePaths = payload['image_paths'];
        if (imagePaths is List) {
          protectedPaths.addAll(imagePaths.whereType<String>());
        }
      } catch (_) {
        // Повреждённая outbox-запись не должна блокировать сборку мусора.
      }
    }
    final messages = await (_database.select(
      _database.cachedMessages,
    )..where((table) => table.ownerUserId.equals(ownerUserId))).get();
    for (final message in messages) {
      try {
        protectedPaths.addAll(
          (jsonDecode(message.mediaUrlsJson) as List).whereType<String>(),
        );
      } catch (_) {
        // Повреждённый локальный путь будет восстановлен синхронизацией.
      }
    }

    final directory = await _userDirectory(ownerUserId);
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File && !protectedPaths.contains(entity.path)) {
        await entity.delete();
      }
    }
  }

  Future<Directory> _userDirectory(String ownerUserId) async {
    final documents = await _documentsDirectoryProvider();
    return Directory(
      path.join(
        documents.path,
        'chat_recent',
        _safeSegment(_environment),
        _safeSegment(ownerUserId),
      ),
    );
  }

  AccountSessionSnapshot? _captureScope() {
    try {
      final scope = _accountSessionController.capture();
      return scope.userId == _ownerUserIdProvider() ? scope : null;
    } on StaleAccountSessionException {
      return null;
    }
  }

  bool _isLegacyOwnedFile(File file, Directory documents) {
    final normalizedParent = path.normalize(file.parent.absolute.path);
    final normalizedDocuments = path.normalize(documents.absolute.path);
    return normalizedParent == normalizedDocuments &&
        path.basename(file.path).startsWith('chat_media_');
  }

  String _storageKey(String ownerUserId) =>
      '${_ownerKey(ownerUserId)}.recent_chat_media_paths';

  String _pendingStorageKey(String ownerUserId) =>
      '${_ownerKey(ownerUserId)}.pending_chat_media_path';

  String _pendingChatStorageKey(String ownerUserId) =>
      '${_ownerKey(ownerUserId)}.pending_chat_id';

  String _ownerKey(String ownerUserId) =>
      'chat_media.${_safeSegment(_environment)}.${_safeSegment(ownerUserId)}';

  String _safeSegment(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
}
