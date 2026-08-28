import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// Durable queue for Storage objects whose profile reference may have changed.
///
/// A queued path is deleted only after an authoritative profile response proves
/// that it is no longer referenced. This also covers process termination after
/// the RPC succeeds but before the client can remove the old object.
class AvatarDeletionQueue {
  AvatarDeletionQueue({
    required SharedPreferences preferences,
    required String environment,
    required Talker talker,
  }) : _preferences = preferences,
       _environment = environment,
       _talker = talker;

  final SharedPreferences _preferences;
  final String _environment;
  final Talker _talker;
  final Map<String, Future<void>> _ownerOperations = {};

  Future<void> enqueue(String ownerUserId, Iterable<String> storagePaths) {
    return _serialize(ownerUserId, () async {
      final paths = _read(ownerUserId)..addAll(storagePaths);
      await _write(ownerUserId, paths);
    });
  }

  Future<void> reconcile({
    required String ownerUserId,
    required Set<String> referencedPaths,
    required Future<void> Function(String storagePath) delete,
  }) {
    return _serialize(ownerUserId, () async {
      final remaining = _read(ownerUserId);
      if (remaining.isEmpty) return;
      for (final storagePath in remaining.toList(growable: false)) {
        if (referencedPaths.contains(storagePath)) {
          remaining.remove(storagePath);
          continue;
        }
        try {
          await delete(storagePath);
          remaining.remove(storagePath);
        } catch (error, stackTrace) {
          _talker.handle(
            error,
            stackTrace,
            'Queued profile photo deletion failed',
          );
        }
      }
      await _write(ownerUserId, remaining);
    });
  }

  Set<String> _read(String ownerUserId) =>
      (_preferences.getStringList(_key(ownerUserId)) ?? const <String>[])
          .toSet();

  Future<void> _write(String ownerUserId, Set<String> paths) {
    if (paths.isEmpty) return _preferences.remove(_key(ownerUserId));
    final sorted = paths.toList()..sort();
    return _preferences.setStringList(_key(ownerUserId), sorted);
  }

  Future<void> _serialize(
    String ownerUserId,
    Future<void> Function() operation,
  ) {
    final previous = _ownerOperations[ownerUserId] ?? Future<void>.value();
    final current = previous.catchError((_) {}).then((_) => operation());
    _ownerOperations[ownerUserId] = current;
    return current.whenComplete(() {
      if (identical(_ownerOperations[ownerUserId], current)) {
        _ownerOperations.remove(ownerUserId);
      }
    });
  }

  String _key(String ownerUserId) =>
      'profile_avatar_deletions.${_safe(_environment)}.${_safe(ownerUserId)}';

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
}
