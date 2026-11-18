import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/features/recommendations/view/feed_comments_sliver.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_details.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_controls.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_gallery.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/router/router.gr.dart';
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

  Widget providers(Widget child) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider.value(value: accounts),
      RepositoryProvider<IFeedRepository>.value(value: repository),
      RepositoryProvider.value(value: scope),
    ],
    child: child,
  );

  Future<void> show(
    WidgetTester tester, {
    String id = _postId,
    FeedPostDetailsPreview? preview,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      providers(
        MaterialApp(
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
          home: FeedPostDetailsPage(id: id, preview: preview),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('warm publication paints before RPC and keeps focus and draft', (
    tester,
  ) async {
    final pending = Completer<FeedPost?>();
    repository.pendingPost = pending.future;
    final initial = _postWithLocation();
    await show(
      tester,
      preview: FeedPostDetailsPreview(initial, accounts.capture()),
      settle: false,
    );
    expect(find.text(initial.text), findsOneWidget);
    expect(repository.postReads, 1);
    expect(repository.commentReads, 0);
    final field = find.byType(TextField);
    await tester.tap(find.byTooltip('comments'));
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.enterText(field, 'retained draft');
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.reset);
    await tester.pump();
    expect(
      tester.getBottomLeft(field).dy,
      lessThan(
        (tester.view.physicalSize.height - 250) / tester.view.devicePixelRatio,
      ),
    );
    pending.complete(repository.post);
    await tester.pumpAndSettle();
    expect(repository.postReads, 1);
    expect(repository.commentReads, 1);
    expect(tester.widget<TextField>(field).controller!.text, 'retained draft');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    'publication title centers in the safe area and shares its gutter',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(760, 500);
      tester.view.padding = const FakeViewPadding(left: 32, right: 12);
      addTearDown(tester.view.reset);
      await show(tester);

      expect(tester.getCenter(find.text('post')).dx, 390);
      expect(
        tester.getTopLeft(find.byType(GlassIconButton)).dx,
        tester.getTopLeft(find.byType(FeedPostAuthorAvatar)).dx,
      );
    },
  );

  testWidgets(
    'comment loading fades into a text-only error and retries to empty',
    (tester) async {
      final initial = Completer<FeedCommentsPage>();
      final retry = Completer<FeedCommentsPage>();
      repository.commentPage = (_, _) =>
          repository.commentReads == 1 ? initial.future : retry.future;
      await show(tester, settle: false);
      await tester.pump();
      final progress = find.byType(PullRefreshIndicator);
      expect(progress, findsOneWidget);
      final progressTop = tester.getTopLeft(progress).dy;

      initial.completeError(StateError('offline'));
      await tester.pump();
      final error = find.text('couldn’t load comments');
      expect(error, findsOneWidget);
      expect(progress, findsOneWidget);
      expect(tester.getTopLeft(progress).dy, progressTop);
      await tester.pump(const Duration(milliseconds: 200));
      expect(progress, findsNothing);
      final retryButton = find.byType(RetryPillButton);
      expect(retryButton, findsOneWidget);
      await tester.tap(retryButton);
      await tester.tap(retryButton);
      await tester.pump();
      expect(repository.commentReads, 2);

      retry.complete((comments: <FeedComment>[], next: null));
      await tester.pumpAndSettle();
      final empty = find.text('no comments yet');
      expect(tester.widget<Text>(empty).style!.fontSize, 22);
      expect(tester.widget<Text>(empty).style!.fontWeight, FontWeight.w700);
      expect(
        tester.widget<EmptyChatState>(find.byType(EmptyChatState)).showImage,
        isFalse,
      );
      expect(retryButton, findsNothing);
    },
  );

  testWidgets(
    'switches server sort, renders replies in line and serializes a comment like',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(440, 960);
      addTearDown(tester.view.reset);
      const preview = FeedComment(
        id: 'first-reply',
        rootId: 'root',
        authorId: 'another-account',
        authorName: 'reply author',
        text: 'first reply',
      );
      const root = FeedComment(
        id: 'root',
        authorId: 'comment-account',
        authorName: 'root author',
        text: 'root text',
        replyCount: 2,
        replyPreview: preview,
        commentVersion: 2,
        postVersion: 3,
        reaction: (version: 4, liked: false, likes: 2),
      );
      final newest = Completer<FeedCommentsPage>();
      repository.commentPage = (sort, thread) async {
        if (thread != null) {
          return (
            comments: [
              preview,
              const FeedComment(
                id: 'next-reply',
                rootId: 'root',
                authorId: 'other',
                authorName: 'other',
                text: 'next reply',
              ),
            ],
            next: null,
          );
        }
        if (sort == FeedCommentSort.newFirst) return newest.future;
        if (sort == FeedCommentSort.old) {
          return (
            comments: [
              const FeedComment(
                id: 'old',
                authorId: 'other',
                authorName: 'other',
                text: 'old result',
              ),
            ],
            next: null,
          );
        }
        return (comments: [root], next: null);
      };
      await show(tester);
      expect(repository.commentQueries, [(FeedCommentSort.popular, null)]);
      expect(
        tester.getTopLeft(find.text('root author')).dx,
        tester.getTopLeft(find.text('reply author')).dx,
      );
      await tester.tap(find.text('show replies'));
      await tester.pumpAndSettle();
      expect(find.text('next reply'), findsOneWidget);
      expect(repository.commentQueries.last, (FeedCommentSort.old, 'root'));
      expect(find.text('hide replies'), findsNothing);
      expect(find.byType(FeedDivider), findsOneWidget);

      final rootRow = find.byKey(const ValueKey('root'));
      final like = find.descendant(
        of: rootRow,
        matching: find.byIcon(Icons.favorite_border),
      );
      await tester.tap(like);
      await tester.tap(like);
      expect(repository.likes, hasLength(1));
      expect(repository.likes.single.$2.version, 4);
      repository.pendingLike!.complete((
        version: 5,
        liked: true,
        changed: true,
      ));
      await tester.pump();
      await tester.pumpAndSettle();
      final sliver = tester.widget<FeedCommentsSliver>(
        find.byType(FeedCommentsSliver),
      );
      expect(sliver.comments.reactionFor(root), (
        version: 5,
        liked: true,
        likes: 3,
      ));
      expect(
        find.descendant(of: rootRow, matching: find.byIcon(Icons.favorite)),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: rootRow,
          matching: find.byTooltip('comment options'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('spam'));
      await tester.pumpAndSettle();
      expect(find.text('send a report about this comment?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'report'));
      await tester.pumpAndSettle();
      expect(repository.reported, [('root', FeedReportReason.spam)]);
      expect(find.text('comment unavailable'), findsOneWidget);
      expect(find.text('first reply'), findsOneWidget);

      final sortMenu = find.byTooltip('comment order');
      final arrow = find.descendant(
        of: sortMenu,
        matching: find.byType(AnimatedRotation),
      );
      await tester.tap(sortMenu);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedRotation>(arrow).turns, .5);
      final popular = find.widgetWithText(MenuItemButton, 'popular');
      expect(
        tester.getTopLeft(popular).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(sortMenu).dy),
      );
      expect(
        tester
            .widget<MenuItemButton>(popular)
            .style!
            .foregroundColor!
            .resolve({}),
        Theme.of(tester.element(popular)).colorScheme.primary,
      );
      await tester.tap(find.widgetWithText(MenuItemButton, 'newest'));
      await tester.pump();
      expect(tester.widget<AnimatedRotation>(arrow).turns, 0);
      expect(find.byType(MenuItemButton), findsNothing);
      await tester.tap(sortMenu);
      await tester.pump();
      await tester.tap(find.widgetWithText(MenuItemButton, 'oldest'));
      await tester.pumpAndSettle();
      expect(find.text('old result'), findsOneWidget);
      newest.complete((
        comments: [
          const FeedComment(
            id: 'new',
            authorId: 'other',
            authorName: 'other',
            text: 'late newest result',
          ),
        ],
        next: null,
      ));
      await tester.pumpAndSettle();
      expect(find.text('old result'), findsOneWidget);
      expect(find.text('late newest result'), findsNothing);
      expect(repository.commentQueries, [
        (FeedCommentSort.popular, null),
        (FeedCommentSort.old, 'root'),
        (FeedCommentSort.newFirst, null),
        (FeedCommentSort.old, null),
      ]);
    },
  );

  testWidgets('opening a second branch preserves the first and its replies', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 1000);
    addTearDown(tester.view.reset);
    repository.commentPage = (_, thread) async => (
      comments: thread == null
          ? [
              for (final id in ['a', 'b'])
                FeedComment(
                  id: id,
                  authorId: 'other',
                  text: 'thread $id',
                  replyCount: 1,
                ),
            ]
          : [
              FeedComment(
                id: 'reply-$thread',
                rootId: thread,
                authorId: 'other',
                text: 'reply to $thread',
              ),
            ],
      next: null,
    );
    await show(tester);
    final expand = find.text('show replies');
    await tester.tap(expand.first);
    await tester.pumpAndSettle();
    expect(find.text('reply to a'), findsOneWidget);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(find.text('reply to a'), findsOneWidget);
    expect(find.text('reply to b'), findsOneWidget);
    expect(expand, findsNothing);
    expect(find.byType(FeedDivider), findsNWidgets(2));
    expect(repository.commentQueries, [
      (FeedCommentSort.popular, null),
      (FeedCommentSort.old, 'a'),
      (FeedCommentSort.old, 'b'),
    ]);
  });

  testWidgets('comment cache keeps the avatar row mounted during a warm read', (
    tester,
  ) async {
    const first = FeedComment(
      id: 'cached',
      authorId: 'commenter',
      authorName: 'cached author',
      avatarPath: 'avatars/commenter/one.jpg',
      text: 'cached text',
    );
    repository.commentPage = (_, _) async => (comments: [first], next: null);
    await show(tester);
    expect(find.text('cached text'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    final revalidation = Completer<FeedCommentsPage>();
    repository.commentPage = (_, _) => revalidation.future;
    await show(tester, settle: false);
    await tester.pump();
    final avatar = find.descendant(
      of: find.byKey(const ValueKey('cached')),
      matching: find.byType(FeedAuthorAvatar),
    );
    expect(find.text('cached text'), findsOneWidget);
    expect(find.byType(PullRefreshIndicator), findsOneWidget);
    final element = tester.element(avatar);
    revalidation.complete((
      comments: [
        const FeedComment(
          id: 'cached',
          authorId: 'commenter',
          authorName: 'cached author',
          avatarPath: 'avatars/commenter/one.jpg',
          text: 'updated text',
        ),
      ],
      next: null,
    ));
    await tester.pumpAndSettle();
    expect(find.text('updated text'), findsOneWidget);
    expect(tester.element(avatar), same(element));
    expect(repository.commentReads, 2);
  });

  testWidgets(
    'only the selected comment avatar flies to the profile and back',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(440, 960);
      addTearDown(tester.view.reset);
      const path = 'avatars/comment-hero.png';
      repository.commentPage = (_, _) async => (
        comments: [
          const FeedComment(
            id: 'first',
            authorId: 'commenter',
            authorName: 'same author',
            avatarPath: path,
            text: 'first comment',
            replyCount: 1,
            replyPreview: FeedComment(
              id: 'mention',
              rootId: 'first',
              authorId: 'commenter',
              text: 'mentioned in a reply',
              replyTo: (id: 'parent', username: 'target', userId: 'mentioned'),
            ),
          ),
          const FeedComment(
            id: 'second',
            authorId: 'commenter',
            authorName: 'same author',
            avatarPath: path,
            text: 'second comment',
            replyCount: 1,
            replyPreview: FeedComment(
              id: 'own-mention',
              rootId: 'second',
              authorId: 'commenter',
              text: 'mentioned in a reply',
              replyTo: (id: 'own-parent', username: 'me', userId: 'viewer'),
            ),
          ),
        ],
        next: null,
      );
      final router = RootStackRouter.build(
        routes: [
          NamedRouteDef(
            name: AuthGateRoute.name,
            path: '/',
            builder: (_, _) => const AutoRouter(),
            children: [
              NamedRouteDef(
                name: 'CommentFixture',
                path: '',
                builder: (_, _) => const FeedPostDetailsPage(id: _postId),
              ),
              NamedRouteDef(
                name: ViewedProfileRoute.name,
                path: 'profile',
                builder: (_, data) {
                  final user = data.argsAs<ViewedProfileRouteArgs>().userId;
                  final snapshot = ProfileAvatarHero.snapshotFor(user);
                  if (snapshot == null) {
                    return Scaffold(body: Text('profile $user'));
                  }
                  return Scaffold(
                    body: Center(
                      child: ProfileAvatarHero(
                        avatarStoragePath: snapshot.avatarStoragePath,
                        child: const UserAvatar(size: 176),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        providers(
          MaterialApp.router(
            routerConfig: router.config(
              navigatorObservers: createAppNavigatorObservers,
            ),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avatar = find.descendant(
        of: find.byKey(const ValueKey('second')),
        matching: find.byType(FeedAuthorAvatar),
      );
      await tester.tap(avatar);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final flight = find.byKey(const ValueKey('profile-photo-flight-clip'));
      expect(flight, findsOneWidget);
      await tester.pumpAndSettle();
      router.innerRouterOf<StackRouter>(AuthGateRoute.name)!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(flight, findsOneWidget);
      await tester.pumpAndSettle();
      expect(avatar, findsOneWidget);
      final ownMention = find.text('@me mentioned in a reply');
      await tester.tapAt(tester.getTopLeft(ownMention) + const Offset(8, 7));
      await tester.pumpAndSettle();
      expect(ownMention, findsOneWidget);
      final mention = find.text('@target mentioned in a reply');
      await tester.tapAt(tester.getTopLeft(mention) + const Offset(8, 7));
      await tester.pumpAndSettle();
      expect(find.text('profile mentioned'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    },
  );

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
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.tap(send);
    await tester.pump();
    expect(repository.writes, hasLength(2));
    expect(repository.writes.last.$1, repository.writes.first.$1);
    repository.writes.last.$2.complete(
      FeedComment(
        id: repository.writes.last.$1,
        authorId: 'viewer',
        authorName: 'viewer',
        text: 'my comment',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('my comment'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reply composer keeps its draft across routes and reopens the IME',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(760, 510);
      tester.view.viewPadding = const FakeViewPadding(left: 32, right: 20);
      tester.view.padding = const FakeViewPadding(left: 32, right: 20);
      addTearDown(tester.view.reset);
      repository.commentPage = (_, _) async => (
        comments: [
          const FeedComment(
            id: 'root',
            authorId: 'other',
            authorName: 'author of comment',
            text: 'root text',
          ),
        ],
        next: null,
      );
      await show(tester);
      final field = find.byType(TextField);
      final reply = find.widgetWithText(TextButton, 'reply');
      expect(
        tester.getTopLeft(find.text('reply')).dx,
        tester.getTopLeft(find.text('root text')).dx,
      );
      await tester.tap(reply);
      await tester.pumpAndSettle();
      final replyBar = find.ancestor(
        of: find.text('replying to author of comment'),
        matching: find.byType(ChatGlassSurface),
      );
      final inputSurface = find.ancestor(
        of: field,
        matching: find.byType(ChatGlassSurface),
      );
      expect(
        tester.getTopLeft(replyBar).dx,
        tester.getTopLeft(inputSurface).dx,
      );
      expect(
        tester.getTopRight(replyBar).dx,
        760 - 20 - MessageInputBar.horizontalGutter,
      );

      await tester.enterText(field, 'draft reply');
      tester.testTextInput.hide();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.tap(find.byTooltip('comments'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      final navigator = Navigator.of(tester.element(field));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('overlaid route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      expect(tester.widget<TextField>(field).controller!.text, 'draft reply');
      expect(replyBar, findsOneWidget);
    },
  );

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
  final likes = <(FeedComment, FeedReaction)>[];
  final reported = <(String, FeedReportReason)>[];
  Completer<FeedCommentLike>? pendingLike;
  final commentQueries = <(FeedCommentSort, String?)>[];
  Future<FeedCommentsPage> Function(FeedCommentSort, String?)? commentPage;
  Future<FeedPost?>? pendingPost;
  int postReads = 0;
  int commentReads = 0;
  final photoReads = <String>[];
  Uint8List? photoBytes;
  Uint8List? secondPhotoBytes;

  @override
  Future<FeedPost?> getPost(String id, AccountSessionSnapshot account) async {
    postReads++;
    if (pendingPost case final pending?) return pending;
    return post;
  }

  @override
  Future<FeedCommentsPage> getComments(
    String id,
    AccountSessionSnapshot account, {
    FeedCommentsCursor? cursor,
    FeedCommentSort sort = FeedCommentSort.popular,
    String? rootId,
  }) async {
    commentReads++;
    commentQueries.add((sort, rootId));
    if (commentPage case final handler?) return handler(sort, rootId);
    return (comments: <FeedComment>[], next: null);
  }

  @override
  Future<FeedCommentLike> setCommentLiked(
    FeedComment comment,
    FeedReaction current,
    String requestId,
    AccountSessionSnapshot account,
  ) {
    likes.add((comment, current));
    return (pendingLike ??= Completer<FeedCommentLike>()).future;
  }

  @override
  Future<void> reportComment(
    String id,
    FeedReportReason reason,
    String requestId,
    AccountSessionSnapshot account,
  ) async => reported.add((id, reason));

  @override
  Future<FeedComment> createComment(
    String id,
    String requestId,
    String text,
    AccountSessionSnapshot account, {
    String? replyTo,
  }) {
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
