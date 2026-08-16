import 'package:yap_chat/app/app_config.dart';
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
  });

  factory RepositoryContainer.prod({required AppConfig config}) {
    return RepositoryContainer(
      chatsRepository: ChatsRepository(config: config),
      chatRepository: ChatRepository(config: config),
      localMediaRepository: LocalMediaRepository(
        preferences: config.preferences,
      ),
      locationRepository: LocationRepository(),
      audioRecorderRepository: AudioRecorderRepository(),
      audioPlayerRepository: AudioPlayerRepository(),
      authRepository: AuthRepository(
        client: config.requireSupabaseClient(),
        redirectUrl: config.authRedirectUrl,
      ),
      profileRepository: ProfileRepository(
        client: config.requireSupabaseClient(),
      ),
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
}
