import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
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
        final isAuthenticated = state.status == AuthStatus.authenticated;
        return PopScope(
          canPop: !isAuthenticated,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop || !isAuthenticated) return;

            final tabsRouter = context.router.root
                .innerRouterOf<StackRouter>(AuthGateRoute.name)
                ?.innerRouterOf<TabsRouter>(MainRoute.name);
            if (tabsRouter != null && tabsRouter.activeIndex != 0) {
              tabsRouter.setActiveIndex(0);
              return;
            }

            SystemNavigator.pop();
          },
          child: AutoRouter.declarative(
            routes: (_) => [
              switch (state.status) {
                AuthStatus.unauthenticated => const WelcomeRoute(),
                AuthStatus.profileIncomplete => const ProfileSetupRoute(),
                AuthStatus.authenticated => const MainRoute(),
                AuthStatus.failure => const AuthFailureRoute(),
                AuthStatus.initial || AuthStatus.loading => const SplashRoute(),
              },
            ],
          ),
        );
      },
    );
  }
}
