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

  testWidgets('gallery swipes at normal scale and loads only the active page', (
    tester,
  ) async {
    final preview = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawPaint(ui.Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(40, 40);
      } finally {
        picture.dispose();
      }
    });
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
      photos: const [
        FeedPhoto(id: 'first', thumbnailPath: 'first'),
        FeedPhoto(id: 'second', thumbnailPath: 'second'),
      ],
    );
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: accounts,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
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
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open gallery'));
    await tester.pumpAndSettle();
    expect(repository.photoReads, ['first']);
    expect(find.text('1/2'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(repository.photoReads, ['first', 'second']);
    await tester.tap(find.byTooltip('back'));
    await tester.pumpAndSettle();
    expect(find.text('open gallery'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

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
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) async {
    photoReads.add(photo.id);
    throw StateError('simulated download failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
