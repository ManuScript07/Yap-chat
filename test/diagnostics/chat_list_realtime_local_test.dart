// Opt-in real SDK + local Docker test. Keys remain in memory only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:uuid/uuid.dart';
// Inject the transport without changing production dependencies.
// ignore: depend_on_referenced_packages
import 'package:web_socket_channel/io.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/repositories/friends/friends.dart';
import 'package:yap_chat/repositories/realtime/realtime.dart';

const _enabled = bool.fromEnvironment('CHAT_LIST_REALTIME_LOCAL');

void main() {
  test(
    'many chat/presence listeners and friends share one real SDK socket',
    () async {
      final auth = await _env('supabase_auth_Yap_chat');
      final storage = await _env('supabase_storage_Yap_chat');
      final user = const Uuid().v4();
      await _sql(
        "insert into auth.users(id,is_sso_user,is_anonymous,raw_user_meta_data) values('$user',false,false,'{}');",
      );
      var socketsCreated = 0;
      final client = SupabaseClient(
        'http://127.0.0.1:54321',
        storage['ANON_KEY']!,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        realtimeClientOptions: RealtimeClientOptions(
          disconnectOnEmptyChannelsAfter: Duration.zero,
          transport: (url, headers) {
            socketsCreated++;
            return IOWebSocketChannel.connect(url, headers: headers);
          },
        ),
      );
      final talker = Talker(settings: TalkerSettings(enabled: false));
      final realtime = UserRealtimeDataSource(client: client, talker: talker);
      final remote = ChatsRemoteDataSource(
        client: client,
        talker: talker,
        userRealtime: realtime,
      );
      final friends = FriendsRemoteDataSource(client: client, talker: talker);
      final subscriptions = <StreamSubscription<dynamic>>[];
      try {
        await client.auth.setInitialSession(
          jsonEncode({
            'access_token': _jwt(user, auth['GOTRUE_JWT_SECRET']!),
            'refresh_token': 'local-diagnostic',
            'token_type': 'bearer',
            'user': {
              'id': user,
              'aud': 'authenticated',
              'user_metadata': <String, dynamic>{},
            },
          }),
        );
        var joined = false;
        subscriptions.add(
          realtime.watchConnectionEvents().listen((value) => joined = value),
        );
        final received = <String>{};
        subscriptions.add(
          remote.watchChanges().listen((event) {
            if (event.conversationId != null) {
              received.add(event.conversationId!);
            }
          }),
        );
        await _until(() => joined);
        expect(client.getChannels(), hasLength(1));
        expect(socketsCreated, 1);
        // The production API has one user stream, never a per-conversation channel.
        for (var i = 0; i < 1000; i++) {
          subscriptions.add(remote.watchChanges().listen((_) {}));
        }
        subscriptions.add(realtime.watchPresenceEvents().listen((_) {}));
        var friendsJoined = false;
        subscriptions.add(
          friends.watchChanges().listen((_) => friendsJoined = true),
        );
        await _until(() => friendsJoined);
        expect(client.getChannels(), hasLength(2));
        expect(socketsCreated, 1);
        final ids = [for (var i = 0; i < 100; i++) const Uuid().v4()];
        await _sql(
          'begin;${ids.map((id) => "select realtime.send(jsonb_build_object('conversation_id','$id','reason','insert'),'changed','user:$user:chats',true);").join('\n')}commit;',
        );
        await _until(() => received.length == ids.length);
        expect(received, ids.toSet());
        expect(socketsCreated, 1);
        final report = {
          'chat_listeners': 1001,
          'distinct_chat_events': received.length,
          'logical_channels': client.getChannels().length,
          'physical_websockets_created': socketsCreated,
        };
        File(
          'tmp/chat_list_realtime_local.json',
        ).writeAsStringSync(jsonEncode(report));
        // ignore: avoid_print
        print('CHAT_LIST_REALTIME_DIAGNOSTIC ${jsonEncode(report)}');
      } finally {
        for (final sub in subscriptions) {
          await sub.cancel();
        }
        await friends.pauseChanges();
        await realtime.dispose();
        await client.dispose();
        await _sql(
          "begin;delete from public.profiles where id='$user';delete from auth.users where id='$user';commit;",
        );
        expect(
          await _sql("select count(*) from auth.users where id='$user';"),
          '0',
        );
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

Future<Map<String, String>> _env(String container) async {
  final r = await Process.run('docker', [
    'inspect',
    '--format',
    '{{json .Config.Env}}',
    container,
  ]);
  expect(r.exitCode, 0, reason: 'Local Docker container unavailable');
  return {
    for (final s in (jsonDecode(r.stdout as String) as List).cast<String>())
      s.substring(0, s.indexOf('=')): s.substring(s.indexOf('=') + 1),
  };
}

Future<String> _sql(String sql) async {
  final p = await Process.start('docker', [
    'exec',
    '-i',
    'supabase_db_Yap_chat',
    'psql',
    '-X',
    '-U',
    'postgres',
    '-d',
    'postgres',
    '-v',
    'ON_ERROR_STOP=1',
    '-qAt',
  ]);
  final out = utf8.decodeStream(p.stdout), err = utf8.decodeStream(p.stderr);
  p.stdin.write("set statement_timeout='15s';\n$sql");
  await p.stdin.close();
  final code = await p.exitCode;
  final error = await err;
  expect(code, 0, reason: error);
  return (await out).trim();
}

String _jwt(String user, String secret) {
  String encode(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  final data =
      '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': user, 'role': 'authenticated', 'aud': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300})}';
  return '$data.${base64Url.encode(Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(data)).bytes).replaceAll('=', '')}';
}

Future<void> _until(bool Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!check()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Missing local Realtime event');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
