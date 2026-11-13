import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app_connection_coordinator.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  test(
    'failed delegate does not turn lifecycle ownership into a connectivity probe',
    () async {
      final chats = _FailingChatsRepository();
      final chat = _FakeChatRepository();
      final presence = _FakePresenceRepository();
      final friends = _FakeFriendsRepository();
      final coordinator = AppConnectionCoordinator(
        chatsRepository: chats,
        chatRepository: chat,
        presenceRepository: presence,
        friendsRepository: friends,
        talker: Talker(settings: TalkerSettings(enabled: false)),
      );
      addTearDown(coordinator.dispose);
      // A guarded failed resume still means "delegates started" to this class.
      // A UI connectivity store must observe transport/HTTP instead of this flag.
      await coordinator.setAuthenticatedUser('user-1');
      await coordinator.setForeground(true);
      await coordinator.setAuthenticatedUser('user-1');
      expect(chats.resumeCount, 1);
      expect(chat.synchronizeCount, 1);
      expect(presence.connectedUserIds, ['user-1']);
      await coordinator.setForeground(false);
      await coordinator.setForeground(true);
      expect(chats.resumeCount, 2);
      expect(chat.synchronizeCount, 2);
    },
  );
  test(
    'background suspends presence but sign-out in background clears it',
    () async {
      final presence = _LifecyclePresenceRepository();
      final coordinator = AppConnectionCoordinator(
        chatsRepository: _FakeChatsRepository(),
        chatRepository: _FakeChatRepository(),
        presenceRepository: presence,
        friendsRepository: _FakeFriendsRepository(),
        talker: Talker(),
      );
      await coordinator.setAuthenticatedUser('user-1');
      await coordinator.setForeground(false);
      await coordinator.setForeground(false);
      expect(presence.suspendCount, 1);
      expect(presence.disconnectCount, 0);
      await coordinator.setAuthenticatedUser(null);
      expect(presence.disconnectCount, 1);
      await coordinator.setAuthenticatedUser('user-2');
      await coordinator.setForeground(true);
      expect(presence.connectedUserIds, ['user-1', 'user-2']);
      await coordinator.dispose();
    },
  );
  test('only a long inactive interval needs a recovery cycle', () {
    final started = DateTime.utc(2026, 9, 26);
    expect(
      AppConnectionCoordinator.shouldRecoverAfterInactive(
        null,
        started.add(const Duration(minutes: 1)),
      ),
      isFalse,
    );
    expect(
      AppConnectionCoordinator.shouldRecoverAfterInactive(
        started,
        started.add(const Duration(seconds: 29)),
      ),
      isFalse,
    );
    expect(
      AppConnectionCoordinator.shouldRecoverAfterInactive(
        started,
        started.add(const Duration(seconds: 30)),
      ),
      isTrue,
    );
  });

  test('coalesces duplicate auth and lifecycle updates', () async {
    final chats = _FakeChatsRepository();
    final chat = _FakeChatRepository();
    final presence = _FakePresenceRepository();
    final friends = _FakeFriendsRepository();
    final coordinator = AppConnectionCoordinator(
      chatsRepository: chats,
      chatRepository: chat,
      presenceRepository: presence,
      friendsRepository: friends,
      talker: Talker(),
    );

    await coordinator.setAuthenticatedUser('user-1');
    await coordinator.setAuthenticatedUser('user-1');
    await coordinator.setForeground(true);

    expect(chats.resumeCount, 1);
    expect(chat.synchronizeCount, 1);
    expect(presence.connectedUserIds, ['user-1']);

    await coordinator.setForeground(false);
    await coordinator.setForeground(false);

    expect(chats.pauseCount, 1);
    expect(chat.pauseCount, 1);
    expect(presence.disconnectCount, 1);

    await coordinator.setForeground(true);
    await coordinator.setForeground(true);

    expect(chats.resumeCount, 2);
    expect(chat.synchronizeCount, 2);
    expect(presence.connectedUserIds, ['user-1', 'user-1']);

    await coordinator.dispose();
  });

  test('disconnects before switching authenticated users', () async {
    final chats = _FakeChatsRepository();
    final chat = _FakeChatRepository();
    final presence = _FakePresenceRepository();
    final friends = _FakeFriendsRepository();
    final coordinator = AppConnectionCoordinator(
      chatsRepository: chats,
      chatRepository: chat,
      presenceRepository: presence,
      friendsRepository: friends,
      talker: Talker(),
    );

    await coordinator.setAuthenticatedUser('user-1');
    await coordinator.setAuthenticatedUser('user-2');

    expect(chats.pauseCount, 1);
    expect(chats.resumeCount, 2);
    expect(chat.pauseCount, 1);
    expect(chat.synchronizeCount, 2);
    expect(presence.connectedUserIds, ['user-1', 'user-2']);
    expect(presence.disconnectCount, 1);

    await coordinator.dispose();
  });
}

class _FailingChatsRepository extends _FakeChatsRepository {
  @override
  Future<void> resumeRealtime() async {
    resumeCount++;
    throw StateError('diagnostic resume failure');
  }
}

class _LifecyclePresenceRepository extends _FakePresenceRepository
    implements IPresenceLifecycleRepository {
  int suspendCount = 0;
  @override
  Future<void> suspend() async {
    suspendCount++;
  }

  @override
  Stream<PresenceSnapshot> watchPresenceSnapshots() => const Stream.empty();
}

class _FakeChatsRepository implements IChatsRepository {
  int pauseCount = 0;
  int resumeCount = 0;

  @override
  Future<void> pauseRealtime() async {
    pauseCount++;
  }

  @override
  Future<void> resumeRealtime() async {
    resumeCount++;
  }

  @override
  Stream<List<Chat>> watchChats() => const Stream.empty();

  @override
  Stream<Chat?> watchChat(String chatId) => const Stream.empty();

  @override
  Future<List<Chat>> getChats() async => const [];

  @override
  Future<Chat?> getChatById(String chatId) async => null;

  @override
  Future<Chat?> getCachedChatByPeerId(String peerId) async => null;

  @override
  Future<String?> resolveAvatar(Chat chat) async => chat.avatarUrl;

  @override
  Future<Chat> prepareDirectChat({
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    String? peerAvatarUrl,
    String? peerAvatarStoragePath,
  }) => throw UnimplementedError();

  @override
  Future<Chat> ensureDirectChat(String peerId) => throw UnimplementedError();

  @override
  Future<void> deleteChats(Set<String> ids) async {}

  @override
  Future<void> markAsRead(Set<String> ids) async {}

  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {}
}

class _FakeFriendsRepository implements IFriendsRepository {
  @override
  Stream<List<Friend>> watchPaginatedFriends() => const Stream.empty();

  @override
  Stream<List<Friend>> watchCachedFriends() => const Stream.empty();

  @override
  Stream<List<FriendRequest>> watchCachedRequests() => const Stream.empty();

  @override
  Future<String?> resolveFriendAvatar(Friend friend) async => friend.avatarUrl;

  @override
  Future<String?> resolveRequestAvatar(FriendRequest request) async =>
      request.peerAvatarUrl;

  @override
  Future<String?> resolveCandidateAvatar(FriendCandidate candidate) async =>
      candidate.avatarUrl;

  @override
  Stream<List<Friend>> watchFriends() => const Stream.empty();

  @override
  Stream<FriendListCacheState> watchFriendListState() => const Stream.empty();

  @override
  Stream<List<FriendRequest>> watchRequests() => const Stream.empty();

  @override
  Future<void> loadMoreFriends() async {}

  @override
  Future<List<FriendRequest>> getRequests() async => const [];

  @override
  Future<List<FriendCandidate>> searchUsers(String query) async => const [];

  @override
  Future<ContactMatchSnapshot> readCachedContactMatches(
    List<String> phoneNumbers,
  ) async => const ContactMatchSnapshot();

  @override
  Future<ContactMatchSnapshot> readCachedPhoneSearchMatch(
    String phoneNumber,
  ) async => const ContactMatchSnapshot();

  @override
  Future<ContactMatchSnapshot> refreshContactMatches(
    List<String> phoneNumbers,
  ) async => const ContactMatchSnapshot();

  @override
  Future<ContactMatchSnapshot> refreshNewFriendContactMatches(
    List<String> phoneNumbers,
    Set<String> friendIds,
  ) async => const ContactMatchSnapshot();

  @override
  Future<ContactMatchSnapshot> refreshPhoneMatch(String phoneNumber) async =>
      const ContactMatchSnapshot();

  @override
  Future<void> sendRequest(FriendCandidate candidate) async {}

  @override
  Future<void> cancelRequest(String requestId) async {}

  @override
  Future<void> respondToRequest(
    String requestId, {
    required bool accept,
  }) async {}

  @override
  Future<FriendLocationLookup> getFriendLocation(String friendId) async =>
      const FriendLocationLookup.unavailable();

  @override
  Future<void> pauseRealtime() async {}

  @override
  Future<void> resumeRealtime() async {}
}

class _FakeChatRepository implements IChatRepository {
  @override
  Future<bool> setMessageReaction(
    ChatMessage message,
    ReactionCode code, {
    bool toggle = true,
  }) async => false;
  @override
  Future<void> reconcileVisibleMessages(String chatId, Set<String> ids) async {}

  int pauseCount = 0;
  int synchronizeCount = 0;

  @override
  Future<ChatMessage> hydrateWindowMedia(ChatMessage message) async => message;

  @override
  Future<List<ChatMessage>> loadMessageWindow(
    String chatId,
    String messageId,
  ) async => const [];

  @override
  Future<List<ChatMessage>> loadWindowOlder(
    String chatId,
    ChatMessage oldest,
  ) async => const [];

  @override
  Future<List<ChatMessage>> loadWindowNewer(
    String chatId,
    ChatMessage newest,
  ) async => const [];

  @override
  Stream<ChatHistoryChange> watchHistoryChanges(String chatId) =>
      const Stream.empty();

  @override
  Future<void> pauseNetwork() async {
    pauseCount++;
  }

  @override
  Future<void> synchronizeOpenChats() async {
    synchronizeCount++;
  }

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) =>
      const Stream.empty();

  @override
  Future<void> markVisibleMessagesRead(
    String chatId,
    Set<String> messageIds,
  ) async {}

  @override
  Future<bool> loadMoreMessages(String chatId) async => false;

  @override
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToMessageId,
  }) async {}

  @override
  Future<void> sendImages(
    String chatId,
    List<String> imagePaths, {
    String? replyToMessageId,
  }) async {}

  @override
  Future<void> sendAudio(
    String chatId,
    String audioPath,
    Duration duration,
    List<double> waveform, {
    String? replyToMessageId,
  }) async {}

  @override
  Future<void> retryMessage(String chatId, ChatMessage message) async {}

  @override
  Future<void> sendLocation(
    String chatId,
    double latitude,
    double longitude, {
    String? replyToMessageId,
  }) async {}

  @override
  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    required bool deleteForEveryone,
  }) async {}
}

class _FakePresenceRepository implements IPresenceRepository {
  final List<String> connectedUserIds = [];
  int disconnectCount = 0;

  @override
  Future<void> connect(String userId) async {
    connectedUserIds.add(userId);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
  }

  @override
  Stream<Set<String>> watchOnlineUserIds() => const Stream.empty();
}
