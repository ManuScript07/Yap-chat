import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/features/profile/profile.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  test(
    'draft mute retains a typed limit refusal and remains retryable',
    () async {
      final chats = _Chats()..creationError = const ChatLimitReachedException();
      final cubit = await _cubit(chats);
      final draft = _chat(false).copyWith(id: 'direct-draft:peer');
      cubit.seed(draft);
      await cubit.toggleMute();
      expect(cubit.state.actionError, isA<ChatLimitReachedException>());
      expect(cubit.state.chat, draft);
      expect(chats.calls, isEmpty);
      expect(cubit.state.isActionPending, false);
      cubit.clearActionError();
      chats.creationError = null;
      await cubit.toggleMute();
      expect(cubit.state.actionError, isNull);
      expect(cubit.state.chat!.isMuted, true);
      expect(chats.calls, hasLength(1));
    },
  );
  test(
    'profile status and block updates use peer stream outside list pages',
    () async {
      final chats = _PeerChats();
      final cubit = await _cubit(chats);
      addTearDown(chats.peers.close);
      await cubit.load();
      expect(chats.watchedPeer, 'peer');
      expect(chats.listCalls, 0);
      final seen = DateTime.utc(2026, 10, 26, 12);
      chats.peers.add(chats.direct.copyWith(lastSeenAt: seen));
      await _until(() => cubit.state.viewedProfile?.lastSeenAt == seen);
      expect(cubit.state.chat?.id, 'outside-first-page');
      final blocked = cubit.stream.firstWhere(
        (s) => s.viewedProfile?.isBlocked == true,
      );
      chats.peers.add(chats.direct.copyWith(blockedByPeer: true));
      final state = await blocked.timeout(const Duration(seconds: 2));
      expect(state.viewedProfile?.profile.avatarUrl, isNull);
      expect(state.viewedProfile?.profile.avatarStoragePath, isNull);
      expect(state.location, isNull);
      expect(chats.listCalls, 0);
    },
  );
  for (final initiallyMuted in [false, true]) {
    test(
      'profile sets the inverse explicit value, initiallyMuted=$initiallyMuted',
      () async {
        final chats = _Chats();
        final cubit = await _cubit(chats);
        cubit.seed(_chat(initiallyMuted));
        await cubit.toggleMute();
        expect(chats.calls.single.ids, {'direct'});
        expect(chats.calls.single.muted, !initiallyMuted);
        expect(cubit.state.chat!.isMuted, !initiallyMuted);
        expect(cubit.state.isActionPending, false);
      },
    );
  }

  test(
    'draft profile creates a direct chat once; repeated taps are guarded',
    () async {
      final chats = _Chats()..gate = Completer<void>();
      final cubit = await _cubit(chats);
      cubit.seed(_chat(false).copyWith(id: 'direct-draft:peer'));
      final first = cubit.toggleMute();
      await chats.started.future;
      await cubit.toggleMute();
      chats.gate!.complete();
      await first;
      expect(chats.created, 1);
      expect(chats.calls, hasLength(1));
      expect(chats.calls.single.ids, {'direct'});
      expect(cubit.state.chat!.isMuted, true);
    },
  );

  test('profile failure does not flip mute locally', () async {
    final chats = _Chats()..fail = true;
    final cubit = await _cubit(chats);
    cubit.seed(_chat(false));
    await cubit.toggleMute();
    expect(cubit.state.chat!.isMuted, false);
    expect(cubit.state.actionError, isNotNull);
    expect(cubit.state.isActionPending, false);
  });
}

Future<_Cubit> _cubit(_Chats chats) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final cubit = _Cubit(
    profile: MockProfileRepository(preferences: preferences),
    location: LocationRepository(preferences: preferences),
    chats: chats,
  );
  addTearDown(cubit.close);
  return cubit;
}

class _Cubit extends ViewedProfileCubit {
  _Cubit({
    required IProfileRepository profile,
    required ILocationRepository location,
    required IChatsRepository chats,
  }) : super(
         userId: 'peer',
         profileRepository: profile,
         locationRepository: location,
         chatsRepository: chats,
         friendsRepository: MockFriendsRepository(),
         blocklistRepository: MockBlocklistRepository(),
         userReportsRepository: const MockUserReportsRepository(),
       );
  void seed(Chat chat) => emit(state.copyWith(chat: chat));
}

class _Chats extends MockChatsRepository {
  final calls = <({Set<String> ids, bool muted})>[];
  final started = Completer<void>();
  Completer<void>? gate;
  int created = 0;
  bool fail = false;
  Object? creationError;
  @override
  Future<Chat> ensureDirectChat(String peerId) async {
    created++;
    if (creationError case final error?) throw error;
    return _chat(false);
  }

  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {
    calls.add((ids: Set.of(ids), muted: isMuted));
    if (!started.isCompleted) started.complete();
    if (fail) throw StateError('offline');
    await gate?.future;
  }
}

class _PeerChats extends _Chats implements IChatsPeerRepository {
  final peers = StreamController<Chat?>.broadcast();
  String? watchedPeer;
  int listCalls = 0;
  final direct = _chat(false).copyWith(
    id: 'outside-first-page',
    peerUsername: 'peer',
    userName: 'Пользователь',
  );
  @override
  Stream<Chat?> watchChatByPeerId(String peerId) {
    watchedPeer = peerId;
    return peers.stream;
  }

  @override
  Stream<List<Chat>> watchChats() {
    listCalls++;
    throw StateError('Profile must not consume list pages');
  }

  @override
  Future<Chat> prepareDirectChat({
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    String? peerAvatarUrl,
    String? peerAvatarStoragePath,
  }) async => direct;
}

Future<void> _until(bool Function() check) async {
  final until = DateTime.now().add(const Duration(seconds: 2));
  while (!check()) {
    if (DateTime.now().isAfter(until)) fail('Peer status did not arrive');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Chat _chat(bool muted) => Chat(
  id: 'direct',
  peerId: 'peer',
  userName: 'Peer',
  lastMessage: '',
  lastMessageTime: DateTime(2026),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
  isMuted: muted,
);
