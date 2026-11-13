import 'package:drift/drift.dart'
    show QueryInterceptor, QueryExecutor, ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  test(
    'indexed peer cache reads one row among 10000, preserves avatars and privacy',
    () async {
      final trace = _Trace();
      final db = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(trace),
      );
      addTearDown(db.close);
      final media = _Media(db);
      final cache = ChatsCacheDataSource(
        database: db,
        userIdProvider: () => 'owner',
        mediaCache: media,
      );
      await cache.replaceAll([for (var i = 0; i < 10000; i++) _chat(i)]);
      final values = <Chat?>[];
      final sub = cache.watchByPeerId('peer-9001').listen(values.add);
      addTearDown(sub.cancel);
      await _until(() => values.isNotEmpty);
      expect(values.single?.id, '9001');
      expect(media.paths, 1);
      expect(trace.maxPeerRows, 1);
      final plan = await db.executor.runSelect(
        'EXPLAIN QUERY PLAN ${trace.sql}',
        trace.args,
      );
      expect(plan.toString(), contains('cached_chats_owner_peer_idx'));
      await cache.applySummaryBatch(
        {'8001'},
        [_chat(8001).copyWith(unreadCount: 42)],
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(values, hasLength(1));
      await cache.applySummaryBatch(
        {'9001'},
        [_chat(9001).copyWith(avatarStoragePath: '9001/new.jpg')],
      );
      await _until(
        () => values.last?.cachedAvatarPath == '/cache/9001/new.jpg',
      );
      await cache.applySummaryBatch(
        {'9001'},
        [_chat(9001, avatarStoragePath: null)],
      );
      await _until(() => values.last?.cachedAvatarPath == null);
      expect(values.last?.avatarUrl, isNull);
      await cache.applySummaryBatch(
        {'9001'},
        [_chat(9001).copyWith(blockedByPeer: true)],
      );
      await _until(() => values.last?.blockedByPeer == true);
      expect(values.last?.cachedAvatarPath, isNull);
      await cache.remove({'9001'});
      await _until(() => values.last == null);
      expect(trace.maxPeerRows, 1);
    },
  );
  test(
    'missing peer appears and observer stays scoped to its captured owner',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var owner = 'a';
      final cache = ChatsCacheDataSource(
        database: db,
        userIdProvider: () => owner,
      );
      final values = <Chat?>[];
      final sub = cache.watchByPeerId('peer-1').listen(values.add);
      addTearDown(sub.cancel);
      await _until(() => values.isNotEmpty);
      expect(values.single, isNull);
      owner = 'b';
      await cache.applySummaryBatch(
        {'1'},
        [_chat(1).copyWith(userName: 'Other account')],
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(values, hasLength(1));
      await cache.applySummaryBatch({'1'}, [_chat(1)], ownerUserId: 'a');
      await _until(() => values.last?.id == '1');
      expect(values.last?.userName, 'Peer 1');
      expect((await cache.readByPeerId('peer-1'))?.userName, 'Other account');
    },
  );
}

Chat _chat(int i, {String? avatarStoragePath = 'default'}) => Chat(
  id: '$i',
  peerId: 'peer-$i',
  userName: 'Peer $i',
  avatarStoragePath: avatarStoragePath == 'default'
      ? '$i/avatar.jpg'
      : avatarStoragePath,
  lastMessage: 'text',
  lastMessageTime: DateTime.utc(2026),
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
);
Future<void> _until(bool Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!check()) {
    if (DateTime.now().isAfter(end)) {
      fail('Peer stream did not emit');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Media extends MediaCacheService {
  _Media(AppDatabase db) : super(database: db);
  int paths = 0;
  @override
  Future<void> prepareLocalPaths() async {}
  @override
  String? localStorageFilePath({
    required String ownerUserId,
    required String bucket,
    required String storagePath,
    String? mimeType,
  }) {
    paths++;
    return '/cache/$storagePath';
  }
}

class _Trace extends QueryInterceptor {
  String sql = '';
  List<Object?> args = [];
  int maxPeerRows = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> parameters,
  ) async {
    final rows = await executor.runSelect(statement, parameters);
    if (statement.contains('"peer_id" = ?') &&
        !statement.startsWith('EXPLAIN')) {
      sql = statement;
      args = List.of(parameters);
      if (rows.length > maxPeerRows) maxPeerRows = rows.length;
    }
    return rows;
  }
}
