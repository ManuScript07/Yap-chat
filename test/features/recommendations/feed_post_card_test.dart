import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_card.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_controls.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/router/router.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  late _Posts repository;
  late FeedActionsCubit actions;
  late FeedCubit timeline;

  setUp(() {
    repository = _Posts();
    final account = AccountSessionController(initialUserId: 'viewer').capture();
    actions = FeedActionsCubit(repository, account, () => true);
    timeline = FeedCubit(
      tab: FeedTab.forYou,
      repository: repository,
      account: account,
      isCurrentAccount: () => true,
      actions: actions,
    );
    addTearDown(actions.close);
    addTearDown(timeline.close);
  });

  Future<void> mount(
    WidgetTester tester,
    List<FeedPost> posts, {
    required ValueChanged<String> onOpen,
    double scale = 1,
    Locale locale = const Locale('en'),
    Size viewport = const Size(320, 760),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              for (final post in posts)
                FeedPostCard(
                  key: ValueKey(post.id),
                  post: post,
                  timeline: timeline,
                  visible: true,
                  onOpenPost: onOpen,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('long names and large counters fit on a compact card at 200%', (
    tester,
  ) async {
    final post = _post('author', name: 'очень длинное имя автора публикации');
    await mount(
      tester,
      [post],
      onOpen: (_) {},
      scale: 2,
      locale: const Locale('ru'),
    );
    final avatar = find.byType(FeedPostAuthorAvatar);
    final text = find.text(post.text);
    final footer = find.byType(FeedPostFooter);
    final share = find.byIcon(Icons.share_outlined);
    final like = find.byIcon(Icons.favorite);
    final name = find.text(post.authorName!);
    final date = find.text(
      MaterialLocalizations.of(
        tester.element(name),
      ).formatCompactDate(post.createdAt.toLocal()),
    );
    final follow = find.byType(PrimaryIconButton);
    expect(
      tester.getTopLeft(text).dx,
      greaterThan(tester.getTopRight(avatar).dx),
    );
    expect(tester.getRect(footer).contains(tester.getCenter(share)), isTrue);
    expect(
      (tester.getCenter(share).dy - tester.getCenter(like).dy).abs(),
      lessThan(24),
    );
    expect(find.text('12к'), findsOneWidget);
    expect(_baseline(tester, date), closeTo(_baseline(tester, name), .01));
    expect(
      tester
          .renderObject<RenderBox>(date)
          .getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(tester.getSize(date).width + .5),
    );
    expect(
      tester.getTopRight(date).dx,
      lessThanOrEqualTo(tester.getTopLeft(follow).dx),
    );
    expect(tester.getTopRight(name).dx, lessThan(tester.getTopLeft(date).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'avatar, author and buttons start at the same top with any location',
    (tester) async {
      final posts = [
        _post(
          'exact',
          name: 'first',
          coordinates: (latitude: 1, longitude: 2),
          repostedBy: 'reposter',
        ),
        _post('nearby', name: 'second'),
        _post('none', name: 'third', nearby: false),
      ];
      await mount(
        tester,
        posts,
        onOpen: (_) {},
        viewport: const Size(360, 760),
      );
      for (final (index, post) in posts.indexed) {
        final card = find.byKey(ValueKey(post.id));
        final avatar = find.descendant(
          of: card,
          matching: find.byType(FeedPostAuthorAvatar),
        );
        final name = find.text(post.authorName!);
        final follow = find.descendant(
          of: card,
          matching: find.byType(PrimaryIconButton),
        );
        final menu = find.descendant(
          of: card,
          matching: find.byTooltip('post options'),
        );
        expect(
          tester.getTopLeft(name).dy,
          closeTo(tester.getTopLeft(avatar).dy, .01),
        );
        expect(tester.getTopLeft(follow).dy, tester.getTopLeft(avatar).dy);
        expect(tester.getTopLeft(menu).dy, tester.getTopLeft(avatar).dy);
        expect(tester.getTopLeft(menu).dx, tester.getTopRight(follow).dx);
        expect(
          tester
              .getTopRight(
                find.descendant(
                  of: card,
                  matching: find.byIcon(Icons.more_vert),
                ),
              )
              .dx,
          348,
        );
        final label = index == 0
            ? find.text('location')
            : find.text('near you');
        if (index < 2) {
          final leading = index == 0 ? find.byIcon(Icons.place_rounded) : label;
          expect(
            tester.getTopLeft(leading).dx,
            tester.getTopLeft(name).dx - (index == 0 ? 3 : 0),
          );
          expect(
            tester.getTopLeft(label).dy - tester.getBottomLeft(name).dy,
            lessThan(5),
          );
        }
      }
      final exact = find.widgetWithText(TextButton, 'location');
      expect(
        tester.widget<TextButton>(exact).style!.overlayColor!.resolve({
          WidgetState.pressed,
        }),
        Colors.transparent,
      );
      expect(
        tester.widget<Text>(find.text('location')).style!.fontWeight,
        FontWeight.w700,
      );
      final first = find.byKey(const ValueKey('post-exact'));
      final heart = find.descendant(
        of: first,
        matching: find.byIcon(Icons.favorite),
      );
      final count = find.descendant(of: first, matching: find.text('12k'));
      expect(
        tester.getTopLeft(heart).dx,
        tester.getTopLeft(find.text('first')).dx,
      );
      expect(
        tester.getCenter(count).dy,
        closeTo(tester.getCenter(heart).dy, .01),
      );
      expect(tester.getTopLeft(count).dx - tester.getTopRight(heart).dx, 5);
      expect(tester.widget<Icon>(heart).size, 22);
      expect(
        tester.widget<Text>(count).style,
        isA<TextStyle>()
            .having((style) => style.fontSize, 'size', 14)
            .having((style) => style.fontWeight, 'weight', FontWeight.w600),
      );
    },
  );

  testWidgets('the location opens the map and a stale tap cannot reopen it', (
    tester,
  ) async {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        launcher,
        null,
      ),
    );
    final post = _post('author', coordinates: (latitude: 1, longitude: 2));
    final opened = <String>[];
    await mount(tester, [post], onOpen: opened.add);
    final location = find.widgetWithText(TextButton, 'location');
    final staleTap = tester.widget<TextButton>(location).onPressed!;
    await tester.tap(location);
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.arguments['url'], 'geo:1.0,2.0?q=1.0,2.0');
    actions.friendshipRemoved(post.authorId);
    staleTap();
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(find.text('near you'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('the tapped duplicate avatar flies on push and on pop', (
    tester,
  ) async {
    const path = 'avatars/feed-hero.png';
    final posts = [
      _post('same', id: 'one', avatarPath: path),
      _post('same', id: 'two', avatarPath: path),
    ];
    final router = RootStackRouter.build(
      routes: [
        NamedRouteDef(
          name: AuthGateRoute.name,
          path: '/',
          builder: (_, _) => const AutoRouter(),
          children: [
            NamedRouteDef(
              name: 'FeedFixture',
              path: '',
              builder: (_, _) => Scaffold(
                body: Builder(
                  builder: (context) => ListView(
                    children: [
                      for (final post in posts)
                        FeedPostCard(
                          post: post,
                          timeline: timeline,
                          visible: ModalRoute.isCurrentOf(context) == true,
                          onOpenPost: (_) {},
                        ),
                    ],
                  ),
                ),
              ),
            ),
            NamedRouteDef(
              name: ViewedProfileRoute.name,
              path: 'profile',
              builder: (_, _) {
                final snapshot = ProfileAvatarHero.snapshotFor('same')!;
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
      MaterialApp.router(
        routerConfig: router.config(
          navigatorObservers: createAppNavigatorObservers,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    final avatars = find.byType(FeedPostAuthorAvatar);
    final midpoint =
        (tester.getCenter(avatars.first).dy +
            tester.getCenter(avatars.last).dy) /
        2;
    await tester.tap(avatars.last);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final flight = find.byKey(const ValueKey('profile-photo-flight-clip'));
    expect(flight, findsOneWidget);
    expect(tester.getCenter(flight).dy, greaterThan(midpoint));
    await tester.pumpAndSettle();
    router.innerRouterOf<StackRouter>(AuthGateRoute.name)!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(flight, findsOneWidget);
    await tester.pumpAndSettle();
    expect(avatars, findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  testWidgets(
    'blank card space opens the post while author and menu use their own targets',
    (tester) async {
      final opened = <String>[];
      final post = _post('viewer');
      await mount(tester, [post], onOpen: opened.add);
      await tester.tap(find.byType(FeedPostAuthorAvatar));
      await tester.tap(find.text(post.authorName!));
      await tester.tap(find.byTooltip('post options'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.byType(ProfileActionSheetContent), findsOneWidget);
      await tester.tapAt(const Offset(30, 100));
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(FeedPostCard));
      await tester.tapAt(origin + const Offset(6, 20));
      expect(opened, [post.id]);
    },
  );

  testWidgets(
    'unfollow requires confirmation and preserves the button while pending',
    (tester) async {
      await mount(tester, [_post('author')], onOpen: (_) {});
      final button = find.byType(PrimaryIconButton);
      final size = tester.getSize(button);
      expect(tester.widget<PrimaryIconButton>(button).muted, isTrue);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repository.writes, isEmpty);
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(repository.writes, isEmpty);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.writes, hasLength(1));
      expect(tester.getSize(button), size);
      expect(tester.widget<PrimaryIconButton>(button).muted, isTrue);
      expect(tester.widget<PrimaryIconButton>(button).busy, isTrue);
      await tester.tap(button);
      expect(repository.writes, hasLength(1));
      repository.writes.single.complete((
        version: 1,
        following: false,
        canFollow: true,
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(button), size);
      expect(tester.widget<PrimaryIconButton>(button).muted, isFalse);
    },
  );
}

double _baseline(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderBox>(text);
  return tester.getTopLeft(text).dy +
      paragraph.getDryBaseline(
        BoxConstraints.tight(paragraph.size),
        TextBaseline.alphabetic,
      )!;
}

FeedPost _post(
  String author, {
  String? id,
  String name = 'author name',
  bool nearby = true,
  FeedCoordinates? coordinates,
  String? avatarPath,
  String? repostedBy,
}) => FeedPost(
  id: id ?? 'post-$author',
  authorId: author,
  authorName: name,
  text: 'short post',
  createdAt: DateTime.utc(2020, 7, 31),
  nearby: nearby,
  coordinates: coordinates,
  avatarPath: avatarPath,
  repostedBy: repostedBy,
  reaction: (version: 0, liked: true, likes: 12000),
  commentCount: 452100000,
  viewCount: 10000000000,
  follow: (version: 0, following: true, canFollow: true),
);

class _Posts extends MockFeedRepository implements IFeedPostRepository {
  final writes = <Completer<FeedFollowState>>[];

  @override
  Future<FeedFollowState> setFollow(
    String authorId,
    FeedFollowState current,
    String requestId,
    AccountSessionSnapshot account,
  ) {
    final write = Completer<FeedFollowState>();
    writes.add(write);
    return write.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
