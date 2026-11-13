import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/app_diagnostics.dart';

void main() {
  test(
    'aggregates successful and failed RPCs without retaining payloads',
    () async {
      final diagnostics = AppDiagnostics(enabled: true);

      expect(await measureRpc(diagnostics, 'get_chats', () async => 1), 1);
      await expectLater(
        measureRpc<int>(
          diagnostics,
          'get_chats',
          () async => throw StateError('offline'),
        ),
        throwsStateError,
      );

      final snapshot = diagnostics.snapshot();
      final rpc = snapshot.rpc['get_chats'];
      expect(rpc?.calls, 2);
      expect(rpc?.errors, 1);
      expect(rpc?.totalMicroseconds, greaterThanOrEqualTo(0));
      expect(jsonEncode(snapshot.toJson()), isNot(contains('target_user_id')));
      expect(
        snapshot.toJson()['physical_realtime_transport'],
        'sdk_managed_not_counted',
      );
    },
  );

  test('tracks logical resources by lease and removes them idempotently', () {
    final diagnostics = AppDiagnostics(enabled: true);
    final channel = diagnostics.trackRealtimeChannel('user-realtime');
    final listener = diagnostics.trackLocalListener('chat-message-cache');

    expect(diagnostics.snapshot().activeRealtimeChannels, {'user-realtime': 1});
    expect(diagnostics.snapshot().activeLocalListeners, {
      'chat-message-cache': 1,
    });

    channel.dispose();
    channel.dispose();
    listener.dispose();
    expect(diagnostics.snapshot().activeRealtimeChannels, isEmpty);
    expect(diagnostics.snapshot().activeLocalListeners, isEmpty);
  });

  test('reads cache size only when explicitly requested', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final diagnostics = AppDiagnostics(enabled: true);

    expect(diagnostics.snapshot().cache, isNull);
    final cache = await diagnostics.refreshCacheSnapshot(
      database,
      ownerUserId: 'owner',
    );

    expect(cache.cachedMessageCount, 0);
    expect(cache.pendingOperationCount, 0);
    expect(cache.sqliteBytes, greaterThan(0));
    expect(diagnostics.snapshot().cache, cache);
  });

  test('disabled diagnostics does not accumulate data', () async {
    final diagnostics = AppDiagnostics(enabled: false);
    final channel = diagnostics.trackRealtimeChannel('user-realtime');
    await measureRpc(diagnostics, 'get_chats', () async => null);
    diagnostics.recordPresenceEvent(payloadBytes: 42);
    diagnostics.recordOutboxAttempt(manual: false);

    expect(diagnostics.snapshot().rpc, isEmpty);
    expect(diagnostics.snapshot().activeRealtimeChannels, isEmpty);
    expect(diagnostics.snapshot().presence.eventCount, 0);
    expect(diagnostics.snapshot().outbox.attempts, 0);
    channel.dispose();
  });
}
