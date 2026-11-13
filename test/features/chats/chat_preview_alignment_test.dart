import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });

  for (final language in ['ru', 'en']) {
    for (final size in [const Size(320, 720), const Size(780, 390)]) {
      for (final scale in [1.0, 2.0]) {
        for (final type in ChatPreviewType.values) {
          testWidgets(
            'preview stays at start $language $size scale=$scale type=$type',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              addTearDown(tester.view.resetDevicePixelRatio);
              addTearDown(tester.view.resetPhysicalSize);
              final chat = ValueNotifier(
                Chat(
                  id: 'chat',
                  userName: 'Peer',
                  lastMessage:
                      'Long initial preview repeated several times to occupy the whole available width',
                  lastMessageTime: DateTime(2026, 10, 28, 12),
                  unreadCount: 3,
                  isOnline: false,
                  isLastMessageFromMe: false,
                ),
              );
              addTearDown(chat.dispose);
              await tester.pumpWidget(
                MaterialApp(
                  theme: ThemeData.dark().copyWith(
                    textTheme: ThemeData.dark().textTheme.apply(
                      fontFamily: 'Roboto',
                    ),
                  ),
                  locale: Locale(language),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      padding: size.width > size.height
                          ? const EdgeInsets.only(left: 28, right: 12)
                          : EdgeInsets.zero,
                    ),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: ValueListenableBuilder<Chat>(
                        valueListenable: chat,
                        builder: (context, value, _) => ChatListItem(
                          key: const ValueKey('row'),
                          chat: value,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final rowRect = tester.getRect(find.byType(ChatListItem));
              final avatar = tester.element(find.byType(UserAvatar));
              final start = tester.getTopLeft(find.text('Peer')).dx;
              final l10n = AppLocalizations.of(
                tester.element(find.byType(ChatListItem)),
              )!;
              final replacement = switch (type) {
                ChatPreviewType.text => 'OK',
                ChatPreviewType.image => l10n.chatReplyPhoto,
                ChatPreviewType.audio => l10n.chatReplyAudio,
                ChatPreviewType.location => l10n.chatReplyLocation,
              };
              chat.value = chat.value.copyWith(
                lastMessage: 'OK',
                lastMessageType: type,
              );
              await tester.pump();
              for (var frame = 0; frame < 13; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                expect(
                  tester.getTopLeft(find.text(replacement)).dx,
                  closeTo(start, .01),
                );
                expect(tester.getRect(find.byType(ChatListItem)), rowRect);
                expect(tester.element(find.byType(UserAvatar)), same(avatar));
                expect(tester.takeException(), isNull);
              }
              // Reverse to a long preview while the previous transition has settled.
              const longer =
                  'Another long preview that should keep exactly the same start edge';
              chat.value = chat.value.copyWith(
                lastMessage: longer,
                lastMessageType: ChatPreviewType.text,
              );
              await tester.pump();
              for (var frame = 0; frame < 13; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                expect(
                  tester.getTopLeft(find.text(longer)).dx,
                  closeTo(start, .01),
                );
                expect(tester.takeException(), isNull);
              }
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      }
    }
  }
}
