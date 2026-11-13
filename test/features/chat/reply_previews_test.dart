import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/message_reply_preview.dart';
import 'package:yap_chat/features/chat/widgets/reply_composer_preview.dart';
import 'package:yap_chat/features/chat/widgets/reply_preview_mode.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/theme/app_text_styles.dart';
import 'package:yap_chat/ui/widgets/message_input_bar.dart';

void main() {
  for (final mode in ReplyPreviewMode.values) {
    for (final mine in [false, true]) {
      for (final type in MessageType.values) {
        testWidgets('reply mode=$mode mine=$mine type=$type', (tester) async {
          final message = _message(type, mine);
          final reply = MessageReply.fromMessage(message);
          for (final composer in [false, true]) {
            await tester.pumpWidget(
              _app(
                SizedBox(
                  width: 300,
                  child: composer
                      ? ReplyComposerPreview(
                          message: message,
                          peerName: 'Peer',
                          onClear: () {},
                        )
                      : MessageReplyPreview(
                          reply: reply,
                          peerName: 'Peer',
                          isMessageMine: mine,
                          mode: mode,
                        ),
                ),
              ),
            );
            final context = tester.element(
              find.byType(
                composer ? ReplyComposerPreview : MessageReplyPreview,
              ),
            );
            final l10n = AppLocalizations.of(context)!;
            final body = switch (type) {
              MessageType.text => message.text,
              MessageType.image => l10n.chatReplyPhoto,
              MessageType.audio => l10n.chatReplyAudio,
              MessageType.location => l10n.chatReplyLocation,
            };
            final text = tester.widget<Text>(find.text(body));
            expect(text.maxLines, 2);
            expect(text.overflow, TextOverflow.ellipsis);
            expect(
              text.style!.fontSize,
              composer ? 14 : AppTextStyles.messageBody.fontSize,
            );
            expect(
              text.style!.fontWeight,
              composer ? null : AppTextStyles.messageBody.fontWeight,
            );
            expect(
              text.style!.height,
              composer ? null : AppTextStyles.messageBody.height,
            );
            expect(
              text.style!.letterSpacing,
              composer ? null : AppTextStyles.messageBody.letterSpacing,
            );
            final author = mine ? l10n.chatReplyYou : 'Peer';
            expect(
              find.text(composer ? l10n.chatReplyingTo(author) : author),
              composer || mode == ReplyPreviewMode.group
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
    for (final width in [180.0, 320.0, 600.0]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets('reply layout mode=$mode width=$width scale=$scale', (
          tester,
        ) async {
          await tester.pumpWidget(
            _app(
              SingleChildScrollView(
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      MessageReplyPreview(
                        reply: MessageReply.fromMessage(
                          _message(MessageType.text, false),
                        ),
                        peerName: 'A very long peer name ' * 10,
                        isMessageMine: false,
                        mode: mode,
                      ),
                      ReplyComposerPreview(
                        message: _message(MessageType.text, false),
                        peerName: 'A very long peer name ' * 10,
                        onClear: () {},
                      ),
                    ],
                  ),
                ),
              ),
              textScale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final preview in [
            find.byType(MessageReplyPreview),
            find.byType(ReplyComposerPreview),
          ]) {
            final rect = tester.getRect(preview);
            expect(rect.width, lessThanOrEqualTo(width));
          }
        });
      }
    }
  }

  testWidgets(
    'composer tap navigates without clearing draft or stealing focus; close only clears reply',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var jumps = 0;
      var clears = 0;
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReplyComposerPreview(
                message: _message(MessageType.text, false),
                peerName: 'Peer',
                onTap: () => jumps++,
                onClear: () => clears++,
              ),
              MessageInputBar(focusNode: focus, onSend: (_) {}),
            ],
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'draft stays');
      await tester.pumpAndSettle();
      await tester.tap(find.text(_message(MessageType.text, false).text));
      await tester.pumpAndSettle();
      expect(jumps, 1);
      expect(clears, 0);
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'draft stays',
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(jumps, 1);
      expect(clears, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

ChatMessage _message(MessageType type, bool mine) => ChatMessage(
  id: 'original',
  chatId: 'chat',
  senderId: mine ? 'me' : 'peer',
  text: 'Quoted text with unchanged truncation rules. ' * 20,
  timestamp: DateTime(2026),
  isMine: mine,
  type: type,
);

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.android),
  locale: const Locale('ru'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (_, child) => MediaQuery(
    data: const MediaQueryData().copyWith(
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: Scaffold(body: Center(child: child)),
);
