import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/avatar_image_processor.dart';
import 'package:yap_chat/core/services/chat_media_processor.dart';
import 'package:yap_chat/core/services/contact_cache_key_service.dart';
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
    required this.blocklistRepository,
    required this.userReportsRepository,
    required this.contactsRepository,
    required this.settingsRepository,
  });

  factory RepositoryContainer.prod({required AppConfig config}) {
    final client = config.requireSupabaseClient();
    final localMediaRepository = LocalMediaRepository(
      preferences: config.preferences,
      database: config.database,
      ownerUserIdProvider: () => client.auth.currentUser?.id,
      environment: config.environment.name,
      accountSessionController: config.accountSessionController,
    );
    final mediaCache = MediaCacheService(
      database: config.database,
      client: client,
      environment: config.environment.name,
      talker: config.talker,
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
    final contactMatchCache = ContactMatchCacheDataSource(
      database: config.database,
      userIdProvider: () => client.auth.currentUser!.id,
      keyService: ContactCacheKeyService(),
    );
    final settingsRepository = SettingsRepository(
      cache: SettingsCacheDataSource(database: config.database),
      remote: SettingsRemoteDataSource(client: client),
      accountSessionController: config.accountSessionController,
    );
    final profileCache = ProfileCacheDataSource(database: config.database);
    final viewedProfileCache = ViewedProfileCacheDataSource(
      database: config.database,
      profileCache: profileCache,
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
      accountSessionController: config.accountSessionController,
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
        accountSessionController: config.accountSessionController,
      ),
      chatRepository: ChatRepository(
        config: config,
        cache: chatCache,
        remote: chatRemote,
        mediaProcessor: const ChatMediaProcessor(),
        mediaCache: mediaCache,
        syncService: conversationSync,
        chatsCache: chatsCache,
        localMediaRepository: localMediaRepository,
        accountSessionController: config.accountSessionController,
      ),
      localMediaRepository: localMediaRepository,
      locationRepository: LocationRepository(
        preferences: config.preferences,
        client: client,
      ),
      audioRecorderRepository: AudioRecorderRepository(),
      audioPlayerRepository: AudioPlayerRepository(),
      authRepository: AuthRepository(
        client: client,
        redirectUrl: config.authRedirectUrl,
        useAnonymousSignIn: config.isLocal,
        oauthAttemptCoordinator: config.oauthAttemptCoordinator,
        accountSessionController: config.accountSessionController,
        accountAccessCache: AuthAccountAccessCacheDataSource(
          preferences: config.preferences,
          environment: config.environment.name,
        ),
      ),
      profileRepository: ProfileRepository(
        client: client,
        cache: profileCache,
        viewedProfileCache: viewedProfileCache,
        mediaCache: mediaCache,
        talker: config.talker,
        avatarDeletionQueue: AvatarDeletionQueue(
          preferences: config.preferences,
          environment: config.environment.name,
          talker: config.talker,
        ),
        avatarStorage: AvatarStorageDataSource(
          client: client,
          imageProcessor: const AvatarImageProcessor(),
        ),
        accountSessionController: config.accountSessionController,
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
              accountSessionController: config.accountSessionController,
            ),
      friendsRepository: FriendsRepository(
        config: config,
        cache: friendsCache,
        contactMatchCache: contactMatchCache,
        remote: friendsRemote,
        mediaCache: mediaCache,
        accountSessionController: config.accountSessionController,
      ),
      blocklistRepository: BlocklistRepository(
        cache: BlocklistCacheDataSource(
          database: config.database,
          preferences: config.preferences,
          namespace: config.environment.name,
        ),
        remote: BlocklistRemoteDataSource(client: client),
        accountSessionController: config.accountSessionController,
      ),
      userReportsRepository: UserReportsRepository(
        remote: UserReportsRemoteDataSource(client: client),
        cache: UserReportsCacheDataSource(
          preferences: config.preferences,
          environment: config.environment.name,
        ),
        accountSessionController: config.accountSessionController,
      ),
      contactsRepository: ContactsRepository(),
      settingsRepository: settingsRepository,
    );
  }

  factory RepositoryContainer.dev({required AppConfig config}) {
    final authRepository = MockAuthRepository(preferences: config.preferences);
    final localMediaRepository = LocalMediaRepository(
      preferences: config.preferences,
      database: config.database,
      ownerUserIdProvider: () => authRepository.currentSession?.userId,
      environment: config.environment.name,
      accountSessionController: config.accountSessionController,
    );
    final mediaCache = MediaCacheService(
      database: config.database,
      client: config.supabaseClient,
      environment: config.environment.name,
      talker: config.talker,
    );
    return RepositoryContainer(
      mediaCache: mediaCache,
      chatsRepository: MockChatsRepository(),
      chatRepository: MockChatRepository(),
      localMediaRepository: localMediaRepository,
      locationRepository: LocationRepository(
        preferences: config.preferences,
        client: config.supabaseClient,
      ),
      audioRecorderRepository: AudioRecorderRepository(),
      audioPlayerRepository: AudioPlayerRepository(),
      authRepository: authRepository,
      profileRepository: MockProfileRepository(preferences: config.preferences),
      presenceRepository: MockPresenceRepository(),
      pushNotificationsRepository: const MockPushNotificationsRepository(),
      friendsRepository: MockFriendsRepository(),
      blocklistRepository: MockBlocklistRepository(),
      userReportsRepository: const MockUserReportsRepository(),
      contactsRepository: const MockContactsRepository(),
      settingsRepository: MockSettingsRepository(),
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
  final IBlocklistRepository blocklistRepository;
  final IUserReportsRepository userReportsRepository;
  final IContactsRepository contactsRepository;
  final ISettingsRepository settingsRepository;

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
