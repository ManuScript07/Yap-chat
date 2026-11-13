import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/data/message_text_entity.dart';
import 'package:yap_chat/features/chat/widgets/message_bubble.dart';
import 'package:yap_chat/features/chat/widgets/message_text_content.dart';
import 'package:yap_chat/features/chat/widgets/message_reply_preview.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

void main() {
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'single tap acts immediately despite bubble double-tap; no reaction',
    (tester) async {
      final entities = <MessageTextEntity>[];
      var reactions = 0;
      await tester.pumpWidget(
        _app(
          _bubble(onEntity: entities.add, onReaction: (_, _) => reactions++),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(_textPoint(tester, '@alice'));
      // No 300 ms wait/pump: action must already have fired.
      expect(entities.map((e) => e.text), ['@alice']);
      expect(reactions, 0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'long press copies only the fragment, haptic, no menu or navigation',
    (tester) async {
      final entities = <MessageTextEntity>[];
      var menus = 0;
      await tester.pumpWidget(
        _app(
          _bubble(
            onEntity: entities.add,
            onLongPress: (_) => menus++,
            onReaction: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        _textPoint(tester, 'example.com'),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(entities, isEmpty);
      expect(menus, 0);
      expect(
        calls.where((c) => c.method == 'Clipboard.setData').single.arguments,
        {'text': 'example.com'},
      );
      expect(
        calls.where((c) => c.method == 'HapticFeedback.vibrate'),
        hasLength(1),
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('plain text preserves message menu and double-tap reaction', (
    tester,
  ) async {
    var menus = 0;
    var reactions = 0;
    await tester.pumpWidget(
      _app(
        _bubble(
          onEntity: (_) {},
          onLongPress: (_) => menus++,
          onReaction: (_, _) => reactions++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final point = _textPoint(tester, 'hello');
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(reactions, 1);
    final gesture = await tester.startGesture(point);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(menus, 1);
    expect(calls.where((c) => c.method == 'Clipboard.setData'), isEmpty);
  });
  testWidgets('drag beginning on link scrolls rather than activating/copying', (
    tester,
  ) async {
    final entities = <MessageTextEntity>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              _bubble(onEntity: entities.add),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(_textPoint(tester, '@alice'));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(entities, isEmpty);
    expect(calls.where((c) => c.method == 'Clipboard.setData'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancelled gesture never acts', (tester) async {
    final entities = <MessageTextEntity>[];
    await tester.pumpWidget(_app(_bubble(onEntity: entities.add)));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(_textPoint(tester, '@alice'));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(entities, isEmpty);
    expect(calls.where((c) => c.method == 'Clipboard.setData'), isEmpty);
  });
  testWidgets(
    'changed text replaces/disposes recognizers and uses latest callback',
    (tester) async {
      final entities = <MessageTextEntity>[];
      await tester.pumpWidget(_app(_bubble(onEntity: entities.add)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _app(_bubble(text: 'hello @bob', onEntity: entities.add)),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(_textPoint(tester, '@bob'));
      expect(entities.single.target, 'bob');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('accessibility accepts inline recognizers without assertion', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_bubble(onEntity: (_) {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets(
    'reply preview remains plain and navigates only to source message',
    (tester) async {
      var replies = 0;
      final entities = <MessageTextEntity>[];
      await tester.pumpWidget(
        _app(
          _bubble(
            onEntity: entities.add,
            reply: const MessageReply(
              messageId: 'source',
              senderId: 'peer',
              isMine: false,
              text: '@quoted https://example.org',
              type: MessageType.text,
            ),
            onReply: () => replies++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MessageReplyPreview));
      await tester.pumpAndSettle();
      expect(replies, 1);
      expect(entities, isEmpty);
      expect(find.byType(MessageTextContent), findsOneWidget);
    },
  );

  for (final mine in [false, true]) {
    testWidgets(
      'underline uses message text color even with inherited decoration: mine=$mine',
      (tester) async {
        await tester.pumpWidget(
          _app(
            DefaultTextStyle(
              style: const TextStyle(decorationColor: Colors.red),
              child: _bubble(mine: mine, onEntity: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final content = tester.widget<MessageTextContent>(
          find.byType(MessageTextContent),
        );
        final rich = tester.widget<RichText>(
          find
              .descendant(
                of: find.byType(MessageTextContent),
                matching: find.byType(RichText),
              )
              .first,
        );
        var linkCount = 0;
        void checkSpans(InlineSpan span, TextStyle? inherited) {
          if (span is! TextSpan) return;
          final effective = inherited?.merge(span.style) ?? span.style;
          if (span.recognizer != null) {
            linkCount++;
            expect(span.style!.decoration, TextDecoration.underline);
            expect(span.style!.decorationColor, content.style.color);
            expect(effective?.color, content.style.color);
          }
          for (final child in span.children ?? const <InlineSpan>[]) {
            checkSpans(child, effective);
          }
        }

        checkSpans(rich.text, null);
        expect(linkCount, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [180.0, 300.0]) {
    for (final scale in [1.0, 1.8]) {
      for (final reactions in [false, true]) {
        testWidgets(
          'same layout as plain text: width=$width scale=$scale reactions=$reactions',
          (tester) async {
            const text =
                'hello @alice example.com +79991234567 long words wrap';
            await tester.pumpWidget(
              _app(
                SingleChildScrollView(
                  child: _bubble(
                    text: text,
                    width: width,
                    reactions: reactions,
                  ),
                ),
                scale: scale,
              ),
            );
            await tester.pumpAndSettle();
            final original = tester.getSize(find.byType(MessageBubble));
            await tester.pumpWidget(
              _app(
                SingleChildScrollView(
                  child: _bubble(
                    text: text,
                    onEntity: (_) {},
                    width: width,
                    reactions: reactions,
                  ),
                ),
                scale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.getSize(find.byType(MessageBubble)), original);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

Offset _textPoint(WidgetTester tester, String fragment) {
  final rich = find
      .descendant(
        of: find.byType(MessageTextContent),
        matching: find.byType(RichText),
      )
      .first;
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  final text = paragraph.text.toPlainText();
  final offset = text.indexOf(fragment);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: offset, extentOffset: offset + fragment.length),
  );
  return paragraph.localToGlobal(boxes.first.toRect().center);
}

Widget _bubble({
  String text = 'hello @alice example.com +79991234567',
  double width = 300,
  bool reactions = false,
  bool mine = true,
  ValueChanged<MessageTextEntity>? onEntity,
  ValueChanged<ChatMessage>? onLongPress,
  void Function(ReactionCode, bool)? onReaction,
  MessageReply? reply,
  VoidCallback? onReply,
}) => MessageBubble(
  message: ChatMessage(
    id: 'message',
    chatId: 'chat',
    senderId: mine ? 'me' : 'peer',
    text: text,
    timestamp: DateTime(2026),
    isMine: mine,
    replyTo: reply,
    reactionState: reactions
        ? const MessageReactionState(
            version: 1,
            reactions: [
              MessageReaction(userId: 'peer', code: ReactionCode.heart),
            ],
          )
        : const MessageReactionState(),
  ),
  initialAnimationProgress: 1,
  maxWidth: width,
  peerName: 'Peer',
  onTextEntityTap: onEntity,
  onLongPress: onLongPress,
  onReaction: onReaction,
  onReplyTap: onReply,
);

Widget _app(Widget child, {double scale = 1}) => BlocProvider<AuthBloc>.value(
  value: _Auth(),
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Align(alignment: Alignment.topCenter, child: child),
    ),
  ),
);

class _Auth implements AuthBloc {
  @override
  AuthState get state => const AuthState(session: AuthSession(userId: 'me'));
  @override
  Stream<AuthState> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
