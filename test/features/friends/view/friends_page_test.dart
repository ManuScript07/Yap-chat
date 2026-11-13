import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/theme/theme.dart';

void main() {
  testWidgets('renders friends and request tabs without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MockFriendsRepository(includeSampleFriends: true);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IFriendsRepository>.value(value: repository),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) =>
                  FriendsBloc(repository: repository)
                    ..add(const FriendsLoadStarted()),
            ),
            BlocProvider(
              create: (_) =>
                  PresenceCubit(repository: MockPresenceRepository()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            locale: const Locale('ru'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const FriendsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('все друны 2', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), '@ma');
    await tester.pump();
    expect(find.text('друны 1', findRichText: true), findsOneWidget);
    expect(find.text('глобальный поиск'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Мак');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('глобальный поиск'), findsOneWidget);
    expect(find.text('Максим'), findsOneWidget);

    expect(find.text('заявки'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('заявки'));
    await tester.pumpAndSettle();

    expect(find.text('исходящие 1'), findsOneWidget);
    expect(find.text('входящие 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hides a stale global result once its user appears in the friend list',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MockFriendsRepository();

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<IFriendsRepository>.value(value: repository),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) =>
                    FriendsBloc(repository: repository)
                      ..add(const FriendsLoadStarted()),
              ),
              BlocProvider(
                create: (_) =>
                    PresenceCubit(repository: MockPresenceRepository()),
              ),
            ],
            child: MaterialApp(
              theme: theme,
              locale: const Locale('ru'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const FriendsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Дим');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Дима'), findsOneWidget);

      // The other account accepts the still visible outgoing request while
      // FriendSearchCubit retains its already fetched result.
      await repository.respondToRequest('request-outgoing', accept: true);
      await tester.pumpAndSettle();

      expect(find.text('Дима'), findsOneWidget);
      expect(find.text('ничего не нашли'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
