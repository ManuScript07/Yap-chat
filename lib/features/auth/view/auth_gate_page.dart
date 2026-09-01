import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/router/router.gr.dart';

@RoutePage()
class AuthGatePage extends StatefulWidget {
  const AuthGatePage({super.key});

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  bool _initialRouteSynchronizationScheduled = false;
  Future<void> _routeSynchronization = Future<void>.value();

  @override
  Widget build(BuildContext context) {
    return AutoRouter(
      builder: (routerContext, child) {
        _scheduleInitialRouteSynchronization(routerContext);

        return BlocListener<AuthBloc, AuthState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: (_, state) {
            _scheduleRouteSynchronization(routerContext.router, state.status);
          },
          child: child,
        );
      },
    );
  }

  void _scheduleInitialRouteSynchronization(BuildContext routerContext) {
    if (_initialRouteSynchronizationScheduled) return;
    _initialRouteSynchronizationScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleRouteSynchronization(
        routerContext.router,
        context.read<AuthBloc>().state.status,
      );
    });
  }

  void _scheduleRouteSynchronization(StackRouter router, AuthStatus status) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final previousSynchronization = _routeSynchronization;
      _routeSynchronization = _synchronizeRouteAfter(
        previousSynchronization,
        router,
        status,
      );
      unawaited(_ignoreSynchronizationFailure(_routeSynchronization));
    });
  }

  Future<void> _synchronizeRouteAfter(
    Future<void> previousSynchronization,
    StackRouter router,
    AuthStatus status,
  ) async {
    try {
      await previousSynchronization;
    } catch (_) {
      // A failed obsolete transition must not block the latest auth state.
    }

    if (!mounted || context.read<AuthBloc>().state.status != status) return;
    await _synchronizeRoute(router, status);
  }

  Future<void> _ignoreSynchronizationFailure(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // The next queued synchronization will reconcile the current route.
    }
  }

  Future<void> _synchronizeRoute(StackRouter router, AuthStatus status) async {
    final route = switch (status) {
      AuthStatus.unauthenticated => const WelcomeRoute(),
      AuthStatus.profileIncomplete => const ProfileSetupRoute(),
      AuthStatus.authenticated => const MainRoute(),
      AuthStatus.banned => const BannedAccountRoute(),
      AuthStatus.failure => const AuthFailureRoute(),
      AuthStatus.initial || AuthStatus.loading => const SplashRoute(),
    };
    final stack = router.stackData;
    if (stack.length == 1 && stack.single.name == route.routeName) return;

    await router.replaceAll([route]);
  }
}
