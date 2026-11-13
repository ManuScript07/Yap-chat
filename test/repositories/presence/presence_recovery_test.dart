import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/features/presence/bloc/presence_cubit.dart';
import 'package:yap_chat/repositories/presence/presence_repository.dart';
import 'package:yap_chat/repositories/presence/presence_status_store.dart';
import 'package:yap_chat/repositories/realtime/user_realtime_data_source.dart';

// Regression tests use deterministic HTTP/Realtime fakes, no real accounts.
void main() {
  const owner = '10000000-0000-0000-0000-000000000001';
  const peer = '10000000-0000-0000-0000-000000000002';

  test(
    'snapshot offline does not stamp resume time; an event after unknown does',
    () async {
      final fixture = _Fixture();
      final cubit = PresenceCubit(repository: fixture.repository);
      await fixture.repository.connect(owner);
      fixture.store.record(peer, isOnline: true);
      await Future<void>.delayed(Duration.zero);
      var previous = cubit.state;
      fixture.store.applySnapshot(fixture.store.captureSnapshot(), {
        peer: false,
      });
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isConfirmedOffline(peer), isTrue);
      expect(cubit.state.hasNewOfflineEvent(peer, previous), isFalse);
      fixture.store.record(peer, isOnline: true);
      fixture.store.beginRevalidation(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      previous = cubit.state;
      expect(previous.isOnline(peer), isFalse);
      fixture.realtime.presence.add(
        const UserPresenceRealtimeEvent(userId: peer, isOnline: false),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.hasNewOfflineEvent(peer, previous), isTrue);
      await cubit.close();
      await fixture.close();
    },
  );

  test(
    'long background preserves only last-known data until bounded recovery',
    () async {
      final clock = FakeAsync();
      final fixture = clock.run((_) => _Fixture());
      Future<void> settle(Future<void> Function() action) =>
          _settleClock(clock, clock.run((_) => action()));
      await settle(() => fixture.repository.setWatchScope('profile', [peer]));
      await settle(() => fixture.repository.connect(owner));
      expect(fixture.store.onlineUserIds, {peer});
      await settle(fixture.repository.suspend);
      clock.elapse(const Duration(hours: 1));
      expect(fixture.store.onlineUserIds, {peer});
      expect(fixture.heartbeatCalls, 1);
      final delayed = Completer<http.Response>();
      fixture.nextScopeResponse = delayed;
      fixture.scopeStarted = Completer<void>();
      final reconnect = clock.run((_) => fixture.repository.connect(owner));
      await _settleClock(clock, fixture.scopeStarted!.future);
      expect(fixture.scopeCalls, 2);
      expect(fixture.store.onlineUserIds, {peer});
      clock.elapse(const Duration(seconds: 16));
      expect(fixture.store.onlineUserIds, isEmpty);
      delayed.complete(_snapshot(peer, true));
      await _settleClock(clock, reconnect);
      expect(fixture.store.onlineUserIds, isEmpty);
      await settle(fixture.close);
    },
  );

  test('old heartbeat cannot confirm a failed new-account session', () async {
    final clock = FakeAsync();
    final fixture = clock.run((_) => _Fixture());
    Future<void> settle(Future<void> Function() action) =>
        _settleClock(clock, clock.run((_) => action()));
    await settle(() => fixture.repository.connect(owner));
    final oldHeartbeat = Completer<http.Response>();
    fixture.nextHeartbeatResponse = oldHeartbeat;
    fixture.heartbeatStarted = Completer<void>();
    clock.elapse(const Duration(seconds: 30));
    await _settleClock(clock, fixture.heartbeatStarted!.future);
    expect(fixture.heartbeatCalls, 2);
    await settle(fixture.repository.suspend);
    fixture.failNextHeartbeat = true;
    await settle(() => fixture.repository.connect(peer));
    expect(fixture.heartbeatCalls, 3);
    oldHeartbeat.complete(http.Response('', 204));
    await settle(() async {});
    await settle(() => fixture.repository.setWatchScope('profile', [owner]));
    expect(fixture.scopeCalls, 0);
    fixture.scopeStarted = Completer<void>();
    clock.elapse(const Duration(seconds: 30));
    await _settleClock(clock, fixture.scopeStarted!.future);
    await settle(() async {});
    expect(fixture.scopeCalls, 1);
    expect(fixture.store.onlineUserIds, {owner});
    await settle(fixture.close);
  });

  test('queued events addressed to the previous account are ignored', () async {
    final fixture = _Fixture();
    await fixture.repository.connect(peer);
    fixture.realtime.presence.add(
      const UserPresenceRealtimeEvent(
        userId: owner,
        isOnline: true,
        viewerUserId: owner,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(fixture.store.onlineUserIds, isEmpty);
    fixture.realtime.presence.add(
      const UserPresenceRealtimeEvent(
        userId: owner,
        isOnline: true,
        viewerUserId: peer,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(fixture.store.onlineUserIds, {owner});
    await fixture.close();
  });

  test(
    'duplicate connect and unchanged scope do not add RPCs or listeners',
    () async {
      final fixture = _Fixture();
      await fixture.repository.setWatchScope('chat:test', [peer]);
      await fixture.repository.connect(owner);
      await fixture.repository.connect(owner);
      await fixture.repository.setWatchScope('chat:test', [peer]);
      expect(fixture.scopeCalls, 1);
      expect(fixture.heartbeatCalls, 1);
      expect(fixture.realtime.resumeCalls, 1);
      expect(fixture.realtime.presence.hasListener, isTrue);
      await fixture.repository.suspend();
      expect(fixture.realtime.presence.hasListener, isFalse);
      expect(fixture.realtime.connections.hasListener, isFalse);
      await fixture.close();
    },
  );

  test(
    'confirmed offline event is immediate and an old snapshot cannot revive it',
    () async {
      final fixture = _Fixture();
      await fixture.repository.setWatchScope('chat:test', [peer]);
      await fixture.repository.connect(owner);
      final delayed = Completer<http.Response>();
      fixture.nextScopeResponse = delayed;
      fixture.realtime.connections.add(true);
      await Future<void>.delayed(Duration.zero);
      fixture.realtime.presence.add(
        const UserPresenceRealtimeEvent(userId: peer, isOnline: false),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.store.onlineUserIds, isEmpty);
      expect(
        (await fixture.store.watchSnapshots().first).confirmedOfflineUserIds,
        {peer},
      );
      delayed.complete(_snapshot(peer, true));
      await Future<void>.delayed(Duration.zero);
      expect(fixture.store.onlineUserIds, isEmpty);
      expect(fixture.heartbeatCalls, 1);
      await fixture.close();
    },
  );

  test(
    'scope changes coalesce and a removed scope cannot restore old statuses',
    () async {
      final fixture = _Fixture();
      await fixture.repository.connect(owner);
      final delayed = Completer<http.Response>();
      fixture.nextScopeResponse = delayed;
      final oldScope = fixture.repository.setWatchScope('profile', [peer]);
      await Future<void>.delayed(Duration.zero);
      final removal = fixture.repository.removeWatchScope('profile');
      final replacement = fixture.repository.setWatchScope('profile', [owner]);
      delayed.complete(_snapshot(peer, true));
      await Future.wait([oldScope, removal, replacement]);
      expect(fixture.scopeCalls, 2);
      expect(fixture.store.onlineUserIds, isEmpty);
      expect(fixture.scopeBodies.last['target_user_ids'], isEmpty);
      await fixture.close();
    },
  );

  test('switching accounts clears old peers and rejects a late RPC', () async {
    final fixture = _Fixture();
    await fixture.repository.connect(owner);
    fixture.store.record(peer, isOnline: true);
    final delayed = Completer<http.Response>();
    fixture.nextScopeResponse = delayed;
    final oldScope = fixture.repository.setWatchScope('profile', [peer]);
    await Future<void>.delayed(Duration.zero);
    await fixture.repository.disconnect();
    await fixture.repository.connect(peer);
    delayed.complete(_snapshot(peer, true));
    await oldScope;
    final snapshot = await fixture.store.watchSnapshots().first;
    expect(snapshot.onlineUserIds, isEmpty);
    expect(snapshot.confirmedOfflineUserIds, isEmpty);
    expect(fixture.scopeCalls, 1);
    await fixture.close();
  });

  test(
    'rejoin snapshot catches a missed offline change without another heartbeat',
    () async {
      final fixture = _Fixture();
      await fixture.repository.setWatchScope('profile', [peer]);
      await fixture.repository.connect(owner);
      final delayed = Completer<http.Response>();
      fixture.nextScopeResponse = delayed;
      fixture.realtime.connections.add(false);
      fixture.realtime.connections.add(true);
      await Future<void>.delayed(Duration.zero);
      delayed.complete(_snapshot(peer, false));
      await Future<void>.delayed(Duration.zero);
      expect(fixture.store.onlineUserIds, isEmpty);
      expect(fixture.scopeCalls, 2);
      expect(fixture.heartbeatCalls, 1);
      await fixture.close();
    },
  );

  test(
    'foreground recovery keeps peer online during a delayed snapshot',
    () async {
      final fixture = _Fixture();
      final states = <bool>[];
      final cubit = PresenceCubit(repository: fixture.repository);
      final subscription = cubit.stream.listen(
        (state) => states.add(state.isOnline(peer)),
      );
      await fixture.repository.setWatchScope('chat:test', [peer]);
      await fixture.repository.connect(owner);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isOnline(peer), isTrue);
      states.clear();

      await fixture.repository.suspend();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isOnline(peer), isTrue);
      final delayed = Completer<http.Response>();
      fixture.nextScopeResponse = delayed;
      final reconnect = fixture.repository.connect(owner);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isOnline(peer), isTrue);
      delayed.complete(_snapshot(peer, true));
      await reconnect;
      await Future<void>.delayed(Duration.zero);
      expect(states, isEmpty);
      expect(fixture.scopeCalls, 2);
      await subscription.cancel();
      await cubit.close();
      await fixture.close();
    },
  );

  test(
    'a delayed snapshot cannot overwrite a newer realtime online event',
    () async {
      final fixture = _Fixture();
      await fixture.repository.connect(owner);
      final delayed = Completer<http.Response>();
      fixture.nextScopeResponse = delayed;
      final sync = fixture.repository.setWatchScope('chat:test', [peer]);
      await Future<void>.delayed(Duration.zero);
      fixture.realtime.presence.add(
        const UserPresenceRealtimeEvent(userId: peer, isOnline: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.store.onlineUserIds, contains(peer));
      delayed.complete(_snapshot(peer, false));
      await sync;
      expect(fixture.store.onlineUserIds, contains(peer));
      await fixture.close();
    },
  );

  test('channel rejoin refreshes the existing presence audience', () async {
    final fixture = _Fixture();
    await fixture.repository.setWatchScope('chat:test', [peer]);
    await fixture.repository.connect(owner);
    expect(fixture.scopeCalls, 1);
    fixture.realtime.connections.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.scopeCalls, 2);
    expect(fixture.store.onlineUserIds, contains(peer));
    await fixture.close();
  });

  test('an old-session sync cannot suppress the new-session sync', () async {
    final fixture = _Fixture();
    await fixture.repository.connect(owner);
    final delayed = Completer<http.Response>();
    fixture.nextScopeResponse = delayed;
    final oldSync = fixture.repository.setWatchScope('chat:test', [peer]);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.scopeCalls, 1);
    await fixture.repository.suspend();
    final reconnect = fixture.repository.connect(owner);
    await Future<void>.delayed(Duration.zero);
    delayed.complete(_snapshot(peer, true));
    await oldSync;
    await reconnect;
    expect(fixture.scopeCalls, 2);
    expect(fixture.store.onlineUserIds, contains(peer));
    await fixture.close();
  });
}

// SDK stream cancellation / isolate startup may finish in the parent zone.
// Drive that event loop without advancing the repository's controlled timers.
Future<void> _settleClock(FakeAsync clock, Future<void> operation) async {
  var completed = false;
  Object? failure;
  clock.run(
    (_) => operation.then(
      (_) => completed = true,
      onError: (Object error) {
        failure = error;
        completed = true;
      },
    ),
  );
  for (var turn = 0; turn < 100 && !completed; turn++) {
    clock.flushMicrotasks();
    await Future<void>.delayed(Duration.zero);
  }
  clock.flushMicrotasks();
  expect(completed, isTrue, reason: 'Controlled operation did not settle');
  if (failure != null) throw failure!;
}

http.Response _snapshot(String peer, bool online) => http.Response(
  jsonEncode([
    {'target_user_id': peer, 'is_online': online},
  ]),
  200,
  headers: {'content-type': 'application/json'},
);

class _Fixture {
  _Fixture() {
    client = SupabaseClient(
      'http://localhost:54321',
      'diagnostic-only',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/set_my_presence_watch_scope')) {
          scopeCalls++;
          if (scopeStarted != null && !scopeStarted!.isCompleted) {
            scopeStarted!.complete();
          }
          scopeBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          final delayed = nextScopeResponse;
          nextScopeResponse = null;
          if (delayed != null) {
            final response = await delayed.future;
            return http.Response(
              response.body,
              response.statusCode,
              headers: response.headers,
              request: request,
            );
          }
          final params = jsonDecode(request.body) as Map<String, dynamic>;
          final ids = params['target_user_ids'] as List;
          return http.Response(
            jsonEncode([
              for (final id in ids) {'target_user_id': id, 'is_online': true},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path.endsWith('/touch_my_presence_session')) {
          heartbeatCalls++;
          if (heartbeatStarted != null && !heartbeatStarted!.isCompleted) {
            heartbeatStarted!.complete();
          }
          final delayed = nextHeartbeatResponse;
          nextHeartbeatResponse = null;
          if (delayed != null) {
            final response = await delayed.future;
            return http.Response(
              response.body,
              response.statusCode,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (failNextHeartbeat) {
            failNextHeartbeat = false;
            return http.Response(
              '{"message":"test failure","code":"P0001"}',
              500,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
        }
        return http.Response(
          '',
          204,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    realtime = _FakeRealtime(client);
    repository = PresenceRepository(
      client: client,
      talker: Talker(),
      userRealtime: realtime,
      statusStore: store,
    );
  }
  final store = PresenceStatusStore();
  late final SupabaseClient client;
  late final _FakeRealtime realtime;
  late final PresenceRepository repository;
  Completer<http.Response>? nextScopeResponse;
  Completer<http.Response>? nextHeartbeatResponse;
  bool failNextHeartbeat = false;
  Completer<void>? scopeStarted;
  Completer<void>? heartbeatStarted;
  int scopeCalls = 0;
  int heartbeatCalls = 0;
  final scopeBodies = <Map<String, dynamic>>[];

  Future<void> close() async {
    await repository.disconnect();
    await realtime.presence.close();
    await realtime.conversations.close();
    await realtime.connections.close();
    await realtime.dispose();
    await store.dispose();
    await client.dispose();
  }
}

class _FakeRealtime extends UserRealtimeDataSource {
  _FakeRealtime(SupabaseClient client)
    : super(client: client, talker: Talker());
  final connections = StreamController<bool>.broadcast();
  @override
  Stream<bool> watchConnectionEvents() => connections.stream;
  final presence = StreamController<UserPresenceRealtimeEvent>.broadcast();
  final conversations =
      StreamController<UserConversationRealtimeEvent>.broadcast();
  @override
  Future<void> resume() async {
    resumeCalls++;
  }

  int resumeCalls = 0;
  @override
  Stream<UserPresenceRealtimeEvent> watchPresenceEvents() => presence.stream;
  @override
  Stream<UserConversationRealtimeEvent> watchConversationEvents() =>
      conversations.stream;
}
