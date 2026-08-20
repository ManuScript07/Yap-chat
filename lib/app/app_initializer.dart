import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/app_connection_coordinator.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/app/repository_container.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/repositories/repositories.dart';

/// Центральная точка Dependency Injection.
///
/// Здесь регистрируются репозитории по интерфейсам и глобальные BLoC/Cubit.
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key, required this.config, required this.child});

  final AppConfig config;
  final Widget child;

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  late final RepositoryContainer _repositories;
  late final AppConnectionCoordinator _connectionCoordinator;

  @override
  void initState() {
    super.initState();
    _repositories = widget.config.isDev
        ? RepositoryContainer.dev(config: widget.config)
        : RepositoryContainer.prod(config: widget.config);
    _connectionCoordinator = AppConnectionCoordinator(
      chatsRepository: _repositories.chatsRepository,
      chatRepository: _repositories.chatRepository,
      presenceRepository: _repositories.presenceRepository,
      talker: widget.config.talker,
    );
  }

  @override
  void dispose() {
    unawaited(() async {
      await _connectionCoordinator.dispose();
      await _repositories.dispose();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppConfig>.value(value: widget.config),
        RepositoryProvider<AppConnectionCoordinator>.value(
          value: _connectionCoordinator,
        ),
        RepositoryProvider<IChatsRepository>.value(
          value: _repositories.chatsRepository,
        ),
        RepositoryProvider<IChatRepository>.value(
          value: _repositories.chatRepository,
        ),
        RepositoryProvider<ILocalMediaRepository>.value(
          value: _repositories.localMediaRepository,
        ),
        RepositoryProvider<ILocationRepository>.value(
          value: _repositories.locationRepository,
        ),
        RepositoryProvider<IAudioRecorderRepository>.value(
          value: _repositories.audioRecorderRepository,
        ),
        RepositoryProvider<IAudioPlayerRepository>.value(
          value: _repositories.audioPlayerRepository,
        ),
        RepositoryProvider<IAuthRepository>.value(
          value: _repositories.authRepository,
        ),
        RepositoryProvider<IProfileRepository>.value(
          value: _repositories.profileRepository,
        ),
        RepositoryProvider<IPresenceRepository>.value(
          value: _repositories.presenceRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: context.read<IAuthRepository>(),
              profileRepository: context.read<IProfileRepository>(),
              clearUserCache: _repositories.mediaCache.clearUser,
            )..add(const AuthStarted()),
          ),
          BlocProvider<PresenceCubit>(
            create: (context) =>
                PresenceCubit(repository: context.read<IPresenceRepository>()),
          ),
        ],
        child: widget.child,
      ),
    );
  }
}
