import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/auth/widgets/profile_setup_widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    for (final size in [
      const Size(320, 720),
      const Size(412, 892),
      const Size(844, 390),
    ]) {
      testWidgets(
        'welcome typography, local logo and sign-in action $locale $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final auth = _Auth();
          addTearDown(auth.close);
          final key = GlobalKey();
          await tester.pumpWidget(
            BlocProvider<AuthBloc>.value(
              value: auth,
              child: _app(
                locale,
                RepaintBoundary(key: key, child: const WelcomePage()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(WelcomePage)),
          )!;
          final title = tester.widget<Text>(find.text(l10n.authWelcomeTitle));
          expect(title.style!.fontSize, 32);
          expect(title.style!.fontWeight, FontWeight.w700);
          expect(title.style!.height, 20 / 32);
          expect(title.style!.letterSpacing, .32);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(l10n.authWelcomeTitle),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(title.style!.color, AppColors.onBrandPrimary);
          final caption = tester.widget<Text>(find.text(l10n.authSignInWith));
          expect(caption.style!.fontSize, 22);
          expect(caption.style!.fontWeight, FontWeight.w500);
          expect(caption.style!.height, 20 / 22);
          final logos = tester
              .widgetList<SvgPicture>(find.byType(SvgPicture))
              .map((p) => (p.bytesLoader as SvgAssetLoader).assetName)
              .toList();
          expect(
            logos,
            contains(
              locale.languageCode == 'ru'
                  ? 'assets/logo/welcome_big_logo.svg'
                  : 'assets/logo/YAPCHAT_welcome_big_logo.svg',
            ),
          );
          final legal = find.textContaining(
            l10n.authConsentPrefix,
            findRichText: true,
          );
          expect(
            tester.getRect(find.byType(FilledButton)).bottom,
            lessThan(tester.getRect(legal).top),
          );
          expect(auth.events, isEmpty);
          await _capture(
            tester,
            key,
            'welcome-${locale.languageCode}-${size.width.toInt()}',
          );
          await tester.tap(find.byType(FilledButton));
          expect(auth.events, [const YandexSignInRequested()]);
          final other = Locale(locale.languageCode == 'ru' ? 'en' : 'ru');
          await tester.pumpWidget(
            BlocProvider<AuthBloc>.value(
              value: auth,
              child: _app(
                other,
                RepaintBoundary(key: key, child: const WelcomePage()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widgetList<SvgPicture>(find.byType(SvgPicture))
                .map((p) => (p.bytesLoader as SvgAssetLoader).assetName),
            contains(
              other.languageCode == 'ru'
                  ? 'assets/logo/welcome_big_logo.svg'
                  : 'assets/logo/YAPCHAT_welcome_big_logo.svg',
            ),
          );
          expect(auth.events, hasLength(1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );

      for (final keyboard in [false, true]) {
        testWidgets(
          'birth date matches Figma without glyph clipping $locale $size keyboard=$keyboard',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.view.viewInsets = FakeViewPadding(
              bottom: keyboard ? 220 : 0,
            );
            addTearDown(tester.view.reset);
            final controllers = [
              TextEditingController(),
              TextEditingController(text: '02'),
              TextEditingController(text: '2007'),
            ];
            final nodes = [FocusNode(), FocusNode(), FocusNode()];
            addTearDown(() {
              for (final c in controllers) {
                c.dispose();
              }
              for (final n in nodes) {
                n.dispose();
              }
            });
            final key = GlobalKey();
            await tester.pumpWidget(
              _app(
                locale,
                RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    body: Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context)!;
                        return ProfileSetupStep(
                          title: l10n.authOnboardingBirthDateTitle,
                          subtitle: l10n.authOnboardingBirthDateHint,
                          child: OnboardingBirthDateFields(
                            dayController: controllers[0],
                            monthController: controllers[1],
                            yearController: controllers[2],
                            dayFocusNode: nodes[0],
                            monthFocusNode: nodes[1],
                            yearFocusNode: nodes[2],
                            dayHint: l10n.authBirthDateDay,
                            monthHint: l10n.authBirthDateMonth,
                            yearHint: l10n.authBirthDateYear,
                            onChanged: () {},
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final title = tester.widget<Text>(
              find.byWidgetPredicate(
                (w) => w is Text && w.style?.fontWeight == FontWeight.w800,
              ),
            );
            expect(title.style!.fontSize, 42);
            expect(title.style!.height, 52 / 42);
            expect(title.style!.letterSpacing, .42);
            final fields = tester
                .widgetList<TextField>(find.byType(TextField))
                .toList();
            for (final field in fields) {
              expect(field.style!.fontSize, 32);
              expect(field.style!.fontWeight, FontWeight.w700);
              expect(field.decoration!.hintStyle!.fontSize, 32);
              expect(field.decoration!.hintStyle!.fontWeight, FontWeight.w700);
              expect(field.style!.color, AppColors.textPrimary);
            }
            // Check actual editable layout, not only configured font sizes.
            final editables = tester.allRenderObjects
                .whereType<RenderEditable>()
                .toList();
            expect(editables, hasLength(3));
            for (var index = 0; index < editables.length; index++) {
              final render = editables[index];
              expect(render.preferredLineHeight, greaterThanOrEqualTo(32));
              expect(
                render.size.height,
                greaterThanOrEqualTo(render.preferredLineHeight - .01),
              );
              final field = fields[index];
              final value = field.controller!.text.isEmpty
                  ? field.decoration!.hintText!
                  : field.controller!.text;
              final painter = TextPainter(
                text: TextSpan(text: value, style: field.style),
                textDirection: TextDirection.ltr,
              )..layout();
              expect(
                painter.width,
                lessThanOrEqualTo(render.size.width + .1),
                reason:
                    'Visible digits/hint must fit without horizontal clipping: $value',
              );
              painter.dispose();
            }
            await _capture(
              tester,
              key,
              'birth-${locale.languageCode}-${size.width.toInt()}-$keyboard',
            );
            for (final controller in controllers) {
              controller.clear();
            }
            await tester.pumpAndSettle();
            for (var index = 0; index < fields.length; index++) {
              final painter = TextPainter(
                text: TextSpan(
                  text: fields[index].decoration!.hintText,
                  style: fields[index].decoration!.hintStyle,
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              expect(
                painter.width,
                lessThanOrEqualTo(editables[index].size.width + .1),
                reason: 'Empty date hints must fit, including mm/yyyy.',
              );
              painter.dispose();
            }
            controllers[2].text = '2007';
            await tester.enterText(find.byType(TextField).first, '15');
            expect(controllers[0].text, '15');
            expect(nodes[1].hasFocus, isTrue);
            expect(controllers[2].text, '2007');
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}

Widget _app(Locale locale, Widget home) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark().copyWith(
    scaffoldBackgroundColor: Colors.black,
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
    colorScheme: const ColorScheme.dark(
      primary: AppColors.brandPrimary,
      onPrimary: AppColors.onBrandPrimary,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
    ),
  ),
  home: home,
);

class _Auth extends Cubit<AuthState> implements AuthBloc {
  _Auth() : super(const AuthState(status: AuthStatus.unauthenticated));
  final events = <AuthEvent>[];
  @override
  void add(AuthEvent event) => events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CAPTURE_AUTH_FIGMA'] != 'true') return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('tmp/$name.png').writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}
