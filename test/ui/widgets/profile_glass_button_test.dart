import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/ui/theme/theme.dart';
import 'package:yap_chat/ui/widgets/chat_glass_surface.dart';
import 'package:yap_chat/ui/widgets/glass_button.dart';

void main() {
  testWidgets('frosted profile button preserves geometry, icon and callback', (
    tester,
  ) async {
    var taps = 0;
    Widget button(bool frosted) => _app(
      GlassButton(
        frostedStyle: frosted,
        icon: Icons.settings_rounded,
        size: 50,
        iconSize: 29,
        borderRadius: 20,
        onPressed: () => taps++,
      ),
    );
    await tester.pumpWidget(button(false));
    final buttonRect = tester.getRect(find.byType(GlassButton));
    final iconRect = tester.getRect(find.byType(Icon));

    await tester.pumpWidget(button(true));
    expect(tester.getRect(find.byType(GlassButton)), buttonRect);
    expect(tester.getRect(find.byType(Icon)), iconRect);
    expect(
      tester.widget<Icon>(find.byType(Icon)).color,
      AppColors.surfaceOverlay,
    );
    final surface = tester.widget<ChatGlassSurface>(
      find.byType(ChatGlassSurface),
    );
    expect(surface.borderRadius, 20);
    expect(surface.lightStyle, isTrue);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
      ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
    );
    await tester.tap(find.byIcon(Icons.settings_rounded));
    // The transparent space around the icon remains part of the hit target.
    await tester.tapAt(buttonRect.topLeft + const Offset(15, 15));
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled frosted profile button has no tap callback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const GlassButton(frostedStyle: true, icon: Icons.visibility_rounded),
      ),
    );
    expect(
      tester.widget<GestureDetector>(find.byType(GestureDetector)).onTap,
      isNull,
    );
    await tester.tap(find.byIcon(Icons.visibility_rounded));
    expect(tester.takeException(), isNull);
  });

  testWidgets('other GlassButton callers keep the original material', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const GlassButton(icon: Icons.close_rounded)));
    expect(find.byType(ChatGlassSurface), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.getSize(find.byType(GlassButton)), const Size(40, 40));
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(GlassButton),
        matching: find.byType(Container),
      ),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.surfaceOverlay.withValues(alpha: 0.4));
    expect(decoration.borderRadius, BorderRadius.circular(16));
    expect(
      decoration.border,
      Border.all(
        color: AppColors.surfaceOverlay.withValues(alpha: 0.8),
        width: 2,
      ),
    );
  });

  testWidgets(
    'profile uses a light tint while default chat tint stays unchanged',
    (tester) async {
      Widget surface(bool light) => _app(
        SizedBox.square(
          dimension: 50,
          child: ChatGlassSurface(
            lightStyle: light,
            borderRadius: 20,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      LinearGradient gradient() =>
          (tester
                          .widgetList<DecoratedBox>(
                            find.descendant(
                              of: find.byType(BackdropFilter),
                              matching: find.byType(DecoratedBox),
                            ),
                          )
                          .single
                          .decoration
                      as BoxDecoration)
                  .gradient!
              as LinearGradient;

      await tester.pumpWidget(surface(true));
      BoxShadow shadow() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byType(ChatGlassSurface),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .boxShadow!
              .single;
      expect(shadow().color, AppColors.textPrimary.withValues(alpha: 0.12));
      expect(shadow().blurRadius, 8);
      expect(shadow().offset, const Offset(0, 2));
      expect(gradient().colors.map((color) => color.toARGB32()), [
        AppColors.textPrimary.withValues(alpha: 0.40).toARGB32(),
        AppColors.textPrimary.withValues(alpha: 0.32).toARGB32(),
      ]);
      final lightPainter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(ChatGlassSurface),
              matching: find.byType(CustomPaint),
            ),
          )
          .foregroundPainter!;
      await tester.pumpWidget(surface(false));
      expect(shadow().color, AppColors.onBrandPrimary.withValues(alpha: 0.12));
      expect(shadow().blurRadius, 8);
      expect(shadow().offset, const Offset(0, 2));
      final tint = AppColors.onBrandPrimary.withValues(alpha: 0.10);
      expect(gradient().colors, [
        Color.alphaBlend(AppColors.textPrimary.withValues(alpha: 0.18), tint),
        Color.alphaBlend(AppColors.textPrimary.withValues(alpha: 0.12), tint),
      ]);
      final defaultPainter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(ChatGlassSurface),
              matching: find.byType(CustomPaint),
            ),
          )
          .foregroundPainter!;
      expect(defaultPainter.shouldRepaint(lightPainter), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: theme,
  home: Scaffold(body: Center(child: child)),
);
