import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  for (final (code, message, limited) in [
    ('P0001', 'chat_limit_reached', true),
    ('42501', 'chat_limit_reached', false),
    ('P0001', 'account_banned', false),
    ('P0001', 'peer_blocked', false),
  ]) {
    test(
      'creation maps only exact chat limit refusal: $code/$message',
      () async {
        final h = await _Harness.create(0);
        addTearDown(h.dispose);
        final gate = h.remote.creationGate = Completer<String>();
        final creation = h.repository.ensureDirectChat('peer-new');
        final check = expectLater(
          creation,
          throwsA(
            limited
                ? isA<ChatLimitReachedException>()
                : isA<PostgrestException>(),
          ),
        );
        await _until(() => h.remote.createCalls == 1);
        gate.completeError(PostgrestException(message: message, code: code));
        await check;
        expect(await h.cache.read(), isEmpty);
        expect(h.remote.batches, isEmpty);
        h.remote.creationGate = null;
        expect((await h.repository.ensureDirectChat('peer-new')).id, 'created');
        expect(h.remote.createCalls, 2);
      },
    );
  }
  test('cached ID/peer lookups and one-row stream stay offline', () async {
    final h = await _Harness.create(1000);
    addTearDown(h.dispose);
    expect((await h.repository.getChatById(' 4 '))?.id, '4');
    expect((await h.repository.getCachedChatByPeerId('peer-4'))?.id, '4');
    expect(await h.repository.getChatById(' '), isNull);
    final watched = await h.repository.watchChat('4').first;
    expect(watched?.id, '4');
    expect(h.remote.fullCalls, 0);
    expect(h.remote.batches, isEmpty);
    expect(h.remote.peerCalls, 0);
  });

  test(
    '20 identical misses share one addressed request, not 1000 summaries',
    () async {
      final h = await _Harness.create(1000);
      addTearDown(h.dispose);
      h.remote.server['old'] = _chat('old');
      final gate = h.remote.nextIdGate = Completer<List<Chat>>();
      final reads = [
        for (var i = 0; i < 20; i++) h.repository.getChatById('old'),
      ];
      await _until(() => h.remote.batches.length == 1);
      gate.complete([_chat('old')]);
      expect(
        (await Future.wait(reads)).every((chat) => chat?.id == 'old'),
        true,
      );
      expect(h.remote.batches, [
        {'old'},
      ]);
      expect(h.remote.fullCalls, 0);
      expect(await h.cache.read(), hasLength(1001));
      expect(await h.database.select(h.database.cachedMessages).get(), isEmpty);
    },
  );

  test(
    'different known-ID misses run serially and a failure does not poison the lane',
    () async {
      final h = await _Harness.create(0);
      addTearDown(h.dispose);
      for (var i = 0; i < 12; i++) {
        h.remote.server['$i'] = _chat('$i');
      }
      final gate = h.remote.nextIdGate = Completer<List<Chat>>();
      final reads = [
        for (var i = 0; i < 12; i++) h.repository.getChatById('$i'),
      ];
      await _until(() => h.remote.batches.length == 1);
      gate.completeError(StateError('offline'));
      final result = await Future.wait(reads);
      expect(result.first, isNull);
      expect(result.skip(1).every((e) => e != null), true);
      expect(h.remote.maximumIds, 1);
      expect(h.remote.fullCalls, 0);
      expect((await h.repository.getChatById('0'))?.id, '0');
      expect(h.remote.batches, hasLength(13));
    },
  );

  test(
    'lookup bypasses stalled full read and older full snapshot cannot drop its result',
    () async {
      final h = await _Harness.create(2);
      addTearDown(h.dispose);
      h.remote.server['old'] = _chat('old');
      final gate = h.remote.nextFullGate = Completer<List<Chat>>();
      final full = h.repository.getChats();
      await _until(() => h.remote.fullCalls == 1);
      expect(
        (await h.repository
                .getChatById('old')
                .timeout(const Duration(seconds: 1)))
            ?.id,
        'old',
      );
      gate.complete(h.remote.head);
      await full;
      expect((await h.cache.readById('old'))?.id, 'old');
      expect(h.remote.batches, [
        {'old'},
      ]);
    },
  );

  test(
    'open chat outside the list survives refresh and absence is verified by ID',
    () async {
      final h = await _Harness.create(1000);
      addTearDown(h.dispose);
      h.remote.server['old'] = _chat('old');
      await h.listen();
      await h.repository.getChatById('old');
      h.sync.openConversation('old');
      final before = h.remote.batches.length;
      await h.repository.getChats();
      expect(await h.cache.readById('old'), isNotNull);
      await _until(() => h.remote.batches.length == before + 1);
      expect(await h.cache.readById('old'), isNotNull);
      h.remote.server.remove('old');
      await h.repository.getChats();
      await _until(() async => await h.cache.readById('old') == null);
      expect(await h.cache.read(), hasLength(1000));
      h.sync.closeConversation('old', session: h.account.capture());
    },
  );

  test('pending local deletion wins over a late ID lookup', () async {
    final h = await _Harness.create(0);
    addTearDown(h.dispose);
    final gate = h.remote.nextIdGate = Completer<List<Chat>>();
    final lookup = h.repository.getChatById('old');
    await _until(() => h.remote.batches.isNotEmpty);
    await h.account.commit(
      h.account.capture(),
      () => h.messages.putPendingChatDeletion(
        id: 'delete',
        chatId: 'old',
        clearedAt: DateTime.now().toUtc(),
        ownerUserId: 'owner',
      ),
    );
    gate.complete([_chat('old')]);
    expect(await lookup, isNull);
    expect(await h.cache.read(), isEmpty);
  });

  test(
    'incoming event during an uncached push lookup gets one bounded fresh read',
    () async {
      final h = await _Harness.create(2);
      addTearDown(h.dispose);
      await h.listen();
      h.remote.server['old'] = _chat('old');
      final gate = h.remote.nextIdGate = Completer<List<Chat>>();
      final lookup = h.repository.getChatById('old');
      await _until(() => h.remote.batches.length == 1);
      h.remote.changes.add(
        const ConversationChange(conversationId: 'old', reason: 'insert'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete([_chat('old')]);
      expect((await lookup)?.id, 'old');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(h.remote.batches, [
        {'old'},
        {'old'},
      ]);
      expect(h.remote.fullCalls, 1);
    },
  );

  test(
    'logout/relogin rejects a late result even for the same account',
    () async {
      final h = await _Harness.create(0);
      addTearDown(h.dispose);
      final gate = h.remote.nextIdGate = Completer<List<Chat>>();
      final lookup = h.repository.getChatById('old');
      await _until(() => h.remote.batches.isNotEmpty);
      h.account.setAuthenticatedUser(null);
      h.account.setAuthenticatedUser('owner');
      gate.complete([_chat('old')]);
      expect(await lookup, isNull);
      expect(await h.cache.read(ownerUserId: 'owner'), isEmpty);
    },
  );

  test(
    'event during final pending-delete check is included in the version guard',
    () async {
      final h = await _Harness.create(2);
      addTearDown(h.dispose);
      await h.listen();
      h.remote.server['old'] = _chat('old');
      final gate = h.messages.nextPendingGate =
          Completer<List<PendingChatDeletion>>();
      h.messages.gatedPendingRead = h.messages.pendingReads + 2;
      final lookup = h.repository.getChatById('old');
      await _until(
        () => h.messages.pendingReads == h.messages.gatedPendingRead,
      );
      h.remote.server['old'] = _chat('old').copyWith(isMuted: true);
      h.remote.changes.add(
        const ConversationChange(conversationId: 'old', reason: 'muted'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete([]);
      expect((await lookup)?.isMuted, true);
      expect(h.remote.batches, hasLength(2));
    },
  );

  test('resume detaches a hung old lookup lane', () async {
    final h = await _Harness.create(0);
    addTearDown(h.dispose);
    h.remote.server['new'] = _chat('new');
    final gate = h.remote.nextIdGate = Completer<List<Chat>>();
    final old = h.repository.getChatById('old');
    await _until(() => h.remote.batches.isNotEmpty);
    await h.repository.pauseRealtime();
    await h.repository.resumeRealtime();
    expect(
      (await h.repository
              .getChatById('new')
              .timeout(const Duration(seconds: 1)))
          ?.id,
      'new',
    );
    gate.complete([_chat('old')]);
    expect(await old, isNull);
    expect(await h.cache.readById('old'), isNull);
  });

  test(
    'unrequested response cannot commit or navigate to another chat',
    () async {
      final h = await _Harness.create(0);
      addTearDown(h.dispose);
      h.remote.nextIdGate = Completer<List<Chat>>()..complete([_chat('other')]);
      expect(await h.repository.getChatById('requested'), isNull);
      expect(await h.cache.read(), isEmpty);
    },
  );

  test(
    'profile draft opens immediately, shared peer lookup only promotes an existing chat',
    () async {
      final h = await _Harness.create(0);
      addTearDown(h.dispose);
      final gate = h.remote.nextPeerGate = Completer<Chat?>();
      final drafts = await Future.wait([
        for (var i = 0; i < 8; i++)
          h.repository.prepareDirectChat(
            peerId: 'peer-old',
            peerUsername: 'old',
            peerDisplayName: 'Old',
          ),
      ]).timeout(const Duration(seconds: 1));
      expect(drafts.every((e) => e.isDraft), true);
      await _until(() => h.remote.peerCalls == 1);
      gate.complete(_chat('old'));
      await _until(() async => await h.cache.readByPeerId('peer-old') != null);
      expect(h.remote.peerCalls, 1);
      expect(h.remote.fullCalls, 0);
      expect(h.remote.createCalls, 0);
    },
  );

  test('empty peer lookup does not create a chat', () async {
    final h = await _Harness.create(0);
    addTearDown(h.dispose);
    final draft = await h.repository.prepareDirectChat(
      peerId: 'new-peer',
      peerUsername: 'new',
      peerDisplayName: 'New',
    );
    expect(draft.isDraft, true);
    await _until(() => h.remote.peerCalls == 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.remote.createCalls, 0);
    expect(h.remote.fullCalls, 0);
    expect(await h.cache.read(), isEmpty);
  });

  test(
    'first send creates once and fetches exact ID independently of stalled peer lookup',
    () async {
      final h = await _Harness.create(1000);
      addTearDown(h.dispose);
      final peerGate = h.remote.nextPeerGate = Completer<Chat?>();
      await h.repository.prepareDirectChat(
        peerId: 'peer-created',
        peerUsername: 'new',
        peerDisplayName: 'New',
      );
      await _until(() => h.remote.peerCalls == 1);
      final chats = await Future.wait([
        for (var i = 0; i < 10; i++)
          h.repository.ensureDirectChat('peer-created'),
      ]).timeout(const Duration(seconds: 1));
      expect(chats.every((e) => e.id == 'created'), true);
      expect(h.remote.createCalls, 1);
      expect(h.remote.batches, [
        {'created'},
      ]);
      expect(h.remote.fullCalls, 0);
      peerGate.complete(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await h.cache.readById('created'))?.peerId, 'peer-created');
    },
  );

  test('accepted creation cannot commit after account switch', () async {
    final h = await _Harness.create(0);
    addTearDown(h.dispose);
    final gate = h.remote.creationGate = Completer<String>();
    final creation = h.repository.ensureDirectChat('peer-created');
    final rejected = expectLater(
      creation,
      throwsA(isA<StaleAccountSessionException>()),
    );
    await _until(() => h.remote.createCalls == 1);
    h.account.setAuthenticatedUser('other');
    gate.complete('created');
    await rejected;
    expect(h.remote.batches, isEmpty);
    expect(await h.cache.read(ownerUserId: 'owner'), isEmpty);
    expect(await h.cache.read(ownerUserId: 'other'), isEmpty);
  });

  test('older lookup preserves an optimistic pending preview', () async {
    final h = await _Harness.create(0);
    addTearDown(h.dispose);
    h.remote.server['old'] = _chat('old');
    await h.messages.upsertMessage(
      ChatMessage(
        id: 'pending',
        chatId: 'old',
        senderId: 'owner',
        isMine: true,
        text: 'local',
        timestamp: DateTime(2027),
        status: MessageStatus.sending,
      ),
      isPending: true,
    );
    final chat = await h.repository.getChatById('old');
    expect(chat?.lastMessageId, 'pending');
    expect(chat?.lastMessage, 'local');
  });

  test('quota/network errors never trigger a full-list fallback', () async {
    final h = await _Harness.create(0);
    addTearDown(h.dispose);
    h.remote.nextIdError = const PostgrestException(
      message: 'quota',
      code: 'PT429',
    );
    expect(await h.repository.getChatById('old'), isNull);
    expect(h.remote.fullCalls, 0);
    expect(h.remote.batches, hasLength(1));
  });

  test(
    'missing migration falls back once per capability without treating network failure as absence',
    () async {
      final h = await _Harness.create(0);
      addTearDown(h.dispose);
      h.remote.nextIdError = const PostgrestException(
        message: 'missing function',
        code: 'PGRST202',
      );
      expect(await h.repository.getChatById('missing'), isNull);
      expect(await h.repository.getChatById('missing2'), isNull);
      expect(h.remote.batches, hasLength(1));
      expect(h.remote.fullCalls, 2);
    },
  );
}

Chat _chat(String id) => Chat(
  id: id,
  peerId: 'peer-$id',
  userName: 'Peer $id',
  lastMessage: 'preview',
  lastMessageId: 'message-$id',
  lastMessageTime: DateTime(2026),
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
);
Future<void> _until(FutureOr<bool> Function() check) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!await check()) {
    if (DateTime.now().isAfter(end)) fail('Lookup state did not arrive');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Harness {
  _Harness(
    this.database,
    this.account,
    this.media,
    this.cache,
    this.messages,
    this.sync,
    this.remote,
    this.repository,
  );
  final AppDatabase database;
  final AccountSessionController account;
  final MediaCacheService media;
  final ChatsCacheDataSource cache;
  final _Messages messages;
  final ConversationSyncService sync;
  final _Remote remote;
  final ChatsRepository repository;
  StreamSubscription<List<Chat>>? subscription;
  static Future<_Harness> create(int count) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final account = AccountSessionController(initialUserId: 'owner');
    final media = MediaCacheService(database: db);
    final talker = Talker(settings: TalkerSettings(enabled: false));
    final config = AppConfig(
      environment: AppEnvironment.prod,
      preferences: prefs,
      talker: talker,
      env: const {},
      database: db,
      accountSessionController: account,
    );
    final cache = ChatsCacheDataSource(
      database: db,
      userIdProvider: () => account.userId!,
    );
    final messages = _Messages(db, account);
    final head = [for (var i = 0; i < count; i++) _chat('$i')];
    await cache.replaceAll(head);
    final remote = _Remote(head);
    final mr = ChatRemoteDataSource(client: remote.client);
    final sync = ConversationSyncService(
      cache: messages,
      remote: mr,
      hydrator: ChatMessageHydrator(
        config: config,
        remote: mr,
        mediaCache: media,
      ),
      chatsCache: cache,
      accountSessionController: account,
    );
    final repository = ChatsRepository(
      config: config,
      cache: cache,
      remote: remote,
      mediaCache: media,
      chatCache: messages,
      conversationSync: sync,
      accountSessionController: account,
    );
    return _Harness(
      db,
      account,
      media,
      cache,
      messages,
      sync,
      remote,
      repository,
    );
  }

  Future<void> listen() async {
    subscription = repository.watchChats().listen((_) {});
    await _until(() => remote.fullCalls == 1);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  Future<void> dispose() async {
    await subscription?.cancel();
    await repository.pauseRealtime();
    await account.drainCommits();
    await remote.changes.close();
    await remote.client.dispose();
    media.dispose();
    await database.close();
  }
}

class _Messages extends ChatCacheDataSource {
  _Messages(AppDatabase database, AccountSessionController account)
    : super(database: database, userIdProvider: () => account.userId!);
  int pendingReads = 0;
  int? gatedPendingRead;
  Completer<List<PendingChatDeletion>>? nextPendingGate;
  @override
  Future<List<PendingChatDeletion>> readPendingChatDeletions({
    String? ownerUserId,
  }) {
    pendingReads++;
    if (pendingReads == gatedPendingRead) return nextPendingGate!.future;
    return super.readPendingChatDeletions(ownerUserId: ownerUserId);
  }
}

class _Remote extends ChatsRemoteDataSource {
  _Remote(List<Chat> head)
    : this._(
        head,
        SupabaseClient(
          'http://localhost',
          'key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  _Remote._(this.head, this.client)
    : super(
        client: client,
        talker: Talker(settings: TalkerSettings(enabled: false)),
      ) {
    server.addEntries(head.map((c) => MapEntry(c.id, c)));
  }
  final SupabaseClient client;
  final List<Chat> head;
  final server = <String, Chat>{};
  final changes = StreamController<ConversationChange>.broadcast();
  int fullCalls = 0,
      peerCalls = 0,
      createCalls = 0,
      activeIds = 0,
      maximumIds = 0;
  final batches = <Set<String>>[];
  Completer<List<Chat>>? nextIdGate, nextFullGate;
  Object? nextIdError;
  Completer<Chat?>? nextPeerGate;
  Completer<String>? creationGate;
  @override
  Future<List<Chat>> fetchChats() async {
    fullCalls++;
    final gate = nextFullGate;
    nextFullGate = null;
    return gate == null ? head : gate.future;
  }

  @override
  Future<List<Chat>> fetchChatsByIds(Set<String> ids) async {
    batches.add(Set.of(ids));
    activeIds++;
    if (activeIds > maximumIds) maximumIds = activeIds;
    final gate = nextIdGate;
    nextIdGate = null;
    final error = nextIdError;
    nextIdError = null;
    try {
      if (error != null) throw error;
      return gate == null
          ? ids.map((id) => server[id]).whereType<Chat>().toList()
          : await gate.future;
    } finally {
      activeIds--;
    }
  }

  @override
  Future<Chat?> fetchChatByPeerId(String peerId) async {
    peerCalls++;
    final gate = nextPeerGate;
    nextPeerGate = null;
    return gate == null
        ? server.values.where((c) => c.peerId == peerId).firstOrNull
        : gate.future;
  }

  @override
  Future<String> createDirectConversation(String peerId) async {
    createCalls++;
    final id = creationGate == null ? 'created' : await creationGate!.future;
    server[id] = _chat(id).copyWith(peerId: peerId);
    return id;
  }

  @override
  Stream<ConversationChange> watchChanges() => changes.stream;
  @override
  Future<void> pauseChanges() async {}
  @override
  Future<void> resumeChanges() async {}
}
