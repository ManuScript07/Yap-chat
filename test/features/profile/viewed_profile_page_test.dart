import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/profile/view/viewed_profile_page.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/theme/theme.dart';
import 'package:yap_chat/ui/widgets/chat_glass_surface.dart';
import 'package:yap_chat/ui/widgets/glass_button.dart';

void main() {
  testWidgets('lays out a non-friend profile on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IProfileRepository>.value(
            value: MockProfileRepository(preferences: preferences),
          ),
          RepositoryProvider<IFriendsRepository>.value(
            value: MockFriendsRepository(),
          ),
          RepositoryProvider<IChatsRepository>.value(
            value: MockChatsRepository(),
          ),
          RepositoryProvider<ILocationRepository>.value(
            value: LocationRepository(preferences: preferences),
          ),
          RepositoryProvider<ISettingsRepository>.value(
            value: MockSettingsRepository(),
          ),
          RepositoryProvider<IBlocklistRepository>.value(
            value: MockBlocklistRepository(),
          ),
          RepositoryProvider<IUserReportsRepository>.value(
            value: const MockUserReportsRepository(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) =>
                  PresenceCubit(repository: MockPresenceRepository()),
            ),
            BlocProvider(
              create: (context) => BlocklistCubit(
                repository: context.read<IBlocklistRepository>(),
              ),
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
            home: const ViewedProfilePage(userId: 'candidate-3'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerButtons = tester.widgetList<GlassButton>(
      find.byType(GlassButton),
    );
    expect(headerButtons.length, 2);
    expect(headerButtons.every((button) => button.frostedStyle), isTrue);
    expect(find.byType(ChatGlassSurface), findsNWidgets(2));
    expect(tester.getSize(find.byType(GlassButton).first), const Size(50, 50));

    expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
    expect(find.text('3 км'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_rounded), findsNothing);
    expect(find.byIcon(Icons.visibility_off_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.person_add_alt_1_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
