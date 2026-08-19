import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/avatar_image_processor.dart';
import 'package:yap_chat/core/services/chat_media_processor.dart';
import 'package:yap_chat/repositories/repositories.dart';

/// Контейнер репозиториев приложения.
///
/// Он хранит только абстрактные контракты, а выбор конкретных реализаций
/// делается фабриками [prod] и [dev].
class RepositoryContainer {
  const RepositoryContainer({
    required this.chatsRepository,
    required this.chatRepository,
    required this.localMediaRepository,
    required this.locationRepository,
    required this.audioRecorderRepository,
    required this.audioPlayerRepository,
    required this.authRepository,
    required this.profileRepository,
    required this.presenceRepository,
  });

  factory RepositoryContainer.prod({required AppConfig config}) {
    final client = config.requireSupabaseClient();
    return RepositoryContainer(
      chatsRepository: ChatsRepository(
        config: config,
        cache: ChatsCacheDataSource(
          database: config.database,
          userIdProvider: () => client.auth.currentUser!.id,
        ),
        remote: ChatsRemoteDataSource(client: client),
      ),
      chatRepository: ChatRepository(
        config: config,
        cache: ChatCacheDataSource(
          database: config.database,
          userIdProvider: () => client.auth.currentUser!.id,
        ),
        remote: ChatRemoteDataSource(client: client),
        mediaProcessor: const ChatMediaProcessor(),
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
      ),
      profileRepository: ProfileRepository(
        client: client,
        cache: ProfileCacheDataSource(database: config.database),
        avatarStorage: AvatarStorageDataSource(
          client: client,
          imageProcessor: const AvatarImageProcessor(),
        ),
      ),
      presenceRepository: PresenceRepository(client: client),
    );
  }

  factory RepositoryContainer.dev({required AppConfig config}) {
    return RepositoryContainer(
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
    );
  }

  final IChatsRepository chatsRepository;
  final IChatRepository chatRepository;
  final ILocalMediaRepository localMediaRepository;
  final ILocationRepository locationRepository;
  final IAudioRecorderRepository audioRecorderRepository;
  final IAudioPlayerRepository audioPlayerRepository;
  final IAuthRepository authRepository;
  final IProfileRepository profileRepository;
  final IPresenceRepository presenceRepository;
}
