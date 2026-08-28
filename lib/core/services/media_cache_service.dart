import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/database/database.dart';

class MediaCacheService {
  MediaCacheService({
    required AppDatabase database,
    SupabaseClient? client,
    this.maxCacheBytes = 256 * 1024 * 1024,
    this.maxSingleFileBytes = 16 * 1024 * 1024,
    this.environment = 'prod',
    this.trimDelay = const Duration(seconds: 2),
    Talker? talker,
    Future<Directory> Function()? cacheDirectoryProvider,
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _database = database,
       _client = client,
       _talker = talker,
       _cacheDirectoryProvider =
           cacheDirectoryProvider ?? getTemporaryDirectory,
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const externalAvatarsBucket = 'external-avatars';

  final AppDatabase _database;
  final SupabaseClient? _client;
  final int maxCacheBytes;
  final int maxSingleFileBytes;
  final String environment;
  final Duration trimDelay;
  final Talker? _talker;
  final Future<Directory> Function() _cacheDirectoryProvider;
  final Future<Directory> Function() _supportDirectoryProvider;
  final Uuid _uuid = const Uuid();
  final Map<String, Future<String>> _activeWrites = {};
  final LinkedHashMap<String, String> _resolvedPaths = LinkedHashMap();
  final Queue<Completer<void>> _downloadQueue = Queue();
  final Map<String, Timer> _trimTimers = {};
  final Map<String, Future<void>> _maintenance = {};
  final Map<String, int> _userGenerations = {};
  int _activeDownloadCount = 0;

  Future<String> cacheStorageFile({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    String? mimeType,
  }) async {
    await _ensureMaintenance(ownerUserId);
    final generation = _generation(ownerUserId);
    final key = _operationKey(ownerUserId, bucket, storagePath);
    final resolved = _takeResolvedPath(key);
    if (resolved != null) {
      final file = File(resolved);
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
        return resolved;
      }
      _forgetResolvedPath(resolved);
    }
    final localPath = await _runOnce(
      ownerUserId,
      bucket,
      storagePath,
      () async {
        final cached = await _readExisting(
          ownerUserId,
          bucket,
          storagePath,
          mimeType,
        );
        if (cached != null) return cached;

        final client = _client;
        if (client == null) {
          throw StateError('Supabase is required to download storage media');
        }
        final bytes = await _withDownloadSlot(
          () => client.storage.from(bucket).download(storagePath),
        );
        _validateFileSize(bytes.lengthInBytes);
        return _writeBytes(
          ownerUserId: ownerUserId,
          bucket: bucket,
          storagePath: storagePath,
          bytes: bytes,
          mimeType: mimeType,
          expectedGeneration: generation,
        );
      },
    );
    _ensureGeneration(ownerUserId, generation);
    return _rememberResolvedPath(key, localPath);
  }

  Future<String?> findStorageFile({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    String? mimeType,
  }) async {
    await _ensureMaintenance(ownerUserId);
    return _readExisting(ownerUserId, bucket, storagePath, mimeType);
  }

  Future<String> cacheNetworkFile({
    required String ownerUserId,
    required String url,
    String bucket = externalAvatarsBucket,
  }) async {
    await _ensureMaintenance(ownerUserId);
    final generation = _generation(ownerUserId);
    final key = _operationKey(ownerUserId, bucket, url);
    final resolved = _takeResolvedPath(key);
    if (resolved != null) {
      final file = File(resolved);
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
        return resolved;
      }
      _forgetResolvedPath(resolved);
    }
    final localPath = await _runOnce(ownerUserId, bucket, url, () async {
      final cached = await _readExisting(ownerUserId, bucket, url, null);
      if (cached != null) return cached;

      return _withDownloadSlot(() async {
        final uri = Uri.parse(url);
        final client = HttpClient();
        try {
          final request = await client.getUrl(uri);
          final response = await request.close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException(
              'Media download failed with ${response.statusCode}',
              uri: uri,
            );
          }
          final advertisedLength = response.contentLength;
          if (advertisedLength > maxSingleFileBytes) {
            throw const FileSystemException('Media file is too large');
          }
          final builder = BytesBuilder(copy: false);
          var receivedBytes = 0;
          await for (final chunk in response) {
            receivedBytes += chunk.length;
            _validateFileSize(receivedBytes);
            builder.add(chunk);
          }
          final bytes = builder.takeBytes();
          return await _writeBytes(
            ownerUserId: ownerUserId,
            bucket: bucket,
            storagePath: url,
            bytes: bytes,
            mimeType: response.headers.contentType?.mimeType,
            expectedGeneration: generation,
          );
        } finally {
          client.close(force: true);
        }
      });
    });
    _ensureGeneration(ownerUserId, generation);
    return _rememberResolvedPath(key, localPath);
  }

  Future<String> storeBytes({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    await _ensureMaintenance(ownerUserId);
    _validateFileSize(bytes.lengthInBytes);
    final generation = _generation(ownerUserId);
    final localPath = await _runOnce(
      ownerUserId,
      bucket,
      storagePath,
      () => _writeBytes(
        ownerUserId: ownerUserId,
        bucket: bucket,
        storagePath: storagePath,
        bytes: bytes,
        mimeType: mimeType,
        expectedGeneration: generation,
      ),
    );
    _ensureGeneration(ownerUserId, generation);
    return localPath;
  }

  Future<String> storeFile({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    required String sourcePath,
    String? mimeType,
  }) async {
    return storeBytes(
      ownerUserId: ownerUserId,
      bucket: bucket,
      storagePath: storagePath,
      bytes: await File(sourcePath).readAsBytes(),
      mimeType: mimeType,
    );
  }

  Future<void> removeStorageFiles({
    required String ownerUserId,
    required String bucket,
    required Iterable<String> storagePaths,
    String? mimeType,
  }) async {
    for (final storagePath in storagePaths) {
      final file = await _destinationFile(
        ownerUserId,
        bucket,
        storagePath,
        mimeType,
      );
      if (await file.exists()) await file.delete();
      final legacyFile = await _legacyDestinationFile(
        ownerUserId,
        bucket,
        storagePath,
        mimeType,
      );
      if (await legacyFile.exists()) await legacyFile.delete();
      _forgetResolvedPath(file.path);
      _forgetResolvedPath(legacyFile.path);
    }
  }

  Future<void> removeLocalFiles(Iterable<String> paths) async {
    for (final value in paths) {
      final file = File(value);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> clearUser(String ownerUserId) async {
    _userGenerations[ownerUserId] = _generation(ownerUserId) + 1;
    _trimTimers.remove(ownerUserId)?.cancel();
    _maintenance.remove(ownerUserId);
    _activeWrites.removeWhere((key, _) => key.startsWith('$ownerUserId\u0000'));
    final pending = await (_database.select(
      _database.pendingChatOperations,
    )..where((table) => table.ownerUserId.equals(ownerUserId))).get();
    for (final operation in pending) {
      try {
        final payload = jsonDecode(operation.payloadJson);
        if (payload is! Map) continue;
        final audioPath = payload['audio_path'];
        if (audioPath is! String || audioPath.isEmpty) continue;
        final file = File(audioPath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Повреждённая outbox-запись не должна блокировать очистку аккаунта.
      }
    }

    try {
      final directory = await _userDirectory(ownerUserId);
      if (await directory.exists()) await directory.delete(recursive: true);
      final legacyDirectory = await _legacyUserDirectory(ownerUserId);
      if (await legacyDirectory.exists()) {
        await legacyDirectory.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      _talker?.handle(
        error,
        stackTrace,
        'Media cache directory cleanup failed',
      );
    }
    _resolvedPaths.removeWhere(
      (key, _) => key.startsWith('$ownerUserId\u0000'),
    );

    await _database.transaction(() async {
      await (_database.delete(
        _database.cachedChats,
      )..where((table) => table.ownerUserId.equals(ownerUserId))).go();
      await (_database.delete(
        _database.cachedMessages,
      )..where((table) => table.ownerUserId.equals(ownerUserId))).go();
      await (_database.delete(
        _database.pendingChatOperations,
      )..where((table) => table.ownerUserId.equals(ownerUserId))).go();
      await (_database.delete(
        _database.cachedProfiles,
      )..where((table) => table.userId.equals(ownerUserId))).go();
      await (_database.delete(
        _database.cachedProfilePhotos,
      )..where((table) => table.userId.equals(ownerUserId))).go();
      await (_database.delete(
        _database.cachedFriends,
      )..where((table) => table.ownerUserId.equals(ownerUserId))).go();
      await (_database.delete(
        _database.cachedFriendRequests,
      )..where((table) => table.ownerUserId.equals(ownerUserId))).go();
      await (_database.delete(
        _database.cachedFriendLocations,
      )..where((table) => table.ownerUserId.equals(ownerUserId))).go();
      await (_database.delete(
        _database.cachedContactMatches,
      )..where((table) => table.ownerUserId.equals(ownerUserId))).go();
    });
  }

  Future<String> _runOnce(
    String ownerUserId,
    String bucket,
    String storagePath,
    Future<String> Function() operation,
  ) {
    final key = _operationKey(ownerUserId, bucket, storagePath);
    final active = _activeWrites[key];
    if (active != null) return active;
    final future = operation();
    _activeWrites[key] = future;
    return future.whenComplete(() {
      if (identical(_activeWrites[key], future)) _activeWrites.remove(key);
    });
  }

  String _operationKey(String ownerUserId, String bucket, String storagePath) =>
      '$ownerUserId\u0000$bucket\u0000$storagePath';

  String? _takeResolvedPath(String key) {
    final path = _resolvedPaths.remove(key);
    if (path != null) _resolvedPaths[key] = path;
    return path;
  }

  String _rememberResolvedPath(String key, String localPath) {
    _resolvedPaths.remove(key);
    _resolvedPaths[key] = localPath;
    while (_resolvedPaths.length > 512) {
      _resolvedPaths.remove(_resolvedPaths.keys.first);
    }
    return localPath;
  }

  void _forgetResolvedPath(String localPath) {
    _resolvedPaths.removeWhere((_, path) => path == localPath);
  }

  Future<T> _withDownloadSlot<T>(Future<T> Function() operation) async {
    if (_activeDownloadCount >= 4) {
      final completer = Completer<void>();
      _downloadQueue.add(completer);
      await completer.future;
    }
    _activeDownloadCount++;
    try {
      return await operation();
    } finally {
      _activeDownloadCount--;
      if (_downloadQueue.isNotEmpty) _downloadQueue.removeFirst().complete();
    }
  }

  Future<String?> _readExisting(
    String ownerUserId,
    String bucket,
    String storagePath,
    String? mimeType,
  ) async {
    final file = await _destinationFile(
      ownerUserId,
      bucket,
      storagePath,
      mimeType,
    );
    if (await file.exists()) {
      await file.setLastModified(DateTime.now());
      return file.path;
    }
    final legacyFile = await _legacyDestinationFile(
      ownerUserId,
      bucket,
      storagePath,
      mimeType,
    );
    if (!await legacyFile.exists()) return null;
    await legacyFile.setLastModified(DateTime.now());
    return legacyFile.path;
  }

  Future<String> _writeBytes({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    required Uint8List bytes,
    String? mimeType,
    required int expectedGeneration,
  }) async {
    if (bytes.isEmpty) throw const FileSystemException('Empty media file');
    _validateFileSize(bytes.lengthInBytes);
    _ensureGeneration(ownerUserId, expectedGeneration);
    final destination = await _destinationFile(
      ownerUserId,
      bucket,
      storagePath,
      mimeType,
    );
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      _ensureGeneration(ownerUserId, expectedGeneration);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      await destination.setLastModified(DateTime.now());
      _scheduleTrim(ownerUserId);
      return destination.path;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  void _scheduleTrim(String ownerUserId) {
    _trimTimers.remove(ownerUserId)?.cancel();
    _trimTimers[ownerUserId] = Timer(trimDelay, () {
      _trimTimers.remove(ownerUserId);
      unawaited(
        _trim(ownerUserId).catchError((Object error, StackTrace stackTrace) {
          _talker?.handle(error, stackTrace, 'Media cache trim failed');
        }),
      );
    });
  }

  Future<void> _trim(String ownerUserId) async {
    final directory = await _userDirectory(ownerUserId);
    if (!await directory.exists()) return;
    final entries = await directory
        .list(recursive: true)
        .where((entity) => entity is File && !entity.path.endsWith('.tmp'))
        .cast<File>()
        .toList();
    final files = <({File file, int size, DateTime accessedAt})>[];
    for (final file in entries) {
      try {
        final stat = await file.stat();
        files.add((file: file, size: stat.size, accessedAt: stat.modified));
      } on FileSystemException {
        // Файл мог исчезнуть одновременно с очисткой диалога или logout.
      }
    }
    files.sort((left, right) => left.accessedAt.compareTo(right.accessedAt));
    var totalBytes = files.fold<int>(0, (sum, item) => sum + item.size);
    for (final item in files) {
      if (totalBytes <= maxCacheBytes) break;
      if (await item.file.exists()) await item.file.delete();
      _forgetResolvedPath(item.file.path);
      totalBytes -= item.size;
    }
  }

  Future<Directory> _userDirectory(String ownerUserId) async {
    final cache = await _cacheDirectoryProvider();
    return Directory(
      path.join(
        cache.path,
        'media_cache',
        _safeSegment(environment),
        _safeSegment(ownerUserId),
      ),
    );
  }

  Future<Directory> _legacyUserDirectory(String ownerUserId) async {
    final support = await _supportDirectoryProvider();
    return Directory(path.join(support.path, 'media_cache', ownerUserId));
  }

  Future<File> _destinationFile(
    String ownerUserId,
    String bucket,
    String storagePath,
    String? mimeType,
  ) async {
    final directory = Directory(
      path.join((await _userDirectory(ownerUserId)).path, bucket),
    );
    final extension = bucket == externalAvatarsBucket
        ? '.image'
        : _extension(storagePath, mimeType);
    final fileName =
        '${_uuid.v5(Namespace.url.value, '$bucket:$storagePath')}$extension';
    return File(path.join(directory.path, fileName));
  }

  Future<File> _legacyDestinationFile(
    String ownerUserId,
    String bucket,
    String storagePath,
    String? mimeType,
  ) async {
    final directory = Directory(
      path.join((await _legacyUserDirectory(ownerUserId)).path, bucket),
    );
    return File(
      path.join(directory.path, _fileName(bucket, storagePath, mimeType)),
    );
  }

  String _fileName(String bucket, String storagePath, String? mimeType) {
    final extension = bucket == externalAvatarsBucket
        ? '.image'
        : _extension(storagePath, mimeType);
    return '${_uuid.v5(Namespace.url.value, '$bucket:$storagePath')}$extension';
  }

  Future<void> _ensureMaintenance(String ownerUserId) {
    return _maintenance.putIfAbsent(ownerUserId, () async {
      final directory = await _userDirectory(ownerUserId);
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.tmp')) {
            try {
              await entity.delete();
            } on FileSystemException {
              // Параллельная запись уже могла завершить временный файл.
            }
          }
        }
      }
      await _trim(ownerUserId);
    });
  }

  int _generation(String ownerUserId) => _userGenerations[ownerUserId] ?? 0;

  void _ensureGeneration(String ownerUserId, int expectedGeneration) {
    if (_generation(ownerUserId) != expectedGeneration) {
      throw const FileSystemException('Media cache was cleared');
    }
  }

  void _validateFileSize(int size) {
    if (size > maxSingleFileBytes) {
      throw const FileSystemException('Media file is too large');
    }
  }

  String _safeSegment(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');

  String _extension(String storagePath, String? mimeType) {
    final uri = Uri.tryParse(storagePath);
    final sourcePath = uri?.path ?? storagePath;
    final sourceExtension = path.extension(sourcePath).toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(sourceExtension)) {
      return sourceExtension;
    }
    return switch (mimeType) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'audio/webm' => '.webm',
      'audio/ogg' => '.ogg',
      'audio/aac' => '.aac',
      'audio/mp4' => '.m4a',
      _ => '.bin',
    };
  }

  void dispose() {
    for (final timer in _trimTimers.values) {
      timer.cancel();
    }
    _trimTimers.clear();
    _resolvedPaths.clear();
    _maintenance.clear();
  }
}
