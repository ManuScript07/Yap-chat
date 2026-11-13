import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  setUpAll(() async {
    // Use the app font rather than Ahem's artificial glyph metrics.
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });
  testWidgets('shows add methods without the disabled search UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: const Locale('ru'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AddFriendPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('добавить'), findsOneWidget);
    expect(find.text('из контактов'), findsOneWidget);
    expect(find.text('поиск по никнейму'), findsOneWidget);
    expect(find.text('по номеру телефона'), findsOneWidget);
    expect(find.text('из соцсетей'), findsOneWidget);
    expect(find.text('позови ещё больше друзей'), findsOneWidget);
    expect(find.text('пригласить'), findsOneWidget);
    expect(find.byType(GlassSearchBar), findsNothing);
    expect(find.byType(BottomAmbientGlow), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
