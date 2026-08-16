import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/router/router.gr.dart';

@RoutePage()
class AuthGatePage extends StatelessWidget {
  const AuthGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (previous, current) => previous.status != current.status,
      builder: (context, state) {
        return AutoRouter.declarative(
          routes: (_) => [
            switch (state.status) {
              AuthStatus.unauthenticated => const WelcomeRoute(),
              AuthStatus.profileIncomplete => const ProfileSetupRoute(),
              AuthStatus.authenticated => const MainRoute(),
              AuthStatus.failure => const AuthFailureRoute(),
              AuthStatus.initial || AuthStatus.loading => const SplashRoute(),
            },
          ],
        );
      },
    );
  }
}
