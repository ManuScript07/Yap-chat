// Protocol probe of the existing transport with passive connection observation.
// Real Supabase/Realtime SDK and loopback HTTP/WebSocket; no external service.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/repositories/realtime/realtime.dart';

final _reports = <Map<String, Object?>>[];
const _timing = bool.fromEnvironment('CONNECTION_BLACKHOLE_TIMING');

void main() {
  tearDownAll(
    () => File(
      'tmp/connection_signals_diagnosis.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_reports)),
  );

  test(
    'connection-only observer does not create a transport or fetch HTTP',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      p.listenConnections();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(p.events, isEmpty);
      expect(p.socketsCreated, 0);
      expect(p.client.getChannels(), isEmpty);
      expect(p.httpRequests, 0);
      p.report('observer-only');
    },
  );

  test(
    'late connection subscriber gets no replay and all listeners share the channel',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      final late = <bool>[];
      p.subscriptions.add(p.realtime.watchConnectionEvents().listen(late.add));
      for (var i = 0; i < 50; i++) {
        p.subscriptions.add(
          p.realtime.watchConversationEvents().listen((_) {}),
        );
        p.subscriptions.add(p.realtime.watchPresenceEvents().listen((_) {}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(p.events, [true]);
      expect(late, isEmpty);
      expect(p.socketsCreated, 1);
      expect(p.client.getChannels(), hasLength(1));
      expect(p.httpRequests, 0);
      p.report('late-listener-no-replay', {
        'late_events': late,
        'extra_listeners': 100,
      });
    },
  );

  test(
    'intentional pause and an unexpected close both publish false',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      await p.realtime.pause();
      await _until(() => p.events.last == false);
      expect(p.client.getChannels(), isEmpty);
      await p.realtime.resume();
      await _until(() => p.events.last == true && p.joins == 2);
      final beforeClose = p.events.length;
      await p.sockets.last.close(WebSocketStatus.goingAway, 'diagnostic drop');
      await _until(
        () => p.events.length > beforeClose && p.events.last == false,
      );
      expect(p.events.take(3), [true, false, true]);
      await p.realtime.pause();
      p.report('pause-versus-loss', {
        'channel_count_after_pause': p.client.getChannels().length,
      });
    },
  );

  for (final status in [403, 429, 500]) {
    test('HTTP $status does not emit a WebSocket connection failure', () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      p.status = status;
      await expectLater(
        p.remote.fetchChatListPage(),
        throwsA(isA<PostgrestException>()),
      );
      expect(p.events, [true]);
      expect(p.httpRequests, 1);
      expect(p.diagnostics.snapshot().rpc['get_chat_list_page']!.errors, 1);
      p.report('http-$status');
    });
  }

  test(
    'gateway 503 preserves a service status without closing the user channel',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      p.gateway = true;
      await expectLater(
        p.remote.fetchChatListPage(),
        throwsA(
          isA<PostgrestException>().having(
            (e) => e.code,
            'HTTP status code',
            '503',
          ),
        ),
      );
      expect(p.events, [true]);
      expect(p.httpRequests, 1);
      p.report('gateway-503-websocket-alive');
    },
  );

  test(
    'malformed page is a data failure after HTTP success, not channel loss',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      p.malformed = true;
      await expectLater(
        p.remote.fetchChatListPage(),
        throwsA(isA<FormatException>()),
      );
      expect(p.events, [true]);
      // The JSON page contract is validated after measureRpc has returned.
      expect(p.diagnostics.snapshot().rpc['get_chat_list_page']!.errors, 0);
      p.report('malformed-after-http-success');
    },
  );

  test(
    'HTTP transport can fail while the existing WebSocket remains subscribed',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      p.dropHttp = true;
      await expectLater(
        p.remote.fetchChatListPage(),
        throwsA(anyOf(isA<http.ClientException>(), isA<SocketException>())),
      );
      expect(p.events, [true]);
      expect(p.client.getChannels(), hasLength(1));
      expect(p.httpRequests, 1);
      p.report('http-lost-websocket-alive');
    },
  );

  test(
    'successful HTTP does not rejoin an intentionally paused realtime source',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      await p.realtime.pause();
      final events = List<bool>.of(p.events);
      expect((await p.remote.fetchChatListPage()).items, isEmpty);
      expect(p.events, events);
      expect(p.events.last, false);
      expect(p.client.getChannels(), isEmpty);
      p.report('http-healthy-websocket-paused');
    },
  );

  test(
    'private-channel access rejection emits false even with a live socket',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      p.rejectJoins = true;
      p.listenConnections();
      p.subscriptions.add(p.realtime.watchConversationEvents().listen((_) {}));
      await _until(() => p.events.isNotEmpty);
      expect(p.events.first, false);
      expect(p.transportAtEvent.first, true);
      expect(p.httpRequests, 0);
      await p.realtime.pause();
      p.report('join-access-rejection');
    },
  );

  test(
    'replacement account leaves the old topic and uses one new channel',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      final oldTopic = p.topics.last;
      await p.authenticate('22222222-2222-4222-8222-222222222222');
      await p.realtime.resume();
      await _until(() => p.events.last == true && p.joins == 2);
      expect(p.topics.last, isNot(oldTopic));
      expect(p.topics.last, contains('22222222-2222-4222-8222-222222222222'));
      expect(p.client.getChannels(), hasLength(1));
      p.report('account-topic-switch');
    },
  );

  test(
    'shared status restores API and Realtime independently without added traffic',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      expect(p.connection.value, false);
      p.gateway = true;
      await expectLater(
        p.remote.fetchChatListPage(),
        throwsA(isA<PostgrestException>()),
      );
      expect(p.connection.value, true);
      // Another joined channel event cannot repair the failed API lane.
      p.connection.realtimeSubscribed(p.connection.capture());
      expect(p.connection.value, true);
      p.gateway = false;
      await p.remote.fetchChatListPage();
      expect(p.connection.value, false);
      p.report('shared-api-recovery', {'rpc_requests': p.httpRequests});
      expect(p.httpRequests, 2);
      expect(p.socketsCreated, 1);
    },
  );

  test(
    'native loss is passive and surviving channel traffic restores its evidence',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      p.connection.reportNetworkAvailability(false);
      expect(p.connection.value, true);
      p.connection.reportNetworkAvailability(true);
      expect(p.connection.value, true);
      await p.remote.fetchChatListPage();
      expect(p.connection.value, true);
      // Use an actual valid user-channel event, not a synthetic status callback.
      p.sockets.last.add(
        jsonEncode([
          null,
          null,
          p.topics.last,
          'broadcast',
          {
            'event': 'changed',
            'payload': {'conversation_id': 'conversation', 'reason': 'insert'},
          },
        ]),
      );
      await _until(() => !p.connection.value);
      expect(p.httpRequests, 1);
      expect(p.socketsCreated, 1);
      expect(p.joins, 1);
      p.report('shared-native-loss-no-probe');
    },
  );

  test(
    'non-OK heartbeat recovers on the next SDK ACK without a channel rejoin',
    () async {
      final p = await _Probe.create(heartbeatIntervalMs: 100);
      addTearDown(p.close);
      p.rejectHeartbeats = 1;
      await p.join();
      await _until(() => p.connection.value);
      await _until(() => !p.connection.value);
      expect(p.joins, 1);
      expect(p.socketsCreated, 1);
      expect(p.httpRequests, 0);
      expect(p.events, [true]);
      p.report('shared-sdk-heartbeat-recovery');
    },
  );

  test(
    'a join completed during suspension survives a coalesced UI return',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      p.joinReplyDelay = const Duration(milliseconds: 80);
      final joining = p.join();
      await _until(() => p.joins == 1);
      p.connection.setForeground(false, suspended: true);
      await joining;
      p.connection.setForeground(true);
      expect(p.connection.value, false);
      expect(p.joins, 1);
      expect(p.socketsCreated, 1);
      expect(p.httpRequests, 0);
      p.report('shared-suspended-join-retained');
    },
  );

  test(
    'silent blackhole uses SDK heartbeat detection, not an immediate network signal',
    () async {
      final p = await _Probe.create();
      addTearDown(p.close);
      await p.join();
      expect(p.client.realtime.heartbeatIntervalMs, 25000);
      p.replyHeartbeats = false;
      final timer = Stopwatch()..start();
      await _until(() => p.heartbeats >= 1, const Duration(seconds: 32));
      expect(p.events, [true]);
      final stillReadyAt = timer.elapsedMilliseconds;
      await _until(() => p.events.last == false, const Duration(seconds: 38));
      final detectedAt = timer.elapsedMilliseconds;
      await p.realtime.pause();
      expect(detectedAt, greaterThan(stillReadyAt));
      p.report('default-heartbeat-blackhole', {
        'still_subscribed_ms': stillReadyAt,
        'failure_detected_ms': detectedAt,
      });
    },
    skip: !_timing,
    timeout: const Timeout(Duration(seconds: 80)),
  );
}

Future<void> _until(
  bool Function() predicate, [
  Duration timeout = const Duration(seconds: 5),
]) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed >= timeout) {
      fail('Timed out waiting for local SDK signal');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Probe {
  _Probe(this.server);
  final HttpServer server;
  late final SupabaseClient client;
  late final UserRealtimeDataSource realtime;
  late final ChatsRemoteDataSource remote;
  final diagnostics = AppDiagnostics(enabled: true);
  final account = AccountSessionController();
  late final AppConnectionStatus connection;
  final subscriptions = <StreamSubscription<dynamic>>[];
  final sockets = <WebSocket>[];
  final events = <bool>[];
  final transportAtEvent = <bool>[];
  final topics = <String>[];
  int socketsCreated = 0, joins = 0, httpRequests = 0, heartbeats = 0;
  int rejectHeartbeats = 0;
  Duration joinReplyDelay = Duration.zero;
  int status = 200;
  bool malformed = false, dropHttp = false, replyHeartbeats = true;
  bool rejectJoins = false;
  bool gateway = false;

  static Future<_Probe> create({int? heartbeatIntervalMs}) async {
    final p = _Probe(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    p.connection = AppConnectionStatus(
      accountSessionController: p.account,
      presentationDelay: Duration.zero,
    );
    final talker = Talker(settings: TalkerSettings(enabled: false));
    p.server.listen(p.handle);
    p.client = SupabaseClient(
      'http://127.0.0.1:${p.server.port}',
      'local-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions: const RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: Duration.zero,
      ),
    );
    if (heartbeatIntervalMs != null) {
      p.client.realtime.heartbeatIntervalMs = heartbeatIntervalMs;
    }
    p.connection.watchHeartbeats(p.client.realtime.onHeartbeat);
    p.realtime = UserRealtimeDataSource(
      client: p.client,
      talker: talker,
      diagnostics: p.diagnostics,
      connectionStatus: p.connection,
    );
    p.remote = ChatsRemoteDataSource(
      client: p.client,
      talker: talker,
      userRealtime: p.realtime,
      diagnostics: p.diagnostics,
      connectionStatus: p.connection,
    );
    await p.authenticate('11111111-1111-4111-8111-111111111111');
    return p;
  }

  Future<void> authenticate(String user) async {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    // Loopback protocol peer only; this token is never accepted by Supabase.
    final token =
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': user, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.local-signature';
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'loopback-only',
        'token_type': 'bearer',
        'user': {
          'id': user,
          'aud': 'authenticated',
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
    account.setAuthenticatedUser(user);
    connection.synchronizeSession();
  }

  void listenConnections() => subscriptions.add(
    realtime.watchConnectionEvents().listen((ready) {
      events.add(ready);
      transportAtEvent.add(client.realtime.isConnected);
    }),
  );
  Future<void> join() async {
    listenConnections();
    subscriptions.add(realtime.watchConversationEvents().listen((_) {}));
    await _until(() => events.lastOrNull == true);
  }

  Future<void> handle(HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socketsCreated++;
      socket.listen((raw) {
        final decoded = jsonDecode(raw as String);
        // Current SDK uses Phoenix v2's compact five-element wire frame.
        final message = decoded is List
            ? <String, dynamic>{
                'join_ref': decoded[0],
                'ref': decoded[1],
                'topic': decoded[2],
                'event': decoded[3],
                'payload': decoded[4],
              }
            : Map<String, dynamic>.from(decoded as Map);
        final event = message['event'];
        if (event == 'heartbeat') {
          heartbeats++;
          if (!replyHeartbeats) return;
        }
        if (event == 'phx_join') {
          joins++;
          topics.add(message['topic'] as String);
        }
        if (event == 'phx_join' ||
            event == 'phx_leave' ||
            event == 'heartbeat') {
          final reject =
              event == 'phx_join' && rejectJoins ||
              event == 'heartbeat' && rejectHeartbeats > 0;
          if (event == 'heartbeat' && rejectHeartbeats > 0) rejectHeartbeats--;
          final reply = <String, dynamic>{
            'event': 'phx_reply',
            'topic': message['topic'],
            'ref': message['ref'],
            'join_ref': message['join_ref'],
            'payload': {
              'status': reject ? 'error' : 'ok',
              'response': event == 'phx_join' && rejectJoins
                  ? {'reason': 'Unauthorized private channel'}
                  : {'postgres_changes': <Object>[]},
            },
          };
          void sendAck() {
            if (socket.readyState != WebSocket.open) return;
            try {
              socket.add(
                jsonEncode(
                  decoded is List
                      ? [
                          reply['join_ref'],
                          reply['ref'],
                          reply['topic'],
                          reply['event'],
                          reply['payload'],
                        ]
                      : reply,
                ),
              );
            } on StateError {
              // The real SDK can close its sink immediately after phx_leave.
              // A local reply racing that shutdown is not a protocol failure.
            }
          }

          if (event == 'phx_join' && joinReplyDelay > Duration.zero) {
            unawaited(Future<void>.delayed(joinReplyDelay, sendAck));
          } else {
            sendAck();
          }
        }
      });
      return;
    }
    httpRequests++;
    await utf8.decoder.bind(request).join();
    if (gateway) {
      request.response.statusCode = 503;
      request.response.write('upstream unavailable');
      await request.response.close();
      return;
    }
    if (dropHttp) {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(
        status == 200
            ? {
                'items': malformed ? 'invalid' : <Object>[],
                'query': '',
                'has_more': false,
                'next_cursor': null,
                'unread_total': 0,
              }
            : {
                'code': status == 429
                    ? 'PT429'
                    : status == 403
                    ? '42501'
                    : 'P0001',
                'message': status == 500
                    ? 'account_pending_deletion'
                    : 'diagnostic rejection',
              },
      ),
    );
    await request.response.close();
  }

  void report(String name, [Map<String, Object?> extra = const {}]) =>
      _reports.add({
        'name': name,
        'connection_events': List<bool>.of(events),
        'socket_connected_at_event': List<bool>.of(transportAtEvent),
        'http_requests': httpRequests,
        'websockets_created': socketsCreated,
        'active_channels': client.getChannels().length,
        'joins': joins,
        ...extra,
      });

  Future<void> close() async {
    connection.dispose();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await realtime.dispose();
    await client.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
