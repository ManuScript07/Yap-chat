import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/repository_container.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/repositories/repositories.dart';

/// Центральная точка Dependency Injection.
///
/// Здесь регистрируются репозитории по интерфейсам и глобальные BLoC/Cubit.
class AppInitializer extends StatelessWidget {
  const AppInitializer({
    super.key,
    required this.config,
    required this.child,
  });

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
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ChatsBloc>(
            create: (context) => ChatsBloc(
              chatsRepository: context.read<IChatsRepository>(),
            )..add(const ChatsLoadStarted()),
          ),
        ],
        child: child,
      ),
    );
  }
}
