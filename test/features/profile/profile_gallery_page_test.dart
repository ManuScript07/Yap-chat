import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/profile/profile.dart';
import 'package:yap_chat/features/profile/widgets/profile_photo_image.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

void main() {
  testWidgets('keeps the profile thumbnail unchanged during its hero flight', (
    tester,
  ) async {
    final photo = ProfilePhoto(
      position: 0,
      bytes: Uint8List.fromList(const [0]),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: GestureDetector(
              key: const ValueKey('open-profile-gallery'),
              onTap: () => Navigator.of(context).push(
                PageRouteBuilder<void>(
                  transitionDuration: const Duration(milliseconds: 260),
                  pageBuilder: (_, _, _) => ProfileGalleryPage(
                    photos: [photo],
                    initialIndex: 0,
                    initialThumbnailCacheWidth: 352,
                    displayName: 'User',
                    imageAspectRatios: const [2],
                  ),
                ),
              ),
              child: SizedBox.square(
                dimension: 176,
                child: ProfilePhotoHero(
                  photo: photo,
                  borderRadius: 32,
                  cacheWidth: 352,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-profile-gallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    var destination = tester
        .widgetList<ProfilePhotoHero>(find.byType(ProfilePhotoHero))
        .singleWhere((hero) => hero.fit == BoxFit.contain);
    expect(destination.cacheWidth, 352);
    expect(destination.revealOnLoad, isFalse);

    await tester.pumpAndSettle();
    destination = tester
        .widgetList<ProfilePhotoHero>(find.byType(ProfilePhotoHero))
        .singleWhere((hero) => hero.fit == BoxFit.contain);
    expect(destination.cacheWidth, isNull);
    expect(destination.revealOnLoad, isFalse);
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
  });

  testWidgets('uses a stable aspect-fitted hero target', (tester) async {
    final photo = ProfilePhoto(
      position: 0,
      bytes: Uint8List.fromList(const [0]),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileGalleryPage(
          photos: [photo],
          initialIndex: 0,
          displayName: 'User',
          imageAspectRatios: const [2],
        ),
      ),
    );
    await tester.pump();

    final pageSize = tester.getSize(find.byType(PageView));
    final hero = find.byWidgetPredicate(
      (widget) =>
          widget is Hero && widget.tag == 'profile-photo-${photo.identity}',
    );

    expect(hero, findsOneWidget);
    final heroSize = tester.getSize(hero);
    expect(heroSize.aspectRatio, closeTo(2, .001));
    expect(heroSize.width, pageSize.width);
    expect(heroSize.height, lessThan(pageSize.height));

    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
  });

  testWidgets('upgrades the hero thumbnail without a second reveal', (
    tester,
  ) async {
    final photo = ProfilePhoto(
      position: 0,
      bytes: Uint8List.fromList(const [0]),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileGalleryPage(
          photos: [photo],
          initialIndex: 0,
          initialThumbnailCacheWidth: 352,
          displayName: 'User',
          imageAspectRatios: const [2],
        ),
      ),
    );

    var imageHero = tester.widget<ProfilePhotoHero>(
      find.byType(ProfilePhotoHero),
    );
    expect(imageHero.cacheWidth, 352);
    expect(imageHero.revealOnLoad, isFalse);

    await tester.pump();
    await tester.pump();
    imageHero = tester.widget<ProfilePhotoHero>(find.byType(ProfilePhotoHero));
    expect(imageHero.cacheWidth, isNull);
    expect(imageHero.revealOnLoad, isFalse);

    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
  });
}
