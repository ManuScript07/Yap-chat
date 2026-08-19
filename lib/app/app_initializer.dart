import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/repository_container.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/repositories/repositories.dart';

/// Центральная точка Dependency Injection.
///
/// Здесь регистрируются репозитории по интерфейсам и глобальные BLoC/Cubit.
class AppInitializer extends StatelessWidget {
  const AppInitializer({super.key, required this.config, required this.child});

  final AppConfig config;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final repositories = config.isDev
        ? RepositoryContainer.dev(config: config)
        : RepositoryContainer.prod(config: config);

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppConfig>.value(value: config),
        RepositoryProvider<IChatsRepository>.value(
          value: repositories.chatsRepository,
        ),
        RepositoryProvider<IChatRepository>.value(
          value: repositories.chatRepository,
        ),
        RepositoryProvider<ILocalMediaRepository>.value(
          value: repositories.localMediaRepository,
        ),
        RepositoryProvider<ILocationRepository>.value(
          value: repositories.locationRepository,
        ),
        RepositoryProvider<IAudioRecorderRepository>.value(
          value: repositories.audioRecorderRepository,
        ),
        RepositoryProvider<IAudioPlayerRepository>.value(
          value: repositories.audioPlayerRepository,
        ),
        RepositoryProvider<IAuthRepository>.value(
          value: repositories.authRepository,
        ),
        RepositoryProvider<IProfileRepository>.value(
          value: repositories.profileRepository,
        ),
        RepositoryProvider<IPresenceRepository>.value(
          value: repositories.presenceRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: context.read<IAuthRepository>(),
              profileRepository: context.read<IProfileRepository>(),
            )..add(const AuthStarted()),
          ),
          BlocProvider<PresenceCubit>(
            create: (context) =>
                PresenceCubit(repository: context.read<IPresenceRepository>()),
          ),
        ],
        child: child,
      ),
    );
  }
}
