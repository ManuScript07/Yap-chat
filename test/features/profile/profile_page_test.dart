import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/view/profile_page.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/theme/theme.dart';
import 'package:yap_chat/ui/widgets/chat_glass_surface.dart';
import 'package:yap_chat/ui/widgets/glass_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'own profile keeps its username outside the gallery Hero flight',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final photo = ProfilePhoto(
        position: 0,
        storagePath: 'owner/avatar.png',
        bytes: File('assets/logo/logo_yap_chat.png').readAsBytesSync(),
      );
      final auth = _ProfileAuthBloc(
        profile: UserProfile(
          id: 'owner',
          username: 'owner',
          displayName: 'Owner',
          onboardingCompleted: true,
          photos: [photo],
        ),
      );
      addTearDown(auth.close);
      await tester.pumpWidget(
        RepositoryProvider<IProfileRepository>.value(
          value: MockProfileRepository(preferences: preferences),
          child: BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp(
              theme: ThemeData.dark(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ProfilePage(),
            ),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump();
        if (tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((w) => w.image != null)) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pumpAndSettle();
      final plaque = find.descendant(
        of: find.byType(ProfilePhotoUsernameTransition, skipOffstage: false),
        matching: find.byType(AnimatedOpacity, skipOffstage: false),
      );
      double alpha() =>
          tester.renderObject<RenderAnimatedOpacity>(plaque).opacity.value;
      expect(alpha(), 1);
      await tester.tapAt(tester.getCenter(find.byType(ProfilePhotoHero)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      for (
        var i = 0;
        i < 40 &&
            find
                .byKey(const ValueKey('profile-photo-flight-clip'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(
        find.byKey(const ValueKey('profile-photo-flight-clip')),
        findsOneWidget,
      );
      expect(alpha(), closeTo(1, .01));
      await tester.pump(const Duration(milliseconds: 130));
      expect(alpha(), 0);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('profile-photo-flight-clip')),
        findsOneWidget,
      );
      expect(alpha(), 0);
      await tester.pumpAndSettle();
      expect(alpha(), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final screen in [const Size(320, 720), const Size(780, 390)]) {
    testWidgets(
      'profile header keeps geometry and frosted material on $screen',
      (tester) async {
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final repository = MockProfileRepository(preferences: preferences);
        final auth = _ProfileAuthBloc();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          final closing = auth.close();
          await tester.pump();
          await closing;
        });
        const boundaryKey = ValueKey('profile-preview');
        await tester.pumpWidget(
          RepositoryProvider<IProfileRepository>.value(
            value: repository,
            child: BlocProvider<AuthBloc>.value(
              value: auth,
              child: MaterialApp(
                // Keep the production palette, but use the bundled font rather
                // than starting Google Fonts downloads in a widget test.
                theme: ThemeData(
                  useMaterial3: true,
                  brightness: Brightness.dark,
                  scaffoldBackgroundColor: AppColors.onBrandPrimary,
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.brandPrimary,
                    onPrimary: AppColors.onBrandPrimary,
                    surface: AppColors.surfaceOverlay,
                    onSurface: AppColors.textPrimary,
                    onSurfaceVariant: AppColors.textSecondary,
                    outline: AppColors.borderInactive,
                  ),
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: 'Roboto',
                  ),
                ),
                locale: const Locale('ru'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const RepaintBoundary(
                  key: boundaryKey,
                  child: ProfilePage(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final buttons = tester.widgetList<GlassButton>(
          find.byType(GlassButton),
        );
        expect(buttons.length, 3);
        expect(buttons.every((button) => button.frostedStyle), isTrue);
        expect(find.byType(ChatGlassSurface), findsNWidgets(3));
        expect(
          tester.getRect(find.byIcon(Icons.edit_rounded)).center,
          const Offset(41, 41),
        );
        expect(
          tester.getRect(find.byIcon(Icons.settings_rounded)).center,
          const Offset(103, 41),
        );
        expect(
          tester.getRect(find.byIcon(Icons.share_rounded)).center,
          Offset(screen.width - 41, 41),
        );
        for (final element in find.byType(GlassButton).evaluate()) {
          expect(
            tester.getSize(find.byWidget(element.widget)),
            const Size(50, 50),
          );
        }
        expect(tester.takeException(), isNull);

        if (Platform.environment['CAPTURE_PROFILE_UI'] == 'true') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'output/profile-glass-${screen.width.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      },
    );
  }
}

/// A stable signed-in fixture: these layout tests do not exercise OAuth.
class _ProfileAuthBloc extends Cubit<AuthState> implements AuthBloc {
  _ProfileAuthBloc({UserProfile? profile})
    : super(
        AuthState(
          status: AuthStatus.authenticated,
          profile:
              profile ??
              const UserProfile(
                id: 'owner',
                username: 'owner',
                displayName: 'Пользователь',
                onboardingCompleted: true,
              ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
