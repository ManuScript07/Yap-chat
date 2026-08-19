import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:yap_chat/core/database/database.dart';

class MediaCacheService {
  MediaCacheService({
    required AppDatabase database,
    SupabaseClient? client,
    this.maxCacheBytes = 1024 * 1024 * 1024,
  }) : _database = database,
       _client = client;

  static const externalAvatarsBucket = 'external-avatars';

  final AppDatabase _database;
  final SupabaseClient? _client;
  final int maxCacheBytes;
  final Uuid _uuid = const Uuid();
  final Map<String, Future<String>> _activeWrites = {};
  final Queue<Completer<void>> _downloadQueue = Queue();
  final Map<String, Timer> _trimTimers = {};
  int _activeDownloadCount = 0;

  Future<String> cacheStorageFile({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    String? mimeType,
  }) {
    return _runOnce(ownerUserId, bucket, storagePath, () async {
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
      return _writeBytes(
        ownerUserId: ownerUserId,
        bucket: bucket,
        storagePath: storagePath,
        bytes: bytes,
        mimeType: mimeType,
      );
    });
  }

  Future<String> cacheNetworkFile({
    required String ownerUserId,
    required String url,
    String bucket = externalAvatarsBucket,
  }) {
    return _runOnce(ownerUserId, bucket, url, () async {
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
          final bytes = await consolidateHttpClientResponseBytes(response);
          return await _writeBytes(
            ownerUserId: ownerUserId,
            bucket: bucket,
            storagePath: url,
            bytes: bytes,
            mimeType: response.headers.contentType?.mimeType,
          );
        } finally {
          client.close(force: true);
        }
      });
    });
  }

  Future<String> storeBytes({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    required Uint8List bytes,
    String? mimeType,
  }) {
    return _runOnce(
      ownerUserId,
      bucket,
      storagePath,
      () => _writeBytes(
        ownerUserId: ownerUserId,
        bucket: bucket,
        storagePath: storagePath,
        bytes: bytes,
        mimeType: mimeType,
      ),
    );
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

  Future<void> clearUser(String ownerUserId) async {
    _trimTimers.remove(ownerUserId)?.cancel();
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

    final directory = await _userDirectory(ownerUserId);
    if (await directory.exists()) await directory.delete(recursive: true);

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
    });
  }

  Future<String> _runOnce(
    String ownerUserId,
    String bucket,
    String storagePath,
    Future<String> Function() operation,
  ) {
    final key = '$ownerUserId\u0000$bucket\u0000$storagePath';
    final active = _activeWrites[key];
    if (active != null) return active;
    final future = operation();
    _activeWrites[key] = future;
    return future.whenComplete(() {
      if (identical(_activeWrites[key], future)) _activeWrites.remove(key);
    });
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
    if (!await file.exists()) return null;
    await file.setLastModified(DateTime.now());
    return file.path;
  }

  Future<String> _writeBytes({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    if (bytes.isEmpty) throw const FileSystemException('Empty media file');
    final destination = await _destinationFile(
      ownerUserId,
      bucket,
      storagePath,
      mimeType,
    );
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
    await destination.setLastModified(DateTime.now());
    _scheduleTrim(ownerUserId);
    return destination.path;
  }

  void _scheduleTrim(String ownerUserId) {
    _trimTimers.remove(ownerUserId)?.cancel();
    _trimTimers[ownerUserId] = Timer(const Duration(seconds: 2), () {
      _trimTimers.remove(ownerUserId);
      unawaited(_trim(ownerUserId).catchError((_) {}));
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
      final stat = await file.stat();
      files.add((file: file, size: stat.size, accessedAt: stat.modified));
    }
    files.sort((left, right) => left.accessedAt.compareTo(right.accessedAt));
    var totalBytes = files.fold<int>(0, (sum, item) => sum + item.size);
    for (final item in files) {
      if (totalBytes <= maxCacheBytes) break;
      if (await item.file.exists()) await item.file.delete();
      totalBytes -= item.size;
    }
  }

  Future<Directory> _userDirectory(String ownerUserId) async {
    final support = await getApplicationSupportDirectory();
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
  }
}
