import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  testWidgets(
    'return preserves chat search and accepts arrivals during the animation',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final navigation = NavigationScrollToTopController();
      final rows = _chats(150);
      await _mount(tester, fixture, _view(rows), navigation: navigation);
      fixture.bloc.add(const ChatsSearchChanged('chat'));
      await _pump(tester);
      fixture.repository.emit(_view(rows, query: 'chat', hasMoreRemote: true));
      await _pump(tester);
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      controller.jumpTo(2500);
      await tester.pump();
      final queries = fixture.repository.queries.toList();
      final requests = fixture.repository.requests.length;
      final done = navigation.scrollToTop(NavigationScrollTarget.chats);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final offset = controller.offset;
      fixture.repository.emit(
        _view([_chat('chat-new'), ...rows], query: 'chat', hasMoreRemote: true),
      );
      await tester.pump();
      expect(controller.offset, closeTo(offset, .1));
      await tester.pumpAndSettle();
      await done;
      expect(controller.offset, 0);
      expect(fixture.bloc.state.searchQuery, 'chat');
      expect(fixture.bloc.state.chats.first.id, 'chat-new');
      expect(fixture.repository.queries, queries);
      expect(fixture.repository.requests.length, requests);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      navigation.dispose();
    },
  );
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      'navigation scrolls loaded chats to top without requesting more $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _Fixture();
        addTearDown(fixture.close);
        final navigation = NavigationScrollToTopController();
        await _mount(
          tester,
          fixture,
          _view(_chats(150), hasMoreRemote: true),
          navigation: navigation,
        );
        final controller = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        controller.jumpTo(controller.position.maxScrollExtent - 800);
        await tester.pump();
        final before = controller.offset;
        final requests = fixture.repository.requests.length;
        final done = navigation.scrollToTop(NavigationScrollTarget.chats);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.offset, inExclusiveRange(0, before));
        await tester.pumpAndSettle();
        await done;
        expect(controller.offset, 0);
        expect(fixture.repository.requests.length, requests);
        expect(fixture.repository.legacyReads, 0);
        expect(fixture.bloc.state.chats.length, 150);
        expect(fixture.repository.visibleIds, contains('chat-0'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        navigation.dispose();
      },
    );
  }
  group('paginated selection', () {
    test(
      'selection survives search, additional pages, and returning home',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        await fixture.start();
        final alice = _chat('alice');
        final bob = _chat('bob');
        await fixture.publish(_view([alice], hasMoreRemote: true));
        await fixture.select('alice');

        await fixture.search('  BOB  ');
        expect(fixture.repository.queries, ['bob']);
        await fixture.publish(_view([bob], query: 'bob', hasMoreRemote: true));
        expect(fixture.bloc.state.selectedChatIds, {'alice'});
        expect(fixture.bloc.state.selectedChats['alice'], alice);
        await fixture.select('bob');

        fixture.bloc.add(const ChatsLoadMoreRequested());
        await fixture.repository.nextRequest();
        await fixture.publish(_view([bob, _chat('bobby')], query: 'bob'));
        fixture.repository.requests.single.complete();
        expect(fixture.bloc.state.selectedChatIds, {'alice', 'bob'});
        expect(fixture.repository.selectedIds, {'alice', 'bob'});

        await fixture.search('');
        await fixture.publish(_view([alice, _chat('carol')]));
        expect(fixture.bloc.state.filteredChats.map((chat) => chat.id), [
          'alice',
          'carol',
        ]);
        expect(fixture.bloc.state.selectedChatIds, {'alice', 'bob'});
        expect(
          fixture.bloc.state.selectionRows.map((chat) => chat.id),
          unorderedEquals(['alice', 'bob']),
        );
        expect(fixture.repository.selectedIds, {'alice', 'bob'});
        expect(fixture.repository.legacyReads, 0);
      },
    );

    test('only explicitly missing selected IDs are removed off page', () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      await fixture.start();
      await fixture.publish(_view([_chat('alice'), _chat('bob')]));
      await fixture.select('alice');
      await fixture.select('bob');
      await fixture.search('carol');
      await fixture.publish(_view([_chat('carol')], query: 'carol'));
      expect(fixture.bloc.state.selectedChatIds, {'alice', 'bob'});

      await fixture.publish(
        _view([_chat('carol')], query: 'carol', missingSelectedIds: {'alice'}),
      );
      expect(fixture.bloc.state.selectedChatIds, {'bob'});
      expect(fixture.bloc.state.selectedChats.keys, ['bob']);
      expect(fixture.repository.selectedIds, {'bob'});

      await fixture.publish(
        _view([_chat('carol')], query: 'carol', missingSelectedIds: {'bob'}),
      );
      expect(fixture.bloc.state.isSelectionMode, isFalse);
      expect(fixture.bloc.state.selectedChats, isEmpty);
      expect(fixture.repository.selectedIds, isEmpty);
    });

    test(
      'page and subscription failures preserve selected snapshots',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        await fixture.start();
        final alice = _chat('alice', muted: true);
        await fixture.publish(_view([alice]));
        await fixture.select('alice');
        await fixture.search('bob');
        final failure = StateError('offline');
        await fixture.publish(
          _view(
            [_chat('bob')],
            query: 'bob',
            hasMoreRemote: true,
            error: failure,
          ),
        );
        expect(fixture.bloc.state.status, ChatsStatus.success);
        expect(fixture.bloc.state.paginationError, same(failure));
        expect(fixture.bloc.state.selectedChatIds, {'alice'});
        expect(fixture.bloc.state.selectedChats['alice'], alice);

        await fixture.after(
          () => fixture.repository.views.addError(StateError('stream failed')),
          (state) => state.status == ChatsStatus.failure,
        );
        expect(fixture.bloc.state.selectedChatIds, {'alice'});
        expect(fixture.bloc.state.hasMutedSelection, isTrue);
        expect(fixture.repository.selectedIds, {'alice'});

        await fixture.publish(_view([_chat('bob')], query: 'bob'));
        expect(fixture.bloc.state.status, ChatsStatus.success);
        expect(fixture.bloc.state.paginationError, isNull);
        expect(fixture.bloc.state.selectedChats['alice'], alice);
      },
    );

    test(
      'failed bulk mute retains selection and can be retried off page',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        await fixture.start();
        final alice = _chat('alice', muted: true);
        await fixture.publish(_view([alice]));
        await fixture.select('alice');
        await fixture.search('bob');
        await fixture.publish(_view([_chat('bob')], query: 'bob'));
        fixture.repository.muteError = StateError('write failed');
        await fixture.after(
          () => fixture.bloc.add(const ChatsMuteToggled()),
          (state) => state.feedback == ChatsBulkActionFeedback.failure,
        );
        expect(fixture.bloc.state.selectedChatIds, {'alice'});
        expect(fixture.bloc.state.selectedChats['alice'], alice);
        expect(fixture.bloc.state.isBulkActionInProgress, isFalse);

        fixture.repository.muteError = null;
        await fixture.after(
          () => fixture.bloc.add(const ChatsMuteToggled()),
          (state) => state.feedback == ChatsBulkActionFeedback.success,
        );
        expect(fixture.repository.muteCalls, hasLength(2));
        for (final call in fixture.repository.muteCalls) {
          expect(call.ids, {'alice'});
          expect(call.isMuted, isFalse);
        }
        expect(fixture.bloc.state.selectedChatIds, isEmpty);
        expect(fixture.bloc.state.selectedChats, isEmpty);
        expect(fixture.repository.selectedIds, isEmpty);
      },
    );
  });

  testWidgets('off-page selected snapshot updates toolbar and mute target', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await _mount(tester, fixture, _view([_chat('alice'), _chat('bob')]));
    await tester.longPress(find.byKey(const ValueKey('alice')));
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('bob')));
    await _pump(tester);
    expect(fixture.bloc.state.selectedChatIds, {'alice', 'bob'});
    expect(_toolbarIcon(Icons.notifications_off_rounded), findsOneWidget);

    fixture.bloc.add(const ChatsSearchChanged('carol'));
    await _pump(tester);
    fixture.repository.emit(_view([_chat('carol')], query: 'carol'));
    await _pump(tester);
    expect(find.byKey(const ValueKey('alice')), findsNothing);
    expect(find.byKey(const ValueKey('bob')), findsNothing);

    // The changed row is neither visible nor the first selected row.
    fixture.repository.emit(
      _view(
        [_chat('carol')],
        query: 'carol',
        selectedChats: [_chat('alice'), _chat('bob', muted: true)],
      ),
    );
    await _pump(tester);
    expect(_toolbarIcon(Icons.notifications_active_rounded), findsOneWidget);
    await tester.tap(_toolbarIcon(Icons.notifications_active_rounded));
    await _pump(tester);
    expect(fixture.repository.muteCalls.single.ids, {'bob'});
    expect(fixture.repository.muteCalls.single.isMuted, isFalse);
    expect(fixture.bloc.state.selectedChatIds, isEmpty);
    expect(fixture.repository.selectedIds, isEmpty);
    expect(find.byKey(const ValueKey('carol')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final cached in [false, true]) {
    testWidgets(
      'near-end ${cached ? 'cached' : 'remote'} load and retry retain rows',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        final rows = _chats(40);
        await _mount(
          tester,
          fixture,
          _view(rows, hasMoreCached: cached, hasMoreRemote: !cached),
        );
        expect(fixture.repository.requests, isEmpty);
        await _scrollToEnd(tester);
        expect(fixture.repository.requests, hasLength(1));
        expect(fixture.repository.requests.single.retry, isFalse);
        expect(fixture.repository.visibleIds, contains('chat-39'));

        fixture.repository.emit(
          _view(rows, hasMoreRemote: true, isLoadingRemote: true),
        );
        await _pump(tester);
        // Loading inserts a new footer after the previous end of the list.
        await _scrollToEnd(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-39')), findsOneWidget);
        expect(fixture.bloc.state.chats, rows);

        fixture.repository.emit(
          _view(
            rows,
            hasMoreRemote: true,
            error: StateError('next page failed'),
          ),
        );
        fixture.repository.requests.single.complete();
        await _pump(tester);
        await _scrollToEnd(tester);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ChatsPage)),
        )!;
        final retry = find.widgetWithText(FilledButton, l10n.repeat);
        expect(retry.hitTestable(), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-39')), findsOneWidget);
        expect(fixture.bloc.state.chats, rows);
        expect(fixture.repository.requests, hasLength(1));

        await tester.tap(retry);
        await _pump(tester);
        expect(fixture.repository.requests, hasLength(2));
        expect(fixture.repository.requests.last.retry, isTrue);
        expect(find.byKey(const ValueKey('chat-39')), findsOneWidget);
        fixture.repository.emit(_view([...rows, _chat('next-page')]));
        fixture.repository.requests.last.complete();
        await _pump(tester);
        await _scrollToEnd(tester);
        expect(find.byKey(const ValueKey('next-page')), findsOneWidget);
        expect(fixture.bloc.state.chats, [...rows, _chat('next-page')]);
        expect(fixture.bloc.state.paginationError, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final kind in ['cached', 'remote', 'failure']) {
    testWidgets(
      'empty $kind page loads continuation or offers a real error retry',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        await _mount(
          tester,
          fixture,
          _view(
            [],
            hasMoreCached: kind == 'cached',
            hasMoreRemote: kind == 'remote',
            error: kind == 'failure' ? StateError('first page failed') : null,
          ),
        );
        expect(find.byType(ChatListItem), findsNothing);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ChatsPage)),
        )!;
        final retry = find.widgetWithText(FilledButton, l10n.repeat);
        if (kind == 'failure') {
          expect(retry.hitTestable(), findsOneWidget);
          expect(fixture.repository.requests, isEmpty);
          await tester.tap(retry);
          await _pump(tester);
          expect(fixture.repository.requests.single.retry, isTrue);
        } else {
          expect(retry, findsNothing);
          expect(fixture.repository.requests.single.retry, isFalse);
        }
        fixture.repository.emit(_view([_chat('recovered')]));
        fixture.repository.requests.single.complete();
        await _pump(tester);
        expect(find.byKey(const ValueKey('recovered')), findsOneWidget);
        expect(fixture.bloc.state.status, ChatsStatus.success);
        expect(fixture.bloc.state.paginationError, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in [const Size(320, 720), const Size(780, 390)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'paginated page and selected toolbar fit $size scale=$scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final fixture = _Fixture();
          addTearDown(fixture.close);
          final rows = [
            for (var i = 0; i < 12; i++)
              _chat('chat-$i', muted: true).copyWith(
                userName: 'Очень длинное имя пользователя Long display name $i',
                lastMessage: 'Длинное последнее сообщение Long message preview',
              ),
          ];
          await _mount(
            tester,
            fixture,
            _view(rows, hasMoreRemote: true, error: StateError('offline')),
            textScale: scale,
          );
          expect(find.byType(ChatListItem), findsWidgets);
          expect(tester.takeException(), isNull);
          await _scrollToEnd(tester);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(ChatsPage)),
          )!;
          expect(find.text(l10n.failedToLoadChats), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Select without navigating, then render the same pagination failure
          // under the selection toolbar at both orientations and text sizes.
          fixture.bloc.add(const ChatSelectionToggled('chat-0'));
          await _pump(tester);
          expect(find.byType(SelectionToolbar), findsOneWidget);
          expect(
            _toolbarIcon(Icons.notifications_active_rounded),
            findsOneWidget,
          );
          expect(fixture.bloc.state.selectedChatIds, {'chat-0'});
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('1000 chats mount only nearby rows and report the new viewport', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await _mount(tester, fixture, _view(_chats(1000)));
    final initial = tester
        .widgetList<ChatListItem>(
          find.byType(ChatListItem, skipOffstage: false),
        )
        .map((row) => row.chat.id)
        .toSet();
    expect(initial, contains('chat-0'));
    expect(initial.length, inExclusiveRange(0, 50));
    expect(find.byKey(const ValueKey('chat-999')), findsNothing);
    expect(fixture.repository.visibleIds, isNotEmpty);
    expect(fixture.repository.visibleIds.length, lessThan(50));

    final position = tester.state<ScrollableState>(_scrollable()).position;
    position.jumpTo(position.maxScrollExtent * .5);
    await _pump(tester);
    final middle = tester
        .widgetList<ChatListItem>(
          find.byType(ChatListItem, skipOffstage: false),
        )
        .map((row) => row.chat.id)
        .toSet();
    expect(middle.length, inExclusiveRange(0, 50));
    expect(middle.intersection(initial), isEmpty);
    expect(find.byKey(const ValueKey('chat-0')), findsNothing);
    expect(fixture.repository.visibleIds, isNotEmpty);
    expect(fixture.repository.visibleIds.difference(middle), isEmpty);
    expect(fixture.repository.visibleIds.length, lessThan(50));
    expect(fixture.repository.requests, isEmpty);
    expect(fixture.repository.legacyReads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('promoting a far row preserves the visible scroll anchor', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final rows = _chats(100);
    await _mount(tester, fixture, _view(rows));
    final position = tester.state<ScrollableState>(_scrollable()).position;
    position.jumpTo(position.maxScrollExtent * .5);
    await _pump(tester);
    final anchor = find.byType(ChatListItem).evaluate().firstWhere((element) {
      final finder = find.byWidget(element.widget);
      final top = tester.getTopLeft(finder).dy;
      return top >= 130 && top < 300;
    });
    final id = (anchor.widget as ChatListItem).chat.id;
    final finder = find.byKey(ValueKey(id));
    final before = tester.getTopLeft(finder).dy;
    expect(find.byKey(const ValueKey('chat-99')), findsNothing);

    fixture.repository.emit(
      _view([
        rows.last.copyWith(
          lastMessage: 'new activity',
          lastMessageTime: DateTime(2027),
        ),
        ...rows.take(rows.length - 1),
      ]),
    );
    await _pump(tester);
    expect(find.byKey(ValueKey(id)), findsOneWidget);
    expect(tester.getTopLeft(finder).dy, closeTo(before, 1));
    expect(fixture.bloc.state.chats.first.id, 'chat-99');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Chat _chat(String id, {bool muted = false}) => Chat(
  id: id,
  // Empty peer IDs avoid an unrelated PresenceCubit dependency in these tests.
  peerId: '',
  userName: id,
  lastMessage: 'preview',
  lastMessageTime: DateTime(2026),
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
  isMuted: muted,
);

List<Chat> _chats(int count) => [
  for (var i = 0; i < count; i++) _chat('chat-$i'),
];

ChatListViewState _view(
  List<Chat> rows, {
  String query = '',
  List<Chat> selectedChats = const [],
  Set<String> missingSelectedIds = const {},
  bool hasMoreCached = false,
  bool hasMoreRemote = false,
  bool isLoadingRemote = false,
  Object? error,
}) => ChatListViewState(
  query: query,
  chats: List.unmodifiable(rows),
  selectedChats: selectedChats,
  missingSelectedIds: missingSelectedIds,
  ready: true,
  hasMoreCached: hasMoreCached,
  hasMoreRemote: hasMoreRemote,
  isLoadingRemote: isLoadingRemote,
  error: error,
);

Finder _toolbarIcon(IconData icon) => find.descendant(
  of: find.byType(SelectionToolbar),
  matching: find.byIcon(icon),
);

Finder _scrollable() => find.descendant(
  of: find.byType(ListView),
  matching: find.byType(Scrollable),
);

// Bounded pumps also work while the production page shows an animated spinner.
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  ChatListViewState view, {
  double textScale = 1,
  NavigationScrollToTopController? navigation,
}) async {
  fixture.bloc.add(const ChatsLoadStarted());
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<IChatsRepository>.value(value: fixture.repository),
        if (navigation != null)
          RepositoryProvider<NavigationScrollToTopController>.value(
            value: navigation,
          ),
      ],
      child: BlocProvider.value(
        value: fixture.bloc,
        child: MaterialApp(
          theme: ThemeData.dark(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const ChatsPage(),
        ),
      ),
    ),
  );
  await _pump(tester);
  expect(fixture.repository.listened.isCompleted, isTrue);
  fixture.repository.emit(view);
  await _pump(tester);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    final position = tester.state<ScrollableState>(_scrollable()).position;
    if (position.extentAfter < 1) return;
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await _pump(tester);
  }
  fail('The chat list did not reach its end after 30 scroll gestures');
}

class _Fixture {
  final repository = _Repository();
  late final bloc = ChatsBloc(chatsRepository: repository);

  Future<void> start() async {
    bloc.add(const ChatsLoadStarted());
    await repository.listened.future.timeout(const Duration(seconds: 3));
  }

  Future<ChatsState> after(
    void Function() action,
    bool Function(ChatsState) predicate,
  ) {
    final next = bloc.stream
        .firstWhere(predicate)
        .timeout(const Duration(seconds: 3));
    action();
    return next;
  }

  Future<ChatsState> publish(ChatListViewState view) => after(
    () => repository.emit(view),
    (state) => identical(state.chats, view.chats),
  );

  Future<ChatsState> select(String id) => after(
    () => bloc.add(ChatSelectionToggled(id)),
    (state) => state.selectedChatIds.contains(id),
  );

  Future<ChatsState> search(String query) => after(
    () => bloc.add(ChatsSearchChanged(query)),
    (state) => state.searchQuery == query.trim().toLowerCase(),
  );

  Future<void> close() async {
    for (final request in repository.requests) {
      request.complete();
    }
    await bloc.close();
    await repository.views.close();
  }
}

class _PageRequest {
  _PageRequest(this.retry);
  final bool retry;
  final done = Completer<void>();
  void complete() {
    if (!done.isCompleted) done.complete();
  }
}

// A controllable source of repository facts, without duplicating pagination,
// filtering, selection, or mute decisions from the production Bloc.
class _Repository implements IChatsRepository, IChatsListRepository {
  _Repository() {
    views = StreamController<ChatListViewState>.broadcast(
      onListen: () => listened.complete(),
    );
  }

  late final StreamController<ChatListViewState> views;
  final listened = Completer<void>();
  final queries = <String>[];
  final requests = <_PageRequest>[];
  final muteCalls = <({Set<String> ids, bool isMuted})>[];
  final _firstRequest = Completer<_PageRequest>();
  Set<String> visibleIds = {};
  Set<String> selectedIds = {};
  Object? muteError;
  int legacyReads = 0;

  void emit(ChatListViewState view) => views.add(view);

  Future<_PageRequest> nextRequest() {
    if (requests.isNotEmpty) return Future.value(requests.last);
    return _firstRequest.future.timeout(const Duration(seconds: 3));
  }

  @override
  Stream<ChatListViewState> watchChatList() => views.stream;

  @override
  Future<void> setChatListQuery(String query) async => queries.add(query);

  @override
  Future<void> loadMoreChatList({bool retry = false}) async {
    final request = _PageRequest(retry);
    requests.add(request);
    if (!_firstRequest.isCompleted) _firstRequest.complete(request);
    await request.done.future;
  }

  @override
  void setChatListObservedIds(Set<String> visible, Set<String> selected) {
    visibleIds = Set.of(visible);
    selectedIds = Set.of(selected);
  }

  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {
    muteCalls.add((ids: Set.of(ids), isMuted: isMuted));
    if (muteError case final error?) throw error;
  }

  @override
  Future<String?> resolveAvatar(Chat chat) async => null;

  @override
  Stream<List<Chat>> watchChats() {
    legacyReads++;
    throw UnsupportedError('Paginated UI must use watchChatList');
  }

  @override
  Future<List<Chat>> getChats() async {
    legacyReads++;
    throw UnsupportedError('Paginated UI must not fetch a full list');
  }

  @override
  Stream<Chat?> watchChat(String chatId) => throw UnimplementedError();
  @override
  Future<Chat?> getChatById(String chatId) => throw UnimplementedError();
  @override
  Future<Chat?> getCachedChatByPeerId(String peerId) =>
      throw UnimplementedError();
  @override
  Future<Chat> prepareDirectChat({
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    String? peerAvatarUrl,
    String? peerAvatarStoragePath,
  }) => throw UnimplementedError();
  @override
  Future<Chat> ensureDirectChat(String peerId) => throw UnimplementedError();
  @override
  Future<void> deleteChats(Set<String> ids) => throw UnimplementedError();
  @override
  Future<void> markAsRead(Set<String> ids) => throw UnimplementedError();
  @override
  Future<void> pauseRealtime() async {}
  @override
  Future<void> resumeRealtime() async {}
}
