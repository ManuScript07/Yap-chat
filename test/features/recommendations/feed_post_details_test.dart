import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/features/recommendations/view/feed_comment_motion.dart';
import 'package:yap_chat/features/recommendations/view/feed_comments_sliver.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_card.dart';
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

  testWidgets('post retry fades in place and makes room for the top ring', (
    tester,
  ) async {
    final initial = Completer<FeedPost?>();
    repository.pendingPost = initial.future;
    await show(
      tester,
      preview: FeedPostDetailsPreview(repository.post!, accounts.capture()),
      settle: false,
    );
    initial.completeError(TimeoutException('offline'));
    await tester.pumpAndSettle();

    final retryButton = find.byType(RetryPillButton);
    final card = find.byType(FeedPostCard);
    final originalTop = tester.getTopLeft(card).dy;
    final fade = find.descendant(
      of: find.ancestor(
        of: retryButton,
        matching: find.byType(AnimatedOpacity),
      ),
      matching: find.byType(FadeTransition),
    );
    double opacity() => tester.widget<FadeTransition>(fade.first).opacity.value;
    expect(opacity(), 1);

    final retry = Completer<FeedPost?>();
    repository.pendingPost = retry.future;
    await tester.tap(retryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(opacity(), inExclusiveRange(0.0, 1.0));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is PullRefreshIndicator && widget.spinning,
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 180));
    expect(opacity(), 0);
    expect(tester.getTopLeft(card).dy - originalTop, closeTo(76, 1));
    expect(repository.postReads, 2);

    retry.completeError(TimeoutException('still offline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(opacity(), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(tester.getTopLeft(card).dy, closeTo(originalTop, 1));
  });

  testWidgets(
    'comment loading fades into a text-only error and retries to empty',
    (tester) async {
      final initial = Completer<FeedCommentsPage>();
      final retry = Completer<FeedCommentsPage>();
      repository.commentPage = (_, _) =>
          repository.commentReads == 1 ? initial.future : retry.future;
      await show(tester, settle: false);
      await tester.pump();
      final progress = find.byWidgetPredicate(
        (widget) => widget is PullRefreshIndicator && widget.size == 22,
      );
      await tester.pump(const Duration(milliseconds: 179));
      expect(progress, findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(progress, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 180));
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
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pump(const Duration(milliseconds: 250));
      expect(repository.postReads, 2);
      expect(repository.commentReads, 2);
      expect(progress, findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is PullRefreshIndicator &&
              widget.size == 36 &&
              widget.spinning,
        ),
        findsOneWidget,
      );

      retry.complete((comments: <FeedComment>[], next: null));
      await tester.pumpAndSettle();
      expect(progress, findsNothing);
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

  testWidgets('reopening renders cached comments during a quiet head check', (
    tester,
  ) async {
    const old = FeedComment(
      id: 'old',
      authorId: 'author',
      text: 'stored comment',
    );
    const fresh = FeedComment(
      id: 'fresh',
      authorId: 'author',
      text: 'fresh from server',
    );
    final account = accounts.capture();
    final cache = scope.actionsFor(account)!.publicationCache;
    cache.rememberComments(
      (_postId, FeedCommentSort.popular, null),
      (
        page: (comments: [old], next: null),
        expiresAt: cache.expiresFromNow().subtract(const Duration(seconds: 30)),
      ),
    );
    final response = Completer<FeedCommentsPage>();
    repository.commentPage = (_, _) => response.future;
    await show(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text(old.text!), findsOneWidget);
    expect(repository.commentQueries, [(FeedCommentSort.popular, null)]);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is PullRefreshIndicator && widget.opacity > 0,
      ),
      findsNothing,
    );
    response.complete((comments: [fresh], next: null));
    await tester.pumpAndSettle();
    expect(find.text(fresh.text!), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await show(tester);
    expect(find.text(fresh.text!), findsOneWidget);
    expect(repository.commentReads, 1);
  });

  testWidgets('pull refresh joins the same cycle and fences an older cursor', (
    tester,
  ) async {
    const initial = FeedComment(
      id: 'initial',
      authorId: 'author',
      text: 'original list',
    );
    const stale = FeedComment(
      id: 'stale',
      authorId: 'author',
      text: 'old cursor row',
    );
    const fresh = FeedComment(
      id: 'fresh',
      authorId: 'author',
      text: 'new head row',
    );
    final tail = Completer<FeedCommentsPage>();
    final refreshed = Completer<FeedCommentsPage>();
    repository.commentPage = (_, _) => switch (repository.commentReads) {
      1 => Future.value((
        comments: [initial],
        next: (sessionId: 'old', position: 0),
      )),
      2 => tail.future,
      _ => refreshed.future,
    };
    await show(tester);
    final comments = tester
        .widget<FeedCommentsSliver>(find.byType(FeedCommentsSliver))
        .comments;
    final oldRead = comments.next();
    final gesture = await tester.startGesture(const Offset(200, 230));
    await gesture.moveBy(const Offset(0, 480));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    final refresh = tester.widget<PullRefresh>(find.byType(PullRefresh));
    final secondTrigger = refresh.onRefresh();
    await tester.pump();
    expect(repository.postReads, 2);
    expect(repository.commentReads, 3);
    expect(find.text(initial.text!), findsOneWidget);
    refreshed.complete((comments: [fresh], next: null));
    await secondTrigger;
    tail.complete((comments: [stale], next: null));
    await oldRead;
    await tester.pumpAndSettle();
    expect(find.text(fresh.text!), findsOneWidget);
    expect(find.text(stale.text!), findsNothing);
  });

  testWidgets(
    'refresh checks the selected sort and only visible open branches',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(440, 900);
      addTearDown(tester.view.reset);
      final roots = [
        for (var index = 0; index < 20; index++)
          FeedComment(
            id: 'root-$index',
            authorId: 'author',
            text: 'root text $index',
            replyCount: 2,
          ),
      ];
      repository.commentPage = (_, root) async => (
        comments: root == null
            ? roots
            : [
                FeedComment(
                  id: 'reply-$root',
                  rootId: root,
                  authorId: 'author',
                  text: 'reply to $root',
                ),
              ],
        next: null,
      );
      await show(tester);
      final comments = tester
          .widget<FeedCommentsSliver>(find.byType(FeedCommentsSliver))
          .comments;
      comments.selectSort(FeedCommentSort.newFirst);
      await tester.pumpAndSettle();
      await comments.expand(roots.first.id);
      await comments.expand(roots.last.id);
      await tester.pumpAndSettle();
      expect(comments.isExpanded(roots.last.id), isTrue);
      expect(find.text('reply to root-0'), findsOneWidget);
      expect(find.text('reply to root-19'), findsNothing);
      repository.commentQueries.clear();
      final pull = tester.widget<PullRefresh>(find.byType(PullRefresh));
      await pull.onRefresh();
      await tester.pumpAndSettle();
      expect(repository.commentQueries, [
        (FeedCommentSort.newFirst, null),
        (FeedCommentSort.old, roots.first.id),
      ]);
      expect(repository.postReads, 2);
    },
  );

  for (final expiredCursor in [false, true]) {
    testWidgets(
      'replacement keeps a deep visible comment in place (expired: $expiredCursor)',
      (tester) async {
        final rows = [
          for (var index = 0; index < 45; index++)
            FeedComment(
              id: 'depth-$index',
              authorId: 'author',
              text: 'comment number $index',
            ),
        ];
        const second = (sessionId: 'old', position: 19);
        const third = (sessionId: 'old', position: 39);
        const expired = (sessionId: 'old', position: 44);
        repository.commentPage = (_, _) async =>
            switch (repository.commentCursors.last) {
              null => (comments: rows.sublist(0, 20), next: second),
              second => (comments: rows.sublist(20, 40), next: third),
              _ => (
                comments: rows.sublist(40),
                next: expiredCursor ? expired : null,
              ),
            };
        await show(tester);
        final comments = tester
            .widget<FeedCommentsSliver>(find.byType(FeedCommentsSliver))
            .comments;
        await comments.next();
        await comments.next();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('depth-27')),
          330,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final anchorId = comments.visibleAnchors!.call()[null]!;
        final anchor = find.byKey(ValueKey(anchorId));
        final originalOffset = tester.getTopLeft(anchor).dy;
        final value = int.parse(anchorId.split('-').last);
        expect(value, inInclusiveRange(20, 38));

        const newCursor = (sessionId: 'new', position: 19);
        const newTail = (sessionId: 'new', position: 39);
        final pending = Completer<FeedCommentsPage>();
        repository.commentPage = (_, _) async =>
            switch (repository.commentCursors.last) {
              expired => throw const PostgrestException(
                message: 'comment_session_expired',
                code: 'PT410',
              ),
              null => (
                comments: [
                  const FeedComment(
                    id: 'new-root',
                    authorId: 'author',
                    text: 'new root',
                  ),
                  ...rows.sublist(0, 19),
                ],
                next: newCursor,
              ),
              _ => pending.future,
            };
        final refresh = expiredCursor
            ? comments.next()
            : tester.widget<PullRefresh>(find.byType(PullRefresh)).onRefresh();
        await tester.pump();
        expect(tester.getTopLeft(anchor).dy, closeTo(originalOffset, 1));
        final expected = [if (expiredCursor) expired, null, newCursor];
        expect(repository.commentCursors.skip(3), expected);
        pending.complete((comments: rows.sublist(19, 39), next: newTail));
        await refresh;
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(anchor).dy, closeTo(originalOffset, 1));
        expect(comments.state.rows.first.id, 'new-root');
        expect(repository.commentCursors.skip(3), expected);
      },
    );
  }

  testWidgets('pagination animates appended comments and retains the old row', (
    tester,
  ) async {
    const first = FeedComment(
      id: 'first',
      authorId: 'author',
      text: 'first row',
    );
    const second = FeedComment(
      id: 'second',
      authorId: 'author',
      text: 'second row',
    );
    const continuation = (sessionId: 'page', position: 0);
    repository.commentPage = (_, _) async =>
        repository.commentCursors.last == null
        ? (comments: [first], next: continuation)
        : (comments: [second], next: null);
    await show(tester);
    final saved = find.byKey(const ValueKey('first'));
    final element = tester.element(saved);
    final comments = tester
        .widget<FeedCommentsSliver>(find.byType(FeedCommentsSliver))
        .comments;
    await comments.next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final fade = find.descendant(
      of: find.byKey(const ValueKey('second')),
      matching: find.byType(Opacity),
    );
    expect(
      tester.widget<Opacity>(fade.first).opacity,
      inExclusiveRange(0.0, 1.0),
    );
    expect(tester.element(saved), same(element));
    expect(repository.commentCursors, [null, continuation]);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(fade.first).opacity, 1);
  });

  testWidgets('loading an expanded branch animates its new rows only once', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 870);
    addTearDown(tester.view.reset);
    final pending = Completer<FeedCommentsPage>();
    const root = FeedComment(
      id: 'root',
      authorId: 'author',
      text: 'root comment',
      replyCount: 1,
    );
    const reply = FeedComment(
      id: 'reply',
      rootId: 'root',
      authorId: 'writer',
      text: 'animated reply',
    );
    repository.commentPage = (_, rootId) => rootId == null
        ? Future.value((comments: [root], next: null))
        : pending.future;
    await show(tester);
    final rootFinder = find.byKey(const ValueKey('root'));
    final rootElement = tester.element(rootFinder);
    final top = tester.getTopLeft(rootFinder).dy;
    expect(tester.widget<FeedCommentEntrance>(rootFinder).animate, isFalse);
    await tester.tap(find.text('show replies'));
    await tester.pump();
    await tester.pump(feedCommentMotionDuration);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is PullRefreshIndicator && widget.size == 22,
      ),
      findsOneWidget,
    );
    pending.complete((comments: [reply], next: null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final replyFinder = find.byKey(const ValueKey('reply'));
    final displayed = find.descendant(
      of: replyFinder,
      matching: find.byType(Opacity),
    );
    expect(
      tester.widget<Opacity>(displayed.first).opacity,
      inExclusiveRange(0.0, 1.0),
    );
    final replyElement = tester.element(replyFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(displayed.first).opacity, 1);
    expect(tester.element(rootFinder), same(rootElement));
    expect(tester.element(replyFinder), same(replyElement));
    expect(tester.getTopLeft(rootFinder).dy, closeTo(top, 1));
    expect(repository.commentQueries, [
      (FeedCommentSort.popular, null),
      (FeedCommentSort.old, root.id),
    ]);
  });

  testWidgets('pulling a short list never prefetches its old cursor', (
    tester,
  ) async {
    final response = Completer<FeedCommentsPage>();
    repository.commentPage = (_, _) => repository.commentReads == 1
        ? Future.value((
            comments: const [
              FeedComment(id: 'head', authorId: 'author', text: 'first row'),
            ],
            next: (sessionId: 'old', position: 0),
          ))
        : response.future;
    await show(tester);
    final gesture = await tester.startGesture(const Offset(200, 280));
    await gesture.moveBy(const Offset(0, 42));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 32));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 380));
    await tester.pump();
    expect(repository.commentReads, 1);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(repository.postReads, 2);
    expect(repository.commentReads, 2);
    expect(repository.commentCursors, [null, null]);
    response.complete((comments: const <FeedComment>[], next: null));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a comment acknowledged during refresh stays visible and cached',
    (tester) async {
      const row = FeedComment(
        id: 'row',
        authorId: 'author',
        text: 'server row',
      );
      final loading = Completer<FeedCommentsPage>();
      repository.commentPage = (_, _) => repository.commentReads == 1
          ? Future.value((comments: [row], next: null))
          : loading.future;
      await show(tester);
      final cubit = tester
          .widget<FeedCommentsSliver>(find.byType(FeedCommentsSliver))
          .comments;
      final refreshing = tester
          .widget<PullRefresh>(find.byType(PullRefresh))
          .onRefresh();
      await tester.pump();
      expect(repository.commentReads, 2);
      final sending = cubit.submit('sent during refresh');
      final request = repository.writes.single;
      request.$2.complete((
        comment: FeedComment(
          id: request.$1,
          authorId: accounts.capture().userId,
          text: 'sent during refresh',
        ),
        postCount: (count: 2, revision: 1),
      ));
      expect(await sending, isTrue);
      loading.complete((comments: [row], next: null));
      await refreshing;
      await tester.pumpAndSettle();
      expect(find.text('sent during refresh'), findsOneWidget);
      expect(
        cubit.actions.publicationCache
            .read((_postId, FeedCommentSort.popular, null))
            ?.page
            .comments
            .map((row) => row.id),
        [request.$1, row.id],
      );
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
      final count = find.descendant(of: rootRow, matching: find.text('2'));
      final menuGlyph = find.descendant(
        of: rootRow,
        matching: find.byIcon(Icons.more_vert),
      );
      expect(tester.getTopRight(count).dx, tester.getTopRight(menuGlyph).dx);
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
      final sortLabel = find.descendant(
        of: sortMenu,
        matching: find.text('popular'),
      );
      expect(
        tester.getCenter(arrow).dy,
        greaterThan(tester.getCenter(sortLabel).dy),
      );
      await tester.tap(sortMenu);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final popular = find.widgetWithText(MenuItemButton, 'popular');
      final palette = Theme.of(tester.element(popular));
      expect(palette.colorScheme.surface, Colors.white);
      final panelColor = Color.alphaBlend(
        palette.colorScheme.onSurface.withValues(alpha: .08),
        palette.scaffoldBackgroundColor,
      );
      final panel = find.ancestor(
        of: popular,
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.color == panelColor,
        ),
      );
      expect(panel, findsOneWidget);
      final openingHeight = tester.getSize(panel).height;
      await tester.pumpAndSettle();
      expect(openingHeight, inExclusiveRange(0, tester.getSize(panel).height));
      expect(tester.widget<AnimatedRotation>(arrow).turns, .5);
      expect(tester.widget<Material>(panel).clipBehavior, Clip.antiAlias);
      final labels = find.descendant(of: panel, matching: find.byType(Text));
      final longest = labels
          .evaluate()
          .map((element) => tester.getSize(find.byWidget(element.widget)).width)
          .reduce((a, b) => a > b ? a : b);
      expect(tester.getSize(panel).width, closeTo(longest + 32, 1));
      expect(tester.getSize(popular).height, lessThanOrEqualTo(40));
      expect(
        tester.widget<MenuItemButton>(popular).style!.overlayColor!.resolve({
          WidgetState.pressed,
        }),
        Colors.transparent,
      );
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
      await tester.pump(const Duration(milliseconds: 50));
      expect(panel, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 101));
      await tester.pump();
      expect(find.byType(MenuItemButton), findsNothing);
      await tester.tap(sortMenu);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
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

  testWidgets('warm entry restores cached pages, branches and sorts offline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 1100);
    addTearDown(tester.view.reset);
    const first = FeedComment(
      id: 'cached',
      authorId: 'commenter',
      authorName: 'cached author',
      avatarPath: 'avatars/commenter/one.jpg',
      text: 'cached text',
      replyCount: 2,
    );
    repository.commentPage = (sort, root) async {
      final call = repository.commentQueries
          .where((query) => query == (sort, root))
          .length;
      if (root != null) {
        return (
          comments: [
            FeedComment(
              id: 'reply-$call',
              rootId: root,
              authorId: 'reply-author',
              text: 'cached reply $call',
            ),
          ],
          next: call == 1 ? (sessionId: 'replies', position: 0) : null,
        );
      }
      if (sort == FeedCommentSort.newFirst) throw TimeoutException('offline');
      if (sort == FeedCommentSort.old) {
        return (
          comments: [
            const FeedComment(
              id: 'old',
              authorId: 'author',
              text: 'cached oldest row',
            ),
          ],
          next: null,
        );
      }
      if (call == 1) {
        return (comments: [first], next: (sessionId: 'roots', position: 0));
      }
      return (
        comments: [
          const FeedComment(
            id: 'tail',
            authorId: 'author',
            text: 'cached tail',
          ),
        ],
        next: null,
      );
    };
    await show(tester);
    expect(find.text('cached text'), findsOneWidget);
    final comments = tester
        .widget<FeedCommentsSliver>(find.byType(FeedCommentsSliver))
        .comments;
    await comments.next();
    await comments.expand(first.id);
    await comments.nextReplies(first.id);
    comments.selectSort(FeedCommentSort.old);
    await tester.pumpAndSettle();
    expect(find.text('cached oldest row'), findsOneWidget);
    final reads = repository.commentReads;
    await tester.pumpWidget(const SizedBox.shrink());

    final revalidation = Completer<FeedPost?>();
    repository.pendingPost = revalidation.future;
    await show(tester, settle: false);
    await tester.pump();
    final avatar = find.descendant(
      of: find.byKey(const ValueKey('cached')),
      matching: find.byType(FeedAuthorAvatar),
    );
    expect(find.text('cached text'), findsOneWidget);
    expect(find.text('cached tail'), findsOneWidget);
    expect(find.text('cached reply 2'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is PullRefreshIndicator && widget.opacity > 0,
      ),
      findsNothing,
    );
    expect(repository.commentReads, reads);
    final element = tester.element(avatar);
    revalidation.completeError(TimeoutException('offline'));
    await tester.pumpAndSettle();
    expect(find.text('cached reply 2'), findsOneWidget);
    expect(tester.element(avatar), same(element));
    final restored = tester
        .widget<FeedCommentsSliver>(find.byType(FeedCommentsSliver))
        .comments;
    restored.selectSort(FeedCommentSort.old);
    await tester.pumpAndSettle();
    expect(find.text('cached oldest row'), findsOneWidget);
    expect(repository.commentReads, reads);
    restored.selectSort(FeedCommentSort.newFirst);
    await tester.pumpAndSettle();
    expect(find.text('couldn’t load comments'), findsOneWidget);
    expect(repository.commentReads, reads);
    restored.selectSort(FeedCommentSort.popular);
    await tester.pumpAndSettle();
    expect(find.text('cached tail'), findsOneWidget);
    expect(find.text('cached reply 2'), findsOneWidget);
    expect(repository.commentReads, reads);
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(find.text('cached text'), findsNothing);
    expect(find.text('cached reply 2'), findsNothing);
  });

  testWidgets('authoritative denial clears the warm publication and replies', (
    tester,
  ) async {
    repository.post = _postWithLocation(friendsOnly: true);
    repository.commentPage = (_, _) async => (
      comments: [
        const FeedComment(
          id: 'secret',
          authorId: 'peer',
          text: 'cached private comment',
        ),
      ],
      next: null,
    );
    await show(tester);
    expect(find.text('cached private comment'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    final denial = Completer<FeedPost?>();
    repository.pendingPost = denial.future;
    await show(tester, settle: false);
    await tester.pump();
    expect(find.text('cached private comment'), findsOneWidget);
    denial.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('post unavailable'), findsOneWidget);
    expect(find.text('cached private comment'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());

    final nextCheck = Completer<FeedPost?>();
    repository.pendingPost = nextCheck.future;
    await show(tester, settle: false);
    expect(find.text('cached private comment'), findsNothing);
    expect(find.text('test publication'), findsNothing);
    expect(repository.commentReads, 1);
    nextCheck.complete(null);
    await tester.pumpAndSettle();
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
    repository.writes.last.$2.complete((
      comment: FeedComment(
        id: repository.writes.last.$1,
        authorId: 'viewer',
        authorName: 'viewer',
        text: 'my comment',
      ),
      postCount: (count: 1, revision: 1),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('my comment'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FeedPostFooter),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'returning to the feed before acknowledgement still updates its count',
    (tester) async {
      final post = repository.post!;
      final account = accounts.capture();
      final timeline = FeedCubit(
        tab: FeedTab.forYou,
        repository: repository,
        isCurrentAccount: () => accounts.isCurrent(account),
        account: account,
        actions: scope.actionsFor(account),
      );
      addTearDown(timeline.close);
      await tester.pumpWidget(
        providers(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    FeedPostCard(
                      post: post,
                      timeline: timeline,
                      visible: true,
                      onOpenPost: (_) {
                        unawaited(
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const FeedPostDetailsPage(id: _postId),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final footer = find.byType(FeedPostFooter);
      expect(
        find.descendant(of: footer, matching: find.text('1')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('comments'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'pending comment');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('send comment'));
      await tester.pump();
      final write = repository.writes.single;
      await tester.tap(find.byTooltip('back'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedPostDetailsPage), findsNothing);
      write.$2.complete((
        comment: FeedComment(
          id: write.$1,
          authorId: 'viewer',
          text: 'pending comment',
        ),
        postCount: (count: 1, revision: 1),
      ));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: footer, matching: find.text('1')),
        findsOneWidget,
      );
      expect(repository.postReads, 1);
      expect(repository.commentReads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
      await tester.pump();
      final transition = find.descendant(
        of: find.byType(ComposerReplyTransition),
        matching: find.byType(AnimatedSize),
      );
      await tester.pump(const Duration(milliseconds: 60));
      final appearingHeight = tester.getSize(transition).height;
      await tester.pumpAndSettle();
      final fullHeight = tester.getSize(transition).height;
      expect(appearingHeight, inExclusiveRange(0, fullHeight));
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
      final replyPosition = tester.getTopLeft(replyBar);
      final fade = find.descendant(
        of: find.byType(ComposerReplyTransition),
        matching: find.byType(FadeTransition),
      );
      await tester.tap(find.byTooltip('cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        inExclusiveRange(0, 1),
      );
      expect(tester.getTopLeft(replyBar), replyPosition);
      expect(tester.getSize(transition).height, fullHeight);
      await tester.pumpAndSettle();
      expect(replyBar, findsNothing);
      expect(tester.widget<TextField>(field).controller!.text, 'draft reply');
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
  final writes = <(String, Completer<FeedCommentCreation>)>[];
  final likes = <(FeedComment, FeedReaction)>[];
  final reported = <(String, FeedReportReason)>[];
  Completer<FeedCommentLike>? pendingLike;
  final commentQueries = <(FeedCommentSort, String?)>[];
  final commentCursors = <FeedCommentsCursor?>[];
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
    commentCursors.add(cursor);
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
  Future<FeedCommentCreation> createComment(
    String id,
    String requestId,
    String text,
    AccountSessionSnapshot account, {
    String? replyTo,
  }) {
    final result = Completer<FeedCommentCreation>();
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
