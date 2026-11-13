import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/reply_composer_preview.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/theme/theme.dart';
import 'package:yap_chat/ui/widgets/animated_status_switcher.dart';
import 'package:yap_chat/ui/widgets/chat_app_bar.dart';
import 'package:yap_chat/ui/widgets/chat_glass_surface.dart';
import 'package:yap_chat/ui/widgets/glass_icon_button.dart';
import 'package:yap_chat/ui/widgets/gradient_overlay.dart';
import 'package:yap_chat/ui/widgets/message_input_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets(
    'online header is brighter blue and animates from a stable edge',
    (tester) async {
      Widget header(bool online) => _app(
        ChatAppBar(
          userName: 'Собеседник',
          isOnline: online,
          lastSeenAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
      );
      await tester.pumpWidget(header(false));
      final switcher = find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedStatusSwitcher &&
            widget.alignment == AlignmentDirectional.centerStart,
      );
      final oldText = find.descendant(
        of: switcher,
        matching: find.byType(Text),
      );
      final anchor = tester.getTopLeft(oldText);
      final headerSize = tester.getSize(find.byType(ChatAppBar));

      await tester.pumpWidget(header(true));
      final online = find.text('в сети');
      final style = tester.widget<Text>(online).style!;
      expect(style.color, AppColors.incomingBubble);
      expect(
        style.color!.computeLuminance(),
        greaterThan(AppColors.brandPrimary.computeLuminance()),
      );
      expect(style.shadows, isNull);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.fontSize, 14);
      for (var frame = 0; frame < 7; frame++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(tester.getTopLeft(online).dx, anchor.dx);
        expect(tester.getTopLeft(online).dy, closeTo(anchor.dy, 1));
        expect(tester.getSize(find.byType(ChatAppBar)), headerSize);
        if (frame == 1) {
          final fade = tester.widget<FadeTransition>(
            find
                .ancestor(of: online, matching: find.byType(FadeTransition))
                .first,
          );
          final scale = tester.widget<ScaleTransition>(
            find
                .ancestor(of: online, matching: find.byType(ScaleTransition))
                .first,
          );
          expect(fade.opacity.value, inExclusiveRange(0.0, 1.0));
          expect(scale.scale.value, inExclusiveRange(0.94, 1.0));
        }
      }
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: switcher, matching: find.byType(ScaleTransition)),
        findsOneWidget,
      );

      // An interrupted transition must keep both outgoing and incoming labels
      // at the same start edge, rather than briefly centering the shorter one.
      for (final onlineState in [false, true, false]) {
        await tester.pumpWidget(header(onlineState));
        await tester.pump(const Duration(milliseconds: 45));
        for (final element in oldText.evaluate()) {
          final position = tester.getTopLeft(find.byWidget(element.widget));
          expect(position.dx, anchor.dx);
          expect(position.dy, closeTo(anchor.dy, 1));
        }
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('directional status transition respects RTL start edge', (
    tester,
  ) async {
    Widget status(String value) => _app(
      Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          width: 300,
          child: AnimatedStatusSwitcher(
            alignment: AlignmentDirectional.centerStart,
            scaleAlignment: AlignmentDirectional.centerStart,
            scaleBegin: 0.94,
            child: Text(value, key: ValueKey(value)),
          ),
        ),
      ),
    );
    await tester.pumpWidget(status('long offline status'));
    final right = tester.getTopRight(find.text('long offline status')).dx;
    await tester.pumpWidget(status('online'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getTopRight(find.text('online')).dx, right);
    await tester.pumpAndSettle();
    expect(tester.getTopRight(find.text('online')).dx, right);
  });

  testWidgets(
    'shared status and non-chat glass keep their original appearance',
    (tester) async {
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnimatedStatusSwitcher(child: Text('badge')),
              GlassIconButton(icon: Icons.add, chatStyle: false, onTap: () {}),
            ],
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(AnimatedStatusSwitcher),
          matching: find.byType(ScaleTransition),
        ),
        findsOneWidget,
      );
      expect(find.byType(ChatGlassSurface), findsNothing);
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(GlassIconButton),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, AppColors.textPrimary.withValues(alpha: 0.15));
    },
  );

  testWidgets('chat glass preserves button/content size and tap handling', (
    tester,
  ) async {
    var taps = 0;
    Widget button(bool chatStyle) => _app(
      GlassIconButton(
        icon: Icons.add,
        chatStyle: chatStyle,
        onTap: () => taps++,
      ),
    );
    await tester.pumpWidget(button(false));
    final oldSize = tester.getSize(find.byType(GlassIconButton));
    final oldInkRect = tester.getRect(find.byType(InkWell));
    await tester.pumpWidget(button(true));
    expect(tester.getSize(find.byType(GlassIconButton)), oldSize);
    expect(tester.getRect(find.byType(InkWell)), oldInkRect);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(blur.filter, ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12));
    await tester.tap(find.byIcon(Icons.add));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'glass is visibly lighter on black while preserving transparency',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 50,
            height: 50,
            child: ChatGlassSurface(borderRadius: 20, child: SizedBox.expand()),
          ),
        ),
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(BackdropFilter),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      for (final color in gradient.colors) {
        expect(color.a, lessThan(1));
        final composited = Color.alphaBlend(color, Colors.black);
        expect(composited.computeLuminance(), greaterThan(0.01));
        expect(composited.computeLuminance(), lessThan(0.06));
      }
      expect(
        Color.alphaBlend(
          gradient.colors.first,
          Colors.black,
        ).computeLuminance(),
        greaterThan(
          Color.alphaBlend(
            gradient.colors.last,
            Colors.black,
          ).computeLuminance(),
        ),
      );
    },
  );

  testWidgets(
    'new reply material leaves text and close-button geometry intact',
    (tester) async {
      var jumps = 0;
      var clears = 0;
      final message = _message();
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 320,
            child: ReplyComposerPreview(
              message: message,
              peerName: 'Собеседник',
              onTap: () => jumps++,
              onClear: () => clears++,
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(ReplyComposerPreview));
      final textRect = tester.getRect(find.text(message.text));
      final closeRect = tester.getRect(find.byType(IconButton));
      final content = tester
          .widget<ChatGlassSurface>(find.byType(ChatGlassSurface))
          .child;
      await tester.tap(find.text(message.text));
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(jumps, 1);
      expect(clears, 1);

      // Render exactly the same content in the old material to verify that
      // changing the stroke/filter did not change the available content area.
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 320,
            child: Container(
              key: const ValueKey('legacy-reply'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.textPrimary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18.5),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: ColoredBox(
                    color: AppColors.textPrimary.withValues(alpha: 0.15),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const ValueKey('legacy-reply'))), size);
      expect(tester.getRect(find.text(message.text)), textRect);
      expect(tester.getRect(find.byType(IconButton)), closeRect);
      expect(tester.takeException(), isNull);
    },
  );

  for (final screenSize in [const Size(390, 780), const Size(780, 390)]) {
    for (final textScale in [1.0, 1.6]) {
      testWidgets('chat surfaces layout $screenSize textScale=$textScale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(screenSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          _app(
            RepaintBoundary(
              key: captureKey,
              child: ColoredBox(color: Colors.black, child: _preview()),
            ),
            textScale: textScale,
            center: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ChatGlassSurface), findsNWidgets(5));
        expect(tester.getSize(find.byType(TextField)).height, greaterThan(0));

        if (Platform.environment['CAPTURE_CHAT_UI'] == 'true' &&
            textScale == 1) {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final path = 'output/chat-glass-${screenSize.width.toInt()}.png';
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(path);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}

ChatMessage _message() => ChatMessage(
  id: 'quoted',
  chatId: 'chat',
  senderId: 'peer',
  text: 'Текст сообщения, на которое отвечаем',
  timestamp: DateTime(2026),
  isMine: false,
);

Widget _preview() => SizedBox.expand(
  child: Stack(
    children: [
      Positioned.fill(
        child: Column(
          children: List.generate(
            12,
            (index) => Expanded(
              child: Align(
                alignment: index.isEven
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  width: index.isEven ? 210 : 170,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: index.isEven
                        ? AppColors.incomingBubble
                        : const Color(0xFF153C51),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'Сообщение ${index + 1}',
                    style: TextStyle(
                      color: index.isEven
                          ? AppColors.incomingText
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const GradientOverlay(
        height: 95,
        isTop: true,
        backgroundColor: Colors.black,
      ),
      const GradientOverlay(
        height: 140,
        isTop: false,
        backgroundColor: Colors.black,
      ),
      ChatAppBar(userName: 'Собеседник', isOnline: true, onBack: () {}),
      Positioned(
        right: 16,
        bottom: 155,
        child: GlassIconButton(
          icon: Icons.keyboard_arrow_down_rounded,
          chatStyle: true,
          borderRadius: 36,
          iconSize: 36,
          onTap: () {},
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ReplyComposerPreview(
                message: _message(),
                peerName: 'Собеседник',
                onTap: () {},
                onClear: () {},
              ),
            ),
            MessageInputBar(onSend: (_) {}),
          ],
        ),
      ),
    ],
  ),
);

Widget _app(Widget child, {double textScale = 1, bool center = true}) =>
    MaterialApp(
      theme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
        scaffoldBackgroundColor: AppColors.onBrandPrimary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.brandPrimary,
          onPrimary: AppColors.onBrandPrimary,
          surface: AppColors.surfaceOverlay,
          onSurface: AppColors.textPrimary,
        ),
      ),
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: center ? Center(child: child) : child),
    );
