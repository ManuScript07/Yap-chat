import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/app/chat_navigation_coordinator.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/view/viewed_profile_page.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/chat_route_navigation.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/theme/theme.dart';

void main() {
  for (final target in [_chat('B'), _draft('B')]) {
    testWidgets('profile chain replaces A with ${target.id}, Back skips A', (
      tester,
    ) async {
      final router = await _mount(tester);
      final base = router.stackData.first;
      final baseState = tester.state<_BaseScreenState>(
        find.byType(_BaseScreen),
      );
      baseState.selectedTab = 2;
      await _open(tester, router, _chat('A'));
      unawaited(
        router.push(ViewedProfileRoute(userId: 'B', originChatId: 'A')),
      );
      unawaited(router.push(UserFriendsRoute(userId: 'B', userName: 'B')));
      unawaited(router.push(ViewedProfileRoute(userId: 'B')));
      await tester.pumpAndSettle();

      await _open(tester, router, target);
      expect(router.stackData.map((route) => route.name), [
        MainRoute.name,
        ChatRoute.name,
      ]);
      expect(router.stackData.first, same(base));
      expect(router.stackData.last.argsAs<ChatRouteArgs>().chat, target);
      expect(find.text('chat:${target.id}'), findsOneWidget);

      await router.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('base'), findsOneWidget);
      expect(
        tester.state<_BaseScreenState>(find.byType(_BaseScreen)),
        same(baseState),
      );
      expect(baseState.selectedTab, 2);
      expect(router.stackData, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('same peer returns to existing chat, retaining widget state', (
    tester,
  ) async {
    final router = await _mount(tester);
    final draft = _draft('A');
    await _open(tester, router, draft);
    final state = tester.state<_ChatScreenState>(find.byType(_ChatScreen));
    state.counter = 7;
    final route = router.stackData.last;
    unawaited(
      router.push(ViewedProfileRoute(userId: 'A', originChatId: draft.id)),
    );
    await tester.pumpAndSettle();

    // Preparing a server chat must not replace a still-open draft for that peer.
    await _open(tester, router, _chat('A'));
    expect(router.stackData.last, same(route));
    expect(
      tester.state<_ChatScreenState>(find.byType(_ChatScreen)),
      same(state),
    );
    expect(state.counter, 7);
    expect(router.stackData, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing only the profile still returns to A', (tester) async {
    final router = await _mount(tester);
    await _open(tester, router, _chat('A'));
    unawaited(router.push(ViewedProfileRoute(userId: 'B', originChatId: 'A')));
    await tester.pumpAndSettle();
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('chat:A'), findsOneWidget);
  });

  testWidgets('replacement disposes the old focused chat without focusing B', (
    tester,
  ) async {
    final router = await _mount(tester);
    await _open(tester, router, _chat('A'));
    final old = tester.state<_ChatScreenState>(find.byType(_ChatScreen));
    await tester.enterText(find.byType(TextField), 'unsent');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(old.focus.hasFocus, isTrue);
    await _open(tester, router, _chat('B'));
    expect(old.mounted, isFalse);
    final current = tester.state<_ChatScreenState>(find.byType(_ChatScreen));
    expect(current.focus.hasFocus, isFalse);
    expect(find.text('chat:B'), findsOneWidget);
    expect(router.stackData, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('without an existing chat, Back retains ordinary profile flow', (
    tester,
  ) async {
    final router = await _mount(tester);
    unawaited(router.push(ViewedProfileRoute(userId: 'B')));
    await tester.pumpAndSettle();
    await _open(tester, router, _draft('B'));
    expect(router.stackData, hasLength(3));
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('profile'), findsOneWidget);
  });

  testWidgets('keeps the exact page before A, not necessarily Main', (
    tester,
  ) async {
    final router = await _mount(tester);
    unawaited(router.push(const NewChatRoute()));
    await tester.pumpAndSettle();
    final source = router.stackData.last;
    await _open(tester, router, _chat('A'));
    unawaited(router.push(ViewedProfileRoute(userId: 'B', originChatId: 'A')));
    await tester.pumpAndSettle();
    await _open(tester, router, _draft('B'));
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(router.stackData.last, same(source));
    expect(find.text('new-chat'), findsOneWidget);
  });

  testWidgets('notification opens serialize and deduplicate above a profile', (
    tester,
  ) async {
    final router = await _mount(tester);
    await _open(tester, router, _chat('A'));
    unawaited(router.push(ViewedProfileRoute(userId: 'B', originChatId: 'A')));
    await tester.pumpAndSettle();
    var loads = 0;
    final errors = <Object>[];
    final navigator = _coordinator(router, (id) async {
      loads++;
      return _chat(id);
    }, errors);
    final opened = Future.wait([
      navigator.openById('B'),
      navigator.openById('B'),
      navigator.openById('C'),
    ]);
    await tester.pumpAndSettle();
    await opened;
    expect(loads, 2);
    expect(errors, isEmpty);
    expect(router.stackData, hasLength(2));
    expect(find.text('chat:C'), findsOneWidget);
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('base'), findsOneWidget);
  });

  testWidgets('unknown notification chat leaves A and its profile untouched', (
    tester,
  ) async {
    final router = await _mount(tester);
    await _open(tester, router, _chat('A'));
    unawaited(router.push(ViewedProfileRoute(userId: 'B', originChatId: 'A')));
    await tester.pumpAndSettle();
    final before = router.stackData;
    final errors = <Object>[];
    await _coordinator(router, (_) async => null, errors).openById('missing');
    expect(router.stackData, orderedEquals(before));
    expect(errors, isEmpty);
  });

  testWidgets(
    'real profile chat button opens a new draft instead of popping A',
    (tester) async {
      final router = await _mount(tester, realProfile: true);
      await _open(tester, router, _chat('A'));
      unawaited(
        router.push(
          ViewedProfileRoute(userId: 'candidate-3', originChatId: 'A'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
      await tester.pumpAndSettle();
      final target = router.stackData.last.argsAs<ChatRouteArgs>().chat;
      expect(target.isDraft, isTrue);
      expect(target.peerId, 'candidate-3');
      expect(router.stackData, hasLength(2));
      expect(find.text('chat:${target.id}'), findsOneWidget);
      await router.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('base'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('real profile chat button opens another existing conversation', (
    tester,
  ) async {
    final router = await _mount(tester, realProfile: true);
    await _open(tester, router, _chat('friend-1'));
    unawaited(
      router.push(
        ViewedProfileRoute(userId: 'friend-2', originChatId: 'friend-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
    await tester.pumpAndSettle();
    final target = router.stackData.last.argsAs<ChatRouteArgs>().chat;
    expect(target.isDraft, isFalse);
    expect(target.peerId, 'friend-2');
    expect(router.stackData, hasLength(2));
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('base'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real profile of the same peer returns without recreating chat', (
    tester,
  ) async {
    final router = await _mount(tester, realProfile: true);
    await _open(tester, router, _chat('friend-1'));
    final state = tester.state<_ChatScreenState>(find.byType(_ChatScreen));
    unawaited(
      router.push(
        ViewedProfileRoute(userId: 'friend-1', originChatId: 'friend-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
    await tester.pumpAndSettle();
    expect(
      tester.state<_ChatScreenState>(find.byType(_ChatScreen)),
      same(state),
    );
    expect(
      router.stackData.last.argsAs<ChatRouteArgs>().chat.peerId,
      'friend-1',
    );
    expect(router.stackData, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'conversations without peer metadata are not incorrectly reused',
    (tester) async {
      final router = await _mount(tester);
      await _open(tester, router, _chat('A').copyWith(peerId: ''));
      await _open(tester, router, _chat('B').copyWith(peerId: ''));
      expect(find.text('chat:B'), findsOneWidget);
      expect(router.stackData, hasLength(2));
    },
  );
}

Future<_TestRouter> _mount(
  WidgetTester tester, {
  bool realProfile = false,
}) async {
  final router = _TestRouter(realProfile);
  addTearDown(router.dispose);
  Widget app = MaterialApp.router(
    theme: theme,
    locale: const Locale('ru'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router.config(),
  );
  if (realProfile) {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final chats = MockChatsRepository();
    // The generic UI mock seeds old chats without peer IDs. Explicitly create
    // these fixtures so the existing-conversation tests exercise that path.
    await chats.ensureDirectChat('friend-1');
    await chats.ensureDirectChat('friend-2');
    app = MultiRepositoryProvider(
      providers: [
        RepositoryProvider<IProfileRepository>.value(
          value: MockProfileRepository(preferences: preferences),
        ),
        RepositoryProvider<IFriendsRepository>.value(
          value: MockFriendsRepository(),
        ),
        RepositoryProvider<IChatsRepository>.value(value: chats),
        RepositoryProvider<ILocationRepository>.value(
          value: LocationRepository(preferences: preferences),
        ),
        RepositoryProvider<ISettingsRepository>.value(
          value: MockSettingsRepository(),
        ),
        RepositoryProvider<IBlocklistRepository>.value(
          value: MockBlocklistRepository(),
        ),
        RepositoryProvider<IUserReportsRepository>.value(
          value: const MockUserReportsRepository(),
        ),
        RepositoryProvider<ChatNavigationCoordinator>.value(
          value: _coordinator(router, (_) async => null, []),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => PresenceCubit(repository: MockPresenceRepository()),
          ),
          BlocProvider(
            create: (context) => BlocklistCubit(
              repository: context.read<IBlocklistRepository>(),
            ),
          ),
        ],
        child: app,
      ),
    );
  }
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return router;
}

Future<void> _open(WidgetTester tester, StackRouter router, Chat chat) async {
  final opened = openChatRoute(router, chat);
  await tester.pumpAndSettle();
  await opened;
}

ChatNavigationCoordinator _coordinator(
  StackRouter router,
  Future<Chat?> Function(String) load,
  List<Object> errors,
) => ChatNavigationCoordinator(
  loadChat: load,
  navigateToChat: (chat) => openChatRoute(router, chat),
  isConversationVisible: (id) =>
      router.stackData.last.name == ChatRoute.name &&
      router.stackData.last.argsAs<ChatRouteArgs>().chat.id == id,
  isPeerVisible: (id) =>
      router.stackData.last.name == ChatRoute.name &&
      id.isNotEmpty &&
      router.stackData.last.argsAs<ChatRouteArgs>().chat.peerId == id,
  isActive: () => true,
  onError: (error, _, _) => errors.add(error),
  waitForFrame: () async {},
);

class _TestRouter extends RootStackRouter {
  _TestRouter(this.realProfile);
  final bool realProfile;
  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: MainRoute.name,
      path: '/',
      initial: true,
      builder: (_, _) => const _BaseScreen(),
    ),
    NamedRouteDef(
      name: ChatRoute.name,
      path: '/chat',
      builder: (_, data) {
        final args = data.argsAs<ChatRouteArgs>();
        return _ChatScreen(key: args.key, chat: args.chat);
      },
    ),
    NamedRouteDef(
      name: ViewedProfileRoute.name,
      path: '/profile',
      builder: (_, data) {
        final args = data.argsAs<ViewedProfileRouteArgs>();
        return realProfile
            ? ViewedProfilePage(
                userId: args.userId,
                originChatId: args.originChatId,
              )
            : const Scaffold(body: Text('profile'));
      },
    ),
    NamedRouteDef(
      name: UserFriendsRoute.name,
      path: '/friends',
      builder: (_, _) => const Scaffold(body: Text('friends')),
    ),
    NamedRouteDef(
      name: NewChatRoute.name,
      path: '/new-chat',
      builder: (_, _) => const Scaffold(body: Text('new-chat')),
    ),
  ];
}

class _ChatScreen extends StatefulWidget {
  const _ChatScreen({super.key, required this.chat});
  final Chat chat;
  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  int counter = 0;
  final focus = FocusNode();
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('chat:${widget.chat.id}'),
        TextField(focusNode: focus),
      ],
    ),
  );
}

class _BaseScreen extends StatefulWidget {
  const _BaseScreen();
  @override
  State<_BaseScreen> createState() => _BaseScreenState();
}

class _BaseScreenState extends State<_BaseScreen> {
  int selectedTab = 0;
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('base'));
}

Chat _chat(String peer) => Chat(
  id: peer,
  peerId: peer,
  userName: peer,
  lastMessage: '',
  lastMessageTime: DateTime(2026),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);
Chat _draft(String peer) =>
    Chat.directDraft(peerId: peer, peerUsername: peer, peerDisplayName: peer);
