import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/repositories/blocks/blocks.dart';

void main() {
  test('keeps blacklists isolated between accounts', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = BlocklistCacheDataSource(database: database);

    await cache.replaceAll('owner-a', [_user('blocked-a')]);
    await cache.replaceAll('owner-b', [_user('blocked-b')]);

    expect((await cache.read('owner-a'))?.users.single.id, 'blocked-a');
    expect((await cache.read('owner-b'))?.users.single.id, 'blocked-b');
  });

  test('retains a completed empty blacklist snapshot', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = BlocklistCacheDataSource(database: database);

    expect(await cache.read('owner'), isNull);
    await cache.replaceAll('owner', const []);

    final snapshot = await cache.read('owner');
    expect(snapshot, isNotNull);
    expect(snapshot!.users, isEmpty);
  });

  test('updates the stored list after confirmed local mutations', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = BlocklistCacheDataSource(database: database);

    await cache.upsert('owner', _user('first'));
    await cache.upsert('owner', _user('second'));
    await cache.remove('owner', 'first');

    expect((await cache.read('owner'))?.users.single.id, 'second');
  });

  test('repairs a version 19 database missing the raw blacklist tables', () async {
    final directory = await Directory.systemTemp.createTemp('yap-blocklist');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');

    var database = AppDatabase.forTesting(NativeDatabase(file));
    await database.customStatement('SELECT 1');
    await database.close();

    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE cached_blocked_users');
    raw.execute('DROP TABLE cached_blocklist_snapshots');
    raw.close();

    database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);
    final cache = BlocklistCacheDataSource(database: database);
    await cache.replaceAll('owner', [_user('blocked')]);

    expect((await cache.read('owner'))?.users.single.id, 'blocked');
  });
}

BlockedUser _user(String id) => BlockedUser(
  id: id,
  username: 'username-$id',
  displayName: 'Name $id',
  blockedAt: DateTime.utc(2026, 9, 1),
);
