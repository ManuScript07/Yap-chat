import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  setUpAll(() async {
    AppTextStyles.chatName = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 18,
      height: 1.33,
    );
    AppTextStyles.messagePreview = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 16,
      height: 1.25,
    );
    AppTextStyles.metadata = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 14,
      height: 1.14,
    );
    AppTextStyles.badgeText = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 14,
      height: 1.14,
    );
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final ratio in [1.0, 2.0, 3.0]) {
    testWidgets(
      'resting chat/friend rows preserve the common avatar mask at DPR $ratio',
      (tester) async {
        tester.view.physicalSize = Size(390 * ratio, 844 * ratio);
        tester.view.devicePixelRatio = ratio;
        addTearDown(tester.view.reset);
        final presence = PresenceCubit(repository: MockPresenceRepository());
        final chatKey = GlobalKey(),
            friendKey = GlobalKey(),
            controlKey = GlobalKey();
        await tester.pumpWidget(
          BlocProvider.value(
            value: presence,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                scaffoldBackgroundColor: Colors.black,
                colorScheme: const ColorScheme.dark(
                  primary: Colors.white,
                  onSurface: Colors.white,
                ),
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Column(
                  children: [
                    RepaintBoundary(
                      key: chatKey,
                      child: ChatListItem(
                        chat: Chat(
                          id: 'c',
                          peerId: '',
                          userName: 'Peer',
                          lastMessage: 'Text',
                          lastMessageTime: DateTime(2026),
                          unreadCount: 0,
                          isOnline: false,
                          isLastMessageFromMe: false,
                          isMuted: false,
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      key: friendKey,
                      child: FriendListItem(
                        friend: Friend(
                          id: 'f',
                          username: 'peer',
                          displayName: 'Peer',
                          friendsSince: DateTime(2026),
                        ),
                        onChat: () {},
                        onLocation: () {},
                      ),
                    ),
                    RepaintBoundary(
                      key: controlKey,
                      child: const UserAvatar(size: 56),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final deviations = <double>[];
        for (final (key, size) in [
          (chatKey, 56.0),
          (friendKey, 54.0),
          (controlKey, 56.0),
        ]) {
          final row = find.byKey(key);
          final avatarFinder = find.descendant(
            of: row,
            matching: find.byType(UserAvatar),
          );
          final clip = find.descendant(
            of: avatarFinder,
            matching: find.byType(ClipRRect),
          );
          expect(tester.getSize(avatarFinder), Size.square(size));
          expect(tester.getSize(clip), Size.square(size));
          final radius = tester
              .widget<ClipRRect>(clip)
              .borderRadius
              .resolve(TextDirection.ltr);
          expect(radius.topLeft, radius.topRight);
          expect(radius.topLeft, radius.bottomLeft);
          expect(radius.topLeft, radius.bottomRight);
          expect(radius.topLeft.x / size, closeTo(.4, 1e-12));
          final rect = tester.getRect(clip).shift(-tester.getTopLeft(row));
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: ratio);
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final bytes = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
            final left = (rect.left * ratio).round(),
                top = (rect.top * ratio).round();
            final n = (size * ratio).round();
            int value(int x, int y) =>
                bytes[((top + y) * image.width + left + x) * 4];
            var maxBoundaryDifference = 0.0;
            for (var y = 0; y < n ~/ 3; y++) {
              final coverage = List.filled(4, 0.0);
              for (var x = 0; x < n ~/ 3; x++) {
                final values = [
                  value(x, y),
                  value(n - 1 - x, y),
                  value(x, n - 1 - y),
                  value(n - 1 - x, n - 1 - y),
                ];
                for (var corner = 0; corner < 4; corner++) {
                  coverage[corner] += values[corner] / 255;
                }
              }
              for (final c in coverage.skip(1)) {
                final difference = (c - coverage.first).abs();
                if (difference > maxBoundaryDifference) {
                  maxBoundaryDifference = difference;
                }
              }
            }
            debugPrint(
              'Avatar size=$size DPR=$ratio origin=$rect max mirrored boundary deviation=$maxBoundaryDifference physical px',
            );
            deviations.add(maxBoundaryDifference);
            image.dispose();
          });
        }
        expect(deviations, hasLength(3));
        expect(
          deviations[0],
          closeTo(deviations[2], .001),
          reason:
              'The chat row must not deform the common avatar mask compared with an isolated avatar.',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(presence.close);
      },
    );
  }
}
