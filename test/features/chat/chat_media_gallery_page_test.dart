import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  for (final variant in ['quick', 'remeasure', 'rotate-zoom', 'unknown-size']) {
    testWidgets(
      'scoped photo transition handles $variant without altering fullscreen bounds',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final path = 'scoped-$variant.jpg';
        if (variant != 'unknown-size') chatMediaAspectRatios.remember(path, .5);
        addTearDown(chatMediaAspectRatios.clear);
        await tester.pumpWidget(
          _testApp(
            Scaffold(
              body: Center(
                child: MessageMediaGrid(
                  message: ChatMessage(
                    id: 'scoped',
                    chatId: 'chat',
                    senderId: 'peer',
                    text: '',
                    timestamp: DateTime(2026),
                    isMine: false,
                    type: MessageType.image,
                    mediaUrls: [path],
                  ),
                  maxWidth: 220,
                  senderName: 'Sender',
                ),
              ),
            ),
          ),
        );
        final chrome = find.byType(
          ChatMediaTransitionChrome,
          skipOffstage: false,
        );
        final header = tester.element(chrome);
        final sourceImage = find.descendant(
          of: find.byType(MessageMediaGrid, skipOffstage: false),
          matching: find.byType(ChatMediaImage, skipOffstage: false),
          skipOffstage: false,
        );
        final sourceImageState = tester.state(sourceImage);
        await tester.tap(
          find.descendant(
            of: find.byType(MessageMediaGrid),
            matching: find.byType(InkWell),
          ),
        );
        await tester.pump();
        if (variant == 'quick' || variant == 'remeasure') {
          await tester.pump(const Duration(milliseconds: 40));
        } else {
          await tester.pumpAndSettle();
        }
        final gallery = tester.widget<ChatMediaGalleryPage>(
          find.byType(ChatMediaGalleryPage),
        );
        final galleryImage = find.descendant(
          of: find.byType(ChatMediaGalleryPage),
          matching: find.byWidgetPredicate(
            (widget) => widget is ChatMediaImage && widget.path == path,
            skipOffstage: false,
          ),
          skipOffstage: false,
        );
        final imageState = tester.state(galleryImage);
        expect(gallery.transitionGeometry, isNotNull);
        expect(
          find.descendant(
            of: find.byType(ChatMediaGalleryPage),
            matching: find.byType(GradientOverlay),
          ),
          findsNothing,
          reason: 'chat edge shadows must not cover the gallery photo',
        );
        if (variant == 'remeasure') {
          final flight = gallery.transitionGeometry!.localFlight;
          final progress = flight.progress;
          final opacity = flight.chromeOpacity.value;
          final route = ModalRoute.of(
            tester.element(find.byType(ChatMediaGalleryPage)),
          )!;
          route.offstage = true;
          await tester.pump();
          expect(
            route.animation!.value,
            1,
            reason: 'framework measurement proxy',
          );
          expect(
            flight.progress,
            progress,
            reason: 'visible effects use real route time',
          );
          expect(flight.chromeOpacity.value, opacity);
          expect(flight.isFlying, isTrue);
          route.offstage = false;
          await tester.pump();
          expect(flight.progress, progress);
          expect(flight.chromeOpacity.value, opacity);
        }
        if (variant == 'rotate-zoom') {
          await tester.binding.setSurfaceSize(const Size(780, 390));
          await tester.pumpAndSettle();
          final hero = find.byWidgetPredicate(
            (widget) => widget is Hero && widget.tag == 'chat-media-scoped-0',
          );
          expect(tester.getSize(hero).aspectRatio, closeTo(.5, .001));
          final viewer = tester.widget<InteractiveViewer>(
            find.byType(InteractiveViewer),
          );
          viewer.transformationController!.value = Matrix4.diagonal3Values(
            1.5,
            1.5,
            1,
          );
          await tester.pumpAndSettle();
        }
        if (variant == 'unknown-size') {
          expect(find.byType(ChatMediaFlightPhoto), findsNothing);
        }
        final opacityBeforePop =
            gallery.transitionGeometry!.localFlight.chromeOpacity.value;
        Navigator.of(tester.element(find.byType(ChatMediaGalleryPage))).pop();
        await tester.pump();
        if (variant == 'quick') {
          expect(
            gallery.transitionGeometry!.localFlight.chromeOpacity.value,
            closeTo(opacityBeforePop, .001),
            reason: 'quick reversal must not jump opacity',
          );
        }
        // An opaque gallery need not lay out its covered route on rotation.
        // The source must have current geometry when it becomes visible again.
        if (variant == 'rotate-zoom') {
          expect(gallery.transitionGeometry!.headerRect!.width, 780);
        }
        await tester.pump(const Duration(milliseconds: 15));
        expect(
          tester.state(sourceImage),
          same(sourceImageState),
          reason: 'source thumbnail stream is retained in its placeholder',
        );
        expect(
          tester.state(galleryImage),
          same(imageState),
          reason: 'clipping must not restart the full-image stream or decoder',
        );
        if (variant == 'rotate-zoom') {
          expect(find.byType(ChatMediaFlightPhoto), findsOneWidget);
        }
        await tester.pumpAndSettle();
        expect(find.byType(ChatMediaGalleryPage), findsNothing);
        expect(imageState.mounted, isFalse);
        expect(tester.state(sourceImage), same(sourceImageState));
        expect(find.byType(ChatMediaFlightPhoto), findsNothing);
        expect(tester.element(chrome), same(header));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('consecutive gallery openings keep the first frame stable', (
    tester,
  ) async {
    const path = '/missing-repeat-photo.jpg';
    chatMediaAspectRatios.remember(path, .5);
    addTearDown(chatMediaAspectRatios.clear);
    await tester.pumpWidget(
      _testApp(
        Scaffold(
          body: Center(
            child: MessageMediaGrid(
              message: ChatMessage(
                id: 'repeat',
                chatId: 'chat',
                senderId: 'peer',
                text: '',
                timestamp: DateTime(2026),
                isMine: false,
                type: MessageType.image,
                mediaUrls: [path],
              ),
              maxWidth: 220,
              senderName: 'Sender',
            ),
          ),
        ),
      ),
    );
    final flight = ChatMediaTransitionScope.maybeOf(
      tester.element(find.byType(MessageMediaGrid)),
    )!.localFlight;
    for (var attempt = 0; attempt < 3; attempt++) {
      final initialValues = <double>[];
      void record() => initialValues.add(flight.chromeOpacity.value);
      flight.chromeOpacity.addListener(record);
      await tester.tap(
        find.descendant(
          of: find.byType(MessageMediaGrid),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      flight.chromeOpacity.removeListener(record);
      expect(initialValues, everyElement(1.0), reason: 'opening $attempt');
      expect(flight.progress, 0);
      expect(flight.isFlying, isTrue);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ChatMediaGalleryPage))).pop();
      await tester.pumpAndSettle();
      expect(flight.chromeOpacity.value, 1);
      expect(flight.isFlying, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  for (final interruption in [
    'source-removed',
    'forced-removal',
    'owner-removed',
  ]) {
    testWidgets('local photo transition cleans up $interruption', (
      tester,
    ) async {
      const path = '/missing-interrupted-photo.jpg';
      chatMediaAspectRatios.remember(path, .5);
      addTearDown(chatMediaAspectRatios.clear);
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      await tester.pumpWidget(
        _testApp(
          Scaffold(
            body: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (_, visible, _) => visible
                    ? MessageMediaGrid(
                        message: ChatMessage(
                          id: 'interrupt',
                          chatId: 'chat',
                          senderId: 'peer',
                          text: '',
                          timestamp: DateTime(2026),
                          isMine: false,
                          type: MessageType.image,
                          mediaUrls: [path],
                        ),
                        maxWidth: 220,
                        senderName: 'Sender',
                      )
                    : const SizedBox(),
              ),
            ),
          ),
        ),
      );
      final geometry = ChatMediaTransitionScope.maybeOf(
        tester.element(find.byType(MessageMediaGrid)),
      )!;
      await tester.tap(
        find.descendant(
          of: find.byType(MessageMediaGrid),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(geometry.localFlight.isFlying, isTrue);
      if (interruption == 'owner-removed') {
        await tester.pumpWidget(const SizedBox());
      } else {
        final navigator = Navigator.of(
          tester.element(find.byType(ChatMediaGalleryPage)),
        );
        if (interruption == 'source-removed') {
          await tester.pumpAndSettle();
          shown.value = false;
          await tester.pump();
          navigator.pop();
        } else {
          navigator.removeRoute(
            ModalRoute.of(tester.element(find.byType(ChatMediaGalleryPage)))!,
          );
        }
        await tester.pumpAndSettle();
        expect(geometry.localFlight.isFlying, isFalse);
        expect(geometry.localFlight.chromeOpacity.value, 1);
        expect(find.byType(ChatMediaGalleryPage), findsNothing);
        expect(find.byType(ChatMediaFlightPhoto), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('uses one image layer during push and pop flights', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                key: const ValueKey('open-gallery'),
                onTap: () => Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    transitionDuration: const Duration(milliseconds: 260),
                    reverseTransitionDuration: const Duration(
                      milliseconds: 180,
                    ),
                    pageBuilder: (_, _, _) => ChatMediaGalleryPage(
                      sentAt: DateTime(2026),
                      imagePaths: ['missing-first.jpg'],
                      heroTags: ['media-0'],
                      initialIndex: 0,
                      initialThumbnailCacheWidth: 320,
                      senderName: 'Sender',
                      imageAspectRatios: [4 / 3],
                    ),
                    transitionsBuilder: (_, animation, _, child) =>
                        FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                            reverseCurve: Curves.easeInCubic,
                          ),
                          child: child,
                        ),
                  ),
                ),
                child: const SizedBox(
                  width: 160,
                  height: 120,
                  child: ChatMediaHero(
                    path: 'missing-first.jpg',
                    heroTag: 'media-0',
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-gallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    _expectSingleImageFlight(tester);
    expect(_flightImage(tester).cacheWidth, 320);
    final openingRadius = _flightRadius(tester);
    expect(openingRadius, inExclusiveRange(0, 20));
    await tester.pump(const Duration(milliseconds: 40));
    expect(_flightRadius(tester), lessThan(openingRadius));
    final destinationDuringFlight = tester
        .widgetList<ChatMediaHero>(find.byType(ChatMediaHero))
        .singleWhere((hero) => hero.fit == BoxFit.contain);
    expect(destinationDuringFlight.cacheWidth, 320);
    expect(destinationDuringFlight.revealOnLoad, isFalse);
    expect(find.text('Sender'), findsOneWidget);
    expect(_opacityFor(tester, find.text('Sender')), 0);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.text('Sender'),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );
    final activeFades = tester
        .widgetList<FadeTransition>(
          find.ancestor(
            of: find.text('Sender'),
            matching: find.byType(FadeTransition),
          ),
        )
        .where((fade) => fade.opacity.value > 0 && fade.opacity.value < 1);
    expect(activeFades, isNotEmpty);

    await tester.pumpAndSettle();
    expect(_opacityFor(tester, find.text('Sender')), 1);
    final destinationAfterFlight = tester
        .widgetList<ChatMediaHero>(find.byType(ChatMediaHero))
        .singleWhere((hero) => hero.fit == BoxFit.contain);
    expect(destinationAfterFlight.cacheWidth, isNull);
    expect(destinationAfterFlight.revealOnLoad, isFalse);
    Navigator.of(tester.element(find.byType(ChatMediaGalleryPage))).pop();
    await tester.pump();
    expect(_paintedOpacityFor(tester, find.text('Sender')), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacityFor(tester, find.text('Sender')), 0);
    _expectSingleImageFlight(tester);
    expect(_flightImage(tester).cacheWidth, 320);
    final closingRadius = _flightRadius(tester);
    expect(closingRadius, inExclusiveRange(0, 20));
    await tester.pump(const Duration(milliseconds: 40));
    expect(_flightRadius(tester), greaterThan(closingRadius));
    await tester.pumpAndSettle();
  });

  for (final targetIndex in [1, 2, 4, 5]) {
    testWidgets('return after paging uses album tile $targetIndex corners', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final paths = List.generate(6, (index) => 'album-$index.jpg');
      for (final path in paths) {
        chatMediaAspectRatios.remember(path, 1);
      }
      addTearDown(chatMediaAspectRatios.clear);
      await tester.pumpWidget(
        _testApp(
          Scaffold(
            body: Center(
              child: MessageMediaGrid(
                message: ChatMessage(
                  id: 'album',
                  chatId: 'chat',
                  senderId: 'sender',
                  text: '',
                  timestamp: DateTime(2026),
                  isMine: false,
                  type: MessageType.image,
                  mediaUrls: paths,
                ),
                maxWidth: 200,
                senderName: 'Sender',
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('album:media:0')),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      var corners = _flightCorners(tester);
      expect(corners.topLeft.x, inExclusiveRange(0, 20));
      expect(corners.bottomLeft.x, corners.topLeft.x);
      expect(corners.topRight, Radius.zero);
      expect(corners.bottomRight, Radius.zero);
      await tester.pumpAndSettle();
      for (var index = 0; index < targetIndex; index++) {
        await tester.drag(find.byType(PageView), const Offset(-390, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text('${targetIndex + 1} of 6'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      corners = _flightCorners(tester);
      final mask = {1: 0, 2: 2, 4: 8, 5: 15}[targetIndex]!;
      final radii = [
        corners.topLeft,
        corners.topRight,
        corners.bottomLeft,
        corners.bottomRight,
      ];
      for (var corner = 0; corner < 4; corner++) {
        expect(
          radii[corner].x,
          mask & (1 << corner) == 0 ? 0 : inExclusiveRange(0, 20),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(ChatMediaGalleryPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'rotation preserves chrome state and fits the photo to the viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpGallery(tester);
      await tester.binding.setSurfaceSize(const Size(780, 390));
      await tester.pumpAndSettle();
      expect(_paintedOpacityFor(tester, find.text('Sender')), 1);
      final hero = find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'media-0',
      );
      expect(tester.getSize(hero).aspectRatio, closeTo(2, .001));
      await tester.tapAt(tester.getCenter(find.byType(PageView)));
      await tester.pumpAndSettle();
      expect(_paintedOpacityFor(tester, find.text('Sender')), 0);
      await tester.binding.setSurfaceSize(const Size(390, 780));
      await tester.pumpAndSettle();
      expect(_paintedOpacityFor(tester, find.text('Sender')), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('quick back during opening cleans up the flight and controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      transitionDuration: const Duration(milliseconds: 260),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 180,
                      ),
                      pageBuilder: (_, _, _) => ChatMediaGalleryPage(
                        imagePaths: const ['quick.jpg'],
                        heroTags: const ['quick'],
                        initialIndex: 0,
                        senderName: 'Sender',
                        sentAt: DateTime(2026),
                        imageAspectRatios: const [1],
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
                const SizedBox.square(
                  dimension: 120,
                  child: ChatMediaHero(
                    path: 'quick.jpg',
                    heroTag: 'quick',
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_flightImage(tester).path, 'quick.jpg');
    Navigator.of(tester.element(find.byType(ChatMediaGalleryPage))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Sender'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a stable aspect-fitted hero target', (tester) async {
    await _pumpGallery(tester);

    final pageSize = tester.getSize(find.byType(PageView));
    final hero = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'media-0',
    );

    expect(hero, findsOneWidget);
    final heroSize = tester.getSize(hero);
    expect(heroSize.aspectRatio, closeTo(2, .001));
    expect(heroSize.width, pageSize.width);
    expect(heroSize.height, lessThan(pageSize.height));
  });

  testWidgets('keeps the hero thumbnail until full image takes over', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        ChatMediaGalleryPage(
          sentAt: DateTime(2026),
          imagePaths: ['missing-first.jpg'],
          heroTags: ['media-0'],
          initialIndex: 0,
          initialThumbnailCacheWidth: 320,
          senderName: 'Sender',
          imageAspectRatios: [4 / 3],
        ),
      ),
    );

    var imageHero = tester.widget<ChatMediaHero>(find.byType(ChatMediaHero));
    expect(imageHero.cacheWidth, 320);
    expect(imageHero.revealOnLoad, isFalse);

    await tester.pump();
    await tester.pump();
    imageHero = tester.widget<ChatMediaHero>(find.byType(ChatMediaHero));
    expect(imageHero.cacheWidth, isNull);
    expect(imageHero.revealOnLoad, isFalse);
  });

  testWidgets('shows a counter and toggles gallery chrome on tap', (
    tester,
  ) async {
    await _pumpGallery(tester);

    expect(find.text('1 of 2'), findsOneWidget);
    expect(_opacityFor(tester, find.text('Sender')), 1);
    expect(_opacityFor(tester, find.text('1 of 2')), 1);

    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pumpAndSettle();

    expect(_opacityFor(tester, find.text('Sender')), 0);
    expect(_opacityFor(tester, find.text('1 of 2')), 0);

    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await tester.pumpAndSettle();

    expect(_opacityFor(tester, find.text('Sender')), 1);
    expect(_opacityFor(tester, find.text('1 of 2')), 1);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'media-0',
      ),
      findsNothing,
    );
    expect(_heroModeFor(tester, 'media-1').enabled, isTrue);
  });
}

double _flightRadius(WidgetTester tester) => _flightCorners(tester).topLeft.x;

ChatMediaImage _flightImage(WidgetTester tester) =>
    tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .singleWhere((box) => box.child is ChatMediaImage)
            .child!
        as ChatMediaImage;

BorderRadius _flightCorners(WidgetTester tester) {
  final local = find.byType(ChatMediaFlightPhoto);
  if (local.evaluate().isNotEmpty) {
    return tester.widget<ChatMediaFlightPhoto>(local).flight.borderRadius;
  }
  return tester
      .widgetList<ClipRRect>(find.byType(ClipRRect))
      .singleWhere(
        (clip) =>
            clip.child is ColoredBox &&
            (clip.child! as ColoredBox).child is ChatMediaImage,
      )
      .borderRadius
      .resolve(TextDirection.ltr);
}

Future<void> _pumpGallery(WidgetTester tester) async {
  await tester.pumpWidget(
    _testApp(
      ChatMediaGalleryPage(
        sentAt: DateTime(2026),
        imagePaths: ['missing-first.jpg', 'missing-second.jpg'],
        heroTags: ['media-0', 'media-1'],
        initialIndex: 0,
        senderName: 'Sender',
        imageAspectRatios: [2, .5],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MaterialApp _testApp(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: ChatMediaTransitionScope(
    child: Stack(
      children: [
        home,
        const Positioned.fill(child: ChatMediaTransitionLayer()),
        const ChatMediaTransitionShadows(
          topHeight: 84,
          bottomHeight: 110,
          backgroundColor: Colors.black,
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ChatMediaTransitionChrome(child: SizedBox(height: 64)),
        ),
      ],
    ),
  ),
);

void _expectSingleImageFlight(WidgetTester tester) {
  final layers = tester
      .widgetList<Opacity>(find.byType(Opacity))
      .where((opacity) => opacity.child is ChatMediaImage)
      .toList();
  expect(layers, isEmpty);
  expect(
    tester
        .widgetList<ChatMediaImage>(find.byType(ChatMediaImage))
        .where((image) => image.fit == BoxFit.cover),
    isNotEmpty,
  );
}

double _opacityFor(WidgetTester tester, Finder content) {
  final opacity = find.ancestor(
    of: content,
    matching: find.byType(AnimatedOpacity),
  );
  return tester.widget<AnimatedOpacity>(opacity).opacity;
}

double _paintedOpacityFor(WidgetTester tester, Finder content) {
  final opacity = tester.widget<AnimatedOpacity>(
    find.ancestor(of: content, matching: find.byType(AnimatedOpacity)),
  );
  return tester
      .widget<FadeTransition>(
        find.byWidgetPredicate(
          (widget) =>
              widget is FadeTransition &&
              identical(widget.child, opacity.child),
        ),
      )
      .opacity
      .value;
}

HeroMode _heroModeFor(WidgetTester tester, String tag) {
  final hero = find.byWidgetPredicate(
    (widget) => widget is Hero && widget.tag == tag,
  );
  final mode = find.ancestor(of: hero, matching: find.byType(HeroMode));
  return tester.widget<HeroMode>(mode.first);
}
