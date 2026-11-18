import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_details.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_gallery.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

const _postId = '07d220f5-ae02-4a69-b52f-0452f1637e1a';

void main() {
  late AccountSessionController accounts;
  late _Repository repository;
  late FeedAccountScope scope;

  setUp(() {
    accounts = AccountSessionController(initialUserId: 'viewer');
    repository = _Repository();
    scope = FeedAccountScope(accounts, repository);
  });

  tearDown(() {
    scope.dispose();
  });

  Future<void> show(WidgetTester tester, {String id = _postId}) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: accounts),
          RepositoryProvider<IFeedRepository>.value(value: repository),
          RepositoryProvider.value(value: scope),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.black,
            colorScheme: const ColorScheme.dark(
              surface: Colors.white,
              onSurface: Colors.white,
            ),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FeedPostDetailsPage(id: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('invalid and inaccessible posts issue no comment requests', (
    tester,
  ) async {
    await show(tester, id: 'invalid');
    expect(repository.postReads, 0);
    expect(find.text('post unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    repository.post = null;
    await show(tester);
    expect(repository.postReads, 1);
    expect(repository.commentReads, 0);
    expect(find.text('post unavailable'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('revocation changes the map button to a label without a reload', (
    tester,
  ) async {
    repository.post = _postWithLocation();
    await show(tester);
    expect(find.text('location'), findsOneWidget);
    expect(find.text('near you'), findsNothing);
    final actions = scope.actionsFor(accounts.capture())!;
    actions.friendshipRemoved('author');
    await tester.pumpAndSettle();
    expect(find.text('location'), findsNothing);
    expect(find.text('near you'), findsOneWidget);
    expect(find.text('test publication'), findsOneWidget);
    expect(repository.postReads, 1);
    expect(repository.commentReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a public quote closes when its original loses access', (
    tester,
  ) async {
    repository.post = FeedPost(
      id: _postId,
      authorId: 'quoting author',
      authorName: 'quoting author',
      text: 'test quote',
      createdAt: DateTime.utc(2026),
      isQuote: true,
      original: _postWithLocation(id: 'original', friendsOnly: true),
    );
    await show(tester);
    expect(find.text('test quote'), findsOneWidget);
    scope.actionsFor(accounts.capture())!.friendshipRemoved('author');
    await tester.pumpAndSettle();
    expect(find.text('test quote'), findsNothing);
    expect(find.text('test publication'), findsNothing);
    expect(find.text('post unavailable'), findsOneWidget);
    expect(repository.postReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('comment retry keeps the draft and reuses its request id', (
    tester,
  ) async {
    await show(tester);
    expect(repository.postReads, 1);
    expect(repository.commentReads, 1);
    expect(tester.widget<Card>(find.byType(Card).first).color, Colors.black);
    final field = find.byType(TextField);
    final send = find.byTooltip('send comment');
    await tester.enterText(field, 'my comment');
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.tap(send);
    await tester.pump();
    expect(repository.writes, hasLength(1));
    repository.writes.single.$2.completeError(TimeoutException('test'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'my comment');
    await tester.tap(send);
    await tester.pump();
    expect(repository.writes, hasLength(2));
    expect(repository.writes.last.$1, repository.writes.first.$1);
    repository.writes.last.$2.complete((
      id: repository.writes.last.$1,
      authorId: 'viewer',
      authorName: 'viewer',
      text: 'my comment',
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('my comment'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account switch clears an open publication and its draft', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), 'private draft');
    accounts.setAuthenticatedUser('another-viewer');
    await tester.pumpAndSettle();
    expect(find.text('post unavailable'), findsOneWidget);
    expect(find.text('test publication'), findsNothing);
    expect(find.text('private draft'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'gallery requests only the active photo and reuses its decoded frame on return',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      final preview = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawPaint(ui.Paint()..color = Colors.blue);
        final picture = recorder.endRecording();
        try {
          final image = await picture.toImage(40, 120);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          repository.photoBytes = png!.buffer.asUint8List();
          final panorama = await picture.toImage(2048, 1);
          try {
            final png = await panorama.toByteData(
              format: ui.ImageByteFormat.png,
            );
            repository.secondPhotoBytes = png!.buffer.asUint8List();
          } finally {
            panorama.dispose();
          }
          return image;
        } finally {
          picture.dispose();
        }
      });
      Future<void> settleImage() async {
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 25));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 3)),
          );
        }
        await tester.pumpAndSettle();
      }

      addTearDown(preview!.dispose);
      final account = accounts.capture();
      final timeline = FeedCubit(
        tab: FeedTab.forYou,
        repository: repository,
        account: account,
        isCurrentAccount: () => accounts.isCurrent(account),
        actions: scope.actionsFor(account),
      );
      addTearDown(timeline.close);
      final post = FeedPost(
        id: _postId,
        authorId: 'author',
        authorName: 'author',
        text: '',
        createdAt: DateTime.utc(2026),
        friendsOnly: true,
        photos: const [
          FeedPhoto(
            id: 'first',
            thumbnailPath: 'first',
            width: 40,
            height: 120,
          ),
          FeedPhoto(
            id: 'second',
            thumbnailPath: 'second',
            width: 2048,
            height: 1,
          ),
        ],
      );
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: accounts,
          child: MaterialApp(
            locale: const Locale('en'),
            theme: ThemeData(scaffoldBackgroundColor: Colors.black),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor: Colors.green,
                body: Column(
                  children: [
                    Hero(
                      tag: 'post photo',
                      curve: Curves.linear,
                      reverseCurve: Curves.linear,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          feedPhotoPreviewRadius,
                        ),
                        child: RawImage(
                          image: preview,
                          width: 120,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => openFeedGallery(
                        context,
                        timeline: timeline,
                        post: post,
                        index: 0,
                        heroTag: 'post photo',
                        preview: preview,
                      ),
                      child: const Text('open gallery'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open gallery'));
      await tester.pump();
      await tester.pump();

      final flight = find.byKey(const ValueKey('feed-gallery-flight'));
      final header = find.byType(MediaGalleryHeader);
      final headerElement = tester.element(header);
      final chrome = find
          .ancestor(of: header, matching: find.byType(FadeTransition))
          .first;
      final backdrop = find.byKey(const ValueKey('media-gallery-backdrop'));
      double radius() =>
          (tester.widget<ClipRRect>(flight).borderRadius as BorderRadius)
              .topLeft
              .x;
      double chromeOpacity() =>
          tester.widget<FadeTransition>(chrome).opacity.value;
      double backdropOpacity() => tester.widget<ColoredBox>(backdrop).color.a;
      expect(chromeOpacity(), 0);
      final initialRadius = radius();
      await tester.pump(const Duration(milliseconds: 65));
      expect(radius(), closeTo(initialRadius - 4, .05));
      expect(chromeOpacity(), 0);
      final shading = backdropOpacity();
      expect(shading, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 65));
      expect(radius(), closeTo(initialRadius - 8, .05));
      expect(chromeOpacity(), 0);
      expect(backdropOpacity(), greaterThan(shading));
      await tester.pump(const Duration(milliseconds: 130));
      expect(chromeOpacity(), 0);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      expect(flight, findsNothing);
      await tester.pump(const Duration(milliseconds: 54));
      expect(chromeOpacity(), inExclusiveRange(0, 1));
      await settleImage();
      expect(chromeOpacity(), 1);
      expect(tester.element(header), same(headerElement));
      expect(
        tester
            .widgetList<GlassIconButton>(
              find.descendant(
                of: header,
                matching: find.byType(GlassIconButton),
              ),
            )
            .map(
              (button) => (
                button.icon,
                button.width,
                button.height,
                button.borderRadius,
                button.iconSize,
                button.chatStyle,
              ),
            ),
        [
          (Icons.arrow_back_rounded, 44, 44, 16, 26, true),
          (Icons.download_rounded, 44, 44, 16, 24, true),
        ],
      );
      expect(repository.photoReads, ['first']);
      expect(find.text('1 of 2'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await settleImage();
      expect(find.text('2 of 2'), findsOneWidget);
      expect(repository.photoReads, ['first', 'second']);
      expect(
        find.descendant(
          of: find.byType(PageView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox && widget.width == 400 && widget.height == 1,
          ),
        ),
        findsWidgets,
      );

      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      expect(tester.element(header), same(headerElement));
      expect(chromeOpacity(), 1);
      expect(repository.photoReads, ['first', 'second']);

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final zoom = viewer.transformationController!;
      zoom.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      expect(tester.element(header), same(headerElement));
      zoom.value = Matrix4.identity();
      await tester.pump();

      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);
      expect(repository.photoReads, ['first', 'second']);
      zoom.value = Matrix4.diagonal3Values(2, 2, 1)
        ..setTranslationRaw(-50, -80, 0);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(chromeOpacity(), 1);
      expect(flight, findsNothing);
      await tester.pump(const Duration(milliseconds: 70));
      expect(chromeOpacity(), inExclusiveRange(0, 1));
      expect(zoom.value.getMaxScaleOnAxis(), inExclusiveRange(1, 2));
      expect(flight, findsNothing);
      await tester.pump(const Duration(milliseconds: 71));
      await tester.pump();
      await tester.pump();
      expect(chromeOpacity(), 0);
      expect(zoom.value, Matrix4.identity());
      for (var i = 0; i < 4 && flight.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(flight, findsOneWidget);
      final returnStart = radius();
      await tester.pump(const Duration(milliseconds: 45));
      expect(radius(), closeTo(returnStart + 4, .05));
      expect(backdropOpacity(), lessThan(1));
      await tester.pumpAndSettle();
      expect(find.text('open gallery'), findsOneWidget);

      await tester.tap(find.text('open gallery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 65));
      final interrupted = ModalRoute.of(tester.element(header))!;
      interrupted.navigator!.removeRoute(interrupted);
      await tester.pumpAndSettle();
      expect(find.text('open gallery'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('open gallery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 65));
      expect(flight, findsOneWidget);
      scope.actionsFor(account)!.friendshipRemoved('author');
      await tester.pump();
      await tester.pump();
      expect(flight, findsNothing);
      expect(find.text('post unavailable'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(repository.photoReads, ['first', 'second']);
      await tester.tap(find.byTooltip('back'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

FeedPost _postWithLocation({String id = _postId, bool friendsOnly = false}) =>
    FeedPost(
      id: id,
      authorId: 'author',
      authorName: 'author',
      text: 'test publication',
      createdAt: DateTime.utc(2026),
      coordinates: (latitude: 1, longitude: 1),
      nearby: true,
      friendsOnly: friendsOnly,
    );

class _Repository extends MockFeedRepository
    implements IFeedPostRepository, IFeedPublicationRepository {
  FeedPost? post = FeedPost(
    id: _postId,
    authorId: 'author',
    authorName: 'author',
    text: 'test publication',
    createdAt: DateTime.utc(2026),
  );
  final writes = <(String, Completer<FeedComment>)>[];
  int postReads = 0;
  int commentReads = 0;
  final photoReads = <String>[];
  Uint8List? photoBytes;
  Uint8List? secondPhotoBytes;

  @override
  Future<FeedPost?> getPost(String id, AccountSessionSnapshot account) async {
    postReads++;
    return post;
  }

  @override
  Future<FeedCommentsPage> getComments(
    String id,
    AccountSessionSnapshot account, {
    FeedCommentsCursor? cursor,
  }) async {
    commentReads++;
    return (comments: <FeedComment>[], next: null);
  }

  @override
  Future<FeedComment> createComment(
    String id,
    String requestId,
    String text,
    AccountSessionSnapshot account,
  ) {
    final result = Completer<FeedComment>();
    writes.add((requestId, result));
    return result.future;
  }

  @override
  Future<Uint8List> downloadPhoto(
    FeedPhoto photo, {
    required FeedPost post,
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) async {
    photoReads.add(photo.id);
    return (photo.id == 'second' ? secondPhotoBytes : photoBytes) ??
        (throw StateError('no fixture image'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
