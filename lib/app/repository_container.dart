import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/avatar_image_processor.dart';
import 'package:yap_chat/core/services/chat_media_processor.dart';
import 'package:yap_chat/core/services/media_cache_service.dart';
import 'package:yap_chat/repositories/repositories.dart';

/// Контейнер репозиториев приложения.
///
/// Он хранит только абстрактные контракты, а выбор конкретных реализаций
/// делается фабриками [prod] и [dev].
class RepositoryContainer {
  const RepositoryContainer({
    required this.mediaCache,
    required this.chatsRepository,
    required this.chatRepository,
    required this.localMediaRepository,
    required this.locationRepository,
    required this.audioRecorderRepository,
    required this.audioPlayerRepository,
    required this.authRepository,
    required this.profileRepository,
    required this.presenceRepository,
    required this.pushNotificationsRepository,
    required this.friendsRepository,
  });

  factory RepositoryContainer.prod({required AppConfig config}) {
    final client = config.requireSupabaseClient();
    final mediaCache = MediaCacheService(
      database: config.database,
      client: client,
    );
    final chatsCache = ChatsCacheDataSource(
      database: config.database,
      userIdProvider: () => client.auth.currentUser!.id,
    );
    final chatCache = ChatCacheDataSource(
      database: config.database,
      userIdProvider: () => client.auth.currentUser!.id,
    );
    final chatsRemote = ChatsRemoteDataSource(
      client: client,
      talker: config.talker,
    );
    final friendsRemote = FriendsRemoteDataSource(
      client: client,
      talker: config.talker,
    );
    final friendsCache = FriendsCacheDataSource(
      database: config.database,
      userIdProvider: () => client.auth.currentUser!.id,
    );
    final chatRemote = ChatRemoteDataSource(client: client);
    final messageHydrator = ChatMessageHydrator(
      config: config,
      remote: chatRemote,
      mediaCache: mediaCache,
    );
    final conversationSync = ConversationSyncService(
      cache: chatCache,
      remote: chatRemote,
      hydrator: messageHydrator,
      chatsCache: chatsCache,
    );
    return RepositoryContainer(
      mediaCache: mediaCache,
      chatsRepository: ChatsRepository(
        config: config,
        cache: chatsCache,
        remote: chatsRemote,
        mediaCache: mediaCache,
        chatCache: chatCache,
        chatRemote: chatRemote,
        conversationSync: conversationSync,
      ),
      chatRepository: ChatRepository(
        config: config,
        cache: chatCache,
        remote: chatRemote,
        mediaProcessor: const ChatMediaProcessor(),
        mediaCache: mediaCache,
        syncService: conversationSync,
      ),
      localMediaRepository: LocalMediaRepository(
        preferences: config.preferences,
      ),
      locationRepository: LocationRepository(),
      audioRecorderRepository: AudioRecorderRepository(),
      audioPlayerRepository: AudioPlayerRepository(),
      authRepository: AuthRepository(
        client: client,
        redirectUrl: config.authRedirectUrl,
        useAnonymousSignIn: config.isLocal,
      ),
      profileRepository: ProfileRepository(
        client: client,
        cache: ProfileCacheDataSource(database: config.database),
        avatarStorage: AvatarStorageDataSource(
          client: client,
          imageProcessor: const AvatarImageProcessor(),
        ),
      ),
      presenceRepository: PresenceRepository(
        client: client,
        talker: config.talker,
      ),
      pushNotificationsRepository:
          config.isLocal || config.firebaseMessaging == null
          ? const MockPushNotificationsRepository()
          : PushNotificationsRepository(
              client: client,
              messaging: config.firebaseMessaging!,
              preferences: config.preferences,
              talker: config.talker,
            ),
      friendsRepository: FriendsRepository(
        config: config,
        cache: friendsCache,
        remote: friendsRemote,
        mediaCache: mediaCache,
      ),
    );
  }

  factory RepositoryContainer.dev({required AppConfig config}) {
    final mediaCache = MediaCacheService(
      database: config.database,
      client: config.supabaseClient,
    );
    return RepositoryContainer(
      mediaCache: mediaCache,
      chatsRepository: MockChatsRepository(),
      chatRepository: MockChatRepository(),
      localMediaRepository: LocalMediaRepository(
        preferences: config.preferences,
      ),
      locationRepository: LocationRepository(),
      audioRecorderRepository: AudioRecorderRepository(),
      audioPlayerRepository: AudioPlayerRepository(),
      authRepository: MockAuthRepository(preferences: config.preferences),
      profileRepository: MockProfileRepository(preferences: config.preferences),
      presenceRepository: MockPresenceRepository(),
      pushNotificationsRepository: const MockPushNotificationsRepository(),
      friendsRepository: MockFriendsRepository(),
    );
  }

  final MediaCacheService mediaCache;
  final IChatsRepository chatsRepository;
  final IChatRepository chatRepository;
  final ILocalMediaRepository localMediaRepository;
  final ILocationRepository locationRepository;
  final IAudioRecorderRepository audioRecorderRepository;
  final IAudioPlayerRepository audioPlayerRepository;
  final IAuthRepository authRepository;
  final IProfileRepository profileRepository;
  final IPresenceRepository presenceRepository;
  final IPushNotificationsRepository pushNotificationsRepository;
  final IFriendsRepository friendsRepository;

  Future<void> dispose() async {
    mediaCache.dispose();
    await Future.wait([
      chatsRepository.pauseRealtime(),
      chatRepository.pauseNetwork(),
      presenceRepository.disconnect(),
      pushNotificationsRepository.dispose(),
      friendsRepository.pauseRealtime(),
    ]);
  }
}
