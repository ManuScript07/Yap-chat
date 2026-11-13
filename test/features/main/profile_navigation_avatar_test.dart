import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:yap_chat/features/main/main.dart';
import 'package:yap_chat/features/profile/data/data.dart';

Uint8List _bytes(int red, int blue) {
  final image = img.Image(width: 8, height: 8);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixelRgba(x, y, red, 40, blue, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  testWidgets(
    'cached avatar and Image element survive selection changes and metadata refresh',
    (tester) async {
      final bytes = _bytes(200, 20);
      var photo = ProfilePhoto(
        position: 0,
        storagePath: 'owner/a',
        bytes: bytes,
      );
      var selected = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: ProfileNavigationAvatar(
                  key: const ValueKey('owner'),
                  photo: photo,
                  selected: selected,
                  iconColor: Colors.white,
                ),
              );
            },
          ),
        ),
      );
      await _decoded(tester);
      final element = tester.element(find.byType(Image));
      for (var i = 0; i < 12; i++) {
        update(() => selected = !selected);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.element(find.byType(Image)), same(element));
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      }
      update(
        () => photo = const ProfilePhoto(position: 0, storagePath: 'owner/a'),
      );
      await tester.pump();
      final provider =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect((provider.imageProvider as MemoryImage).bytes, same(bytes));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'new photo keeps previous decoded frame, deletion is immediate and final',
    (tester) async {
      ProfilePhoto? photo = ProfilePhoto(
        position: 0,
        storagePath: 'owner/a',
        bytes: _bytes(200, 20),
      );
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: ProfileNavigationAvatar(
                  photo: photo,
                  selected: true,
                  iconColor: Colors.white,
                ),
              );
            },
          ),
        ),
      );
      await _decoded(tester);
      final element = tester.element(find.byType(Image));
      final previousProvider = tester.widget<Image>(find.byType(Image)).image;
      // The existing profile loader can publish new metadata before bytes.
      update(
        () => photo = const ProfilePhoto(position: 0, storagePath: 'owner/b'),
      );
      await tester.pump();
      expect(tester.element(find.byType(Image)), same(element));
      expect(tester.widget<Image>(find.byType(Image)).image, previousProvider);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      update(
        () => photo = ProfilePhoto(
          position: 0,
          storagePath: 'owner/b',
          bytes: _bytes(20, 200),
        ),
      );
      await tester.pump();
      expect(tester.element(find.byType(Image)), same(element));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await _decoded(tester);
      update(() => photo = null);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'active avatar ring is circular white and never changes image size',
    (tester) async {
      var selected = false;
      late StateSetter update;
      final photo = ProfilePhoto(
        position: 0,
        storagePath: 'owner/a',
        bytes: _bytes(20, 100),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: ProfileNavigationAvatar(
                  photo: photo,
                  selected: selected,
                  iconColor: Colors.white,
                ),
              );
            },
          ),
        ),
      );
      await _decoded(tester);
      final before = tester.getSize(find.byType(ClipOval));
      update(() => selected = true);
      await tester.pumpAndSettle();
      final animated = find.byKey(
        const ValueKey('profile_navigation_avatar_ring'),
      );
      final decoration =
          tester.widget<AnimatedContainer>(animated).decoration!
              as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect((decoration.border! as Border).top.color, Colors.white);
      expect(tester.getSize(find.byType(ClipOval)), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'new account and removed Yandex photo cannot reuse previous owner image',
    (tester) async {
      var owner = 'a';
      UserProfile profile = UserProfile(
        id: owner,
        username: 'a',
        displayName: 'a',
        onboardingCompleted: true,
        avatarBytes: _bytes(200, 20),
        avatarStoragePath: 'a/photo',
      );
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: ProfileNavigationAvatar(
                  key: ValueKey(owner),
                  photo: profile.primaryPhoto,
                  selected: false,
                  iconColor: Colors.grey,
                ),
              );
            },
          ),
        ),
      );
      await _decoded(tester);
      update(() {
        owner = 'b';
        profile = const UserProfile(
          id: 'b',
          username: 'b',
          displayName: 'b',
          onboardingCompleted: true,
          yandexAvatarDisabled: true,
        );
      });
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
      // Metadata without cached bytes must not start a separate network load.
      update(
        () => profile = profile.copyWith(
          avatarUrl: 'https://example.invalid/avatar.png',
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _decoded(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    final images = tester.widgetList<RawImage>(find.byType(RawImage));
    if (images.any((image) => image.image != null)) return;
  }
  fail('Cached avatar did not decode');
}
