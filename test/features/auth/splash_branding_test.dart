import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/settings/settings.dart';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets(
      'first splash uses cached ${language.code} without changing layout',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: language.locale,
            supportedLocales: const [Locale('ru'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SplashPage(),
          ),
        );
        final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(
          (svg.bytesLoader as SvgAssetLoader).assetName,
          language == AppLanguage.russian
              ? 'assets/logo/icon_yapchat_foregraund.svg'
              : 'assets/logo/splash_logo_en.svg',
        );
        expect(
          tester.getSize(find.byType(SvgPicture)),
          language == AppLanguage.russian
              ? const Size(157, 137)
              : const Size(288, 288),
        );
        if (language == AppLanguage.russian) {
          final transform = tester.widget<Transform>(
            find
                .ancestor(
                  of: find.byType(SvgPicture),
                  matching: find.byType(Transform),
                )
                .first,
          );
          expect(transform.transform.storage[0], 0.86624205);
          expect(transform.transform.storage[5], 0.86624205);
          expect(transform.alignment, Alignment.center);
        }
        final initialPosition = tester.getTopLeft(find.byType(SvgPicture));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getTopLeft(find.byType(SvgPicture)), initialPosition);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
