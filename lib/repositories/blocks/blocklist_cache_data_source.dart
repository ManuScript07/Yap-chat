import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/repositories/blocks/blocked_user.dart';

class BlocklistCacheSnapshot {
  const BlocklistCacheSnapshot({
    required this.users,
    required this.cachedAt,
  });

  final List<BlockedUser> users;
  final DateTime cachedAt;
}

/// Account-scoped persistent cache for the user's own blacklist.
///
/// Drift is the primary store. A compact SharedPreferences snapshot is kept as
/// a fallback because old application builds could have a versioned database
/// without the raw blacklist tables. Both stores contain the same data and a
/// completed empty list is represented by its own snapshot marker.
class BlocklistCacheDataSource {
  const BlocklistCacheDataSource({
    required AppDatabase database,
    SharedPreferences? preferences,
    this.namespace = 'default',
  }) : _database = database,
       _preferences = preferences;

  final AppDatabase _database;
  final SharedPreferences? _preferences;
  final String namespace;

  Future<BlocklistCacheSnapshot?> read(String ownerUserId) async {
    BlocklistCacheSnapshot? databaseSnapshot;
    try {
      databaseSnapshot = await _readDatabase(ownerUserId);
    } catch (_) {
      // The preferences snapshot remains available if SQLite is broken.
    }
    final preferencesSnapshot = _readPreferences(ownerUserId);
    if (databaseSnapshot == null) return preferencesSnapshot;
    if (preferencesSnapshot == null) return databaseSnapshot;
    return preferencesSnapshot.cachedAt.isAfter(databaseSnapshot.cachedAt)
        ? preferencesSnapshot
        : databaseSnapshot;
  }

  Future<void> replaceAll(
    String ownerUserId,
    List<BlockedUser> users,
  ) async {
    final cachedAt = DateTime.now();
    Object? databaseError;
    var saved = false;
    try {
      await _replaceAllInDatabase(ownerUserId, users, cachedAt);
      saved = true;
    } catch (error) {
      databaseError = error;
    }

    try {
      if (await _writePreferences(ownerUserId, users, cachedAt)) {
        saved = true;
      }
    } catch (_) {
      // A successful SQLite write is enough to retain the confirmed state.
    }
    if (!saved) throw databaseError ?? StateError('Could not cache blacklist');
  }

  Future<void> upsert(String ownerUserId, BlockedUser user) async {
    final current = await read(ownerUserId);
    final users = [
      user,
      ...?current?.users.where((item) => item.id != user.id),
    ];
    await replaceAll(ownerUserId, users);
  }

  Future<void> remove(String ownerUserId, String userId) async {
    final current = await read(ownerUserId);
    await replaceAll(
      ownerUserId,
      current?.users.where((user) => user.id != userId).toList() ?? const [],
    );
  }

  Future<void> clearUser(String ownerUserId) async {
    Object? databaseError;
    var cleared = false;
    try {
      await _ensureTables();
      await _database.transaction(() async {
        await _deleteRows(ownerUserId);
        await _database.customStatement(
          'DELETE FROM cached_blocklist_snapshots WHERE owner_user_id = ?',
          [_variable(ownerUserId)],
        );
      });
      cleared = true;
    } catch (error) {
      databaseError = error;
    }

    try {
      final preferences = _preferences;
      if (preferences != null &&
          await preferences.remove(_preferenceKey(ownerUserId))) {
        cleared = true;
      }
    } catch (_) {
      // The primary database deletion remains sufficient.
    }
    if (!cleared) throw databaseError ?? StateError('Could not clear blacklist');
  }

  Future<BlocklistCacheSnapshot?> _readDatabase(String ownerUserId) async {
    await _ensureTables();
    final snapshot = await _database
        .customSelect(
          '''
            SELECT cached_at_ms
            FROM cached_blocklist_snapshots
            WHERE owner_user_id = ?
          ''',
          variables: [_variable(ownerUserId)],
        )
        .getSingleOrNull();
    if (snapshot == null) return null;

    final users = await _database
        .customSelect(
          '''
            SELECT user_id, username, display_name, avatar_url,
              avatar_storage_path, blocked_at_ms
            FROM cached_blocked_users
            WHERE owner_user_id = ?
            ORDER BY blocked_at_ms DESC, user_id ASC
          ''',
          variables: [_variable(ownerUserId)],
        )
        .get();
    return BlocklistCacheSnapshot(
      users: List.unmodifiable(users.map(_mapUser)),
      cachedAt: _date(snapshot.read<int>('cached_at_ms')),
    );
  }

  Future<void> _replaceAllInDatabase(
    String ownerUserId,
    List<BlockedUser> users,
    DateTime cachedAt,
  ) async {
    await _ensureTables();
    await _database.transaction(() async {
      await _deleteRows(ownerUserId);
      for (final user in users) {
        await _upsert(ownerUserId, user);
      }
      await _writeSnapshot(ownerUserId, cachedAt);
    });
  }

  BlocklistCacheSnapshot? _readPreferences(String ownerUserId) {
    final raw = _preferences?.getString(_preferenceKey(ownerUserId));
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final cachedAtMs = value['cached_at_ms'];
      final encodedUsers = value['users'];
      if (cachedAtMs is! int || encodedUsers is! List) return null;
      final users = encodedUsers
          .whereType<Map<String, dynamic>>()
          .map(_mapPreferenceUser)
          .toList(growable: false);
      return BlocklistCacheSnapshot(
        users: List.unmodifiable(users),
        cachedAt: _date(cachedAtMs),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _writePreferences(
    String ownerUserId,
    List<BlockedUser> users,
    DateTime cachedAt,
  ) async {
    final preferences = _preferences;
    if (preferences == null) return false;
    final value = {
      'cached_at_ms': cachedAt.toUtc().millisecondsSinceEpoch,
      'users': users
          .map(
            (user) => {
              'id': user.id,
              'username': user.username,
              'display_name': user.displayName,
              'avatar_url': user.avatarUrl,
              'avatar_storage_path': user.avatarStoragePath,
              'blocked_at_ms': user.blockedAt.toUtc().millisecondsSinceEpoch,
            },
          )
          .toList(growable: false),
    };
    return preferences.setString(_preferenceKey(ownerUserId), jsonEncode(value));
  }

  String _preferenceKey(String ownerUserId) =>
      'blocklist.snapshot.$namespace.$ownerUserId';

  Future<void> _ensureTables() => _database.ensureBlocklistCacheTables();

  Future<void> _writeSnapshot(String ownerUserId, DateTime cachedAt) =>
      _database.customStatement(
        '''
          INSERT INTO cached_blocklist_snapshots (owner_user_id, cached_at_ms)
          VALUES (?, ?)
          ON CONFLICT(owner_user_id) DO UPDATE SET
            cached_at_ms = excluded.cached_at_ms
        ''',
        [
          _variable(ownerUserId),
          _variable(cachedAt.toUtc().millisecondsSinceEpoch),
        ],
      );

  Future<void> _deleteRows(String ownerUserId) => _database.customStatement(
    'DELETE FROM cached_blocked_users WHERE owner_user_id = ?',
    [_variable(ownerUserId)],
  );

  Future<void> _upsert(String ownerUserId, BlockedUser user) =>
      _database.customStatement(
        '''
          INSERT INTO cached_blocked_users (
            owner_user_id, user_id, username, display_name, avatar_url,
            avatar_storage_path, blocked_at_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(owner_user_id, user_id) DO UPDATE SET
            username = excluded.username,
            display_name = excluded.display_name,
            avatar_url = excluded.avatar_url,
            avatar_storage_path = excluded.avatar_storage_path,
            blocked_at_ms = excluded.blocked_at_ms
        ''',
        [
          _variable(ownerUserId),
          _variable(user.id),
          _variable(user.username),
          _variable(user.displayName),
          _variable(user.avatarUrl),
          _variable(user.avatarStoragePath),
          _variable(user.blockedAt.toUtc().millisecondsSinceEpoch),
        ],
      );

  BlockedUser _mapUser(dynamic row) => BlockedUser(
    id: row.read<String>('user_id'),
    username: row.read<String>('username'),
    displayName: row.read<String>('display_name'),
    avatarUrl: row.read<String?>('avatar_url'),
    avatarStoragePath: row.read<String?>('avatar_storage_path'),
    blockedAt: _date(row.read<int>('blocked_at_ms')),
  );

  BlockedUser _mapPreferenceUser(Map<String, dynamic> value) => BlockedUser(
    id: value['id'] as String? ?? '',
    username: value['username'] as String? ?? '',
    displayName: value['display_name'] as String? ?? '',
    avatarUrl: value['avatar_url'] as String?,
    avatarStoragePath: value['avatar_storage_path'] as String?,
    blockedAt: _date(value['blocked_at_ms'] as int? ?? 0),
  );

  DateTime _date(int millisecondsSinceEpoch) =>
      DateTime.fromMillisecondsSinceEpoch(
        millisecondsSinceEpoch,
        isUtc: true,
      ).toLocal();

  Variable<Object> _variable(Object? value) => Variable<Object>(value);
}
