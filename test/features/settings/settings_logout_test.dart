import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/view/settings_page.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  testWidgets('confirms logout before dispatching AuthSignOutRequested', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final previousObserver = Bloc.observer;
    final observer = _RecordingBlocObserver();
    Bloc.observer = observer;
    addTearDown(() => Bloc.observer = previousObserver);
    final authBloc = AuthBloc(
      authRepository: MockAuthRepository(preferences: preferences),
      profileRepository: MockProfileRepository(preferences: preferences),
    );

    await tester.pumpWidget(
      RepositoryProvider<AppConfig>(
        create: (_) => _TestAppConfig(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: authBloc),
            BlocProvider(
              create: (_) =>
                  AppLanguageCubit(repository: MockSettingsRepository()),
            ),
            BlocProvider(
              create: (_) => AppPublicContentCubit(
                repository: const MockAppPublicContentRepository(),
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showSettingsPage(context),
                  child: const Text('open settings'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(CustomScrollView)),
    )!;
    final logoutAction = find.text(l10n.settingsLogout);
    await tester.scrollUntilVisible(
      logoutAction,
      350,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(logoutAction, findsOneWidget);

    await tester.tap(logoutAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(l10n.settingsLogoutConfirmationTitle), findsOneWidget);
    expect(find.text(l10n.settingsLogoutConfirmationContent), findsOneWidget);

    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(observer.events.whereType<AuthSignOutRequested>(), isEmpty);

    await tester.tap(logoutAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text(l10n.settingsLogoutConfirm));
    await tester.pump();

    expect(observer.events.whereType<AuthSignOutRequested>(), hasLength(1));
  }, timeout: const Timeout(Duration(seconds: 20)));
}

class _TestAppConfig implements AppConfig {
  @override
  AppDiagnostics? get diagnostics => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingBlocObserver extends BlocObserver {
  final List<Object?> events = [];

  @override
  void onEvent(Bloc<Object?, Object?> bloc, Object? event) {
    events.add(event);
    super.onEvent(bloc, event);
  }
}
