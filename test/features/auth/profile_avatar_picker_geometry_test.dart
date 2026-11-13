import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/widgets/profile_setup_widgets.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  for (final filled in [false, true]) {
    for (final size in [const Size(320, 720), const Size(780, 390)]) {
      testWidgets(
        'onboarding avatar uses profile corners filled=$filled $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var picked = 0;
          var removed = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: ProfileAvatarPicker(
                    avatarUrl: null,
                    localAvatarBytes: filled
                        ? File(
                            'assets/logo/logo_yap_chat.png',
                          ).readAsBytesSync()
                        : null,
                    onPick: () => picked++,
                    onRemove: () => removed++,
                  ),
                ),
              ),
            ),
          );
          final ink = find
              .descendant(
                of: find.byType(ProfileAvatarPicker),
                matching: find.byType(InkWell),
              )
              .first;
          expect(
            tester.widget<InkWell>(ink).borderRadius,
            BorderRadius.circular(44),
          );
          expect(tester.getSize(ink), const Size(220, 220));
          if (filled) {
            expect(
              tester.widget<UserAvatar>(find.byType(UserAvatar)).borderRadius,
              44,
            );
            await tester.tap(find.byIcon(Icons.close_rounded));
            expect(removed, 1);
          } else {
            final background = tester.widget<Container>(
              find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius ==
                        BorderRadius.circular(44),
              ),
            );
            expect(background.decoration, isA<BoxDecoration>());
          }
          await tester.tap(ink);
          expect(picked, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
