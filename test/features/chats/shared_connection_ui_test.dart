import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['RobotoFlex', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    }
  });

  for (final locale in ['ru', 'en']) {
    for (final size in [
      const Size(320, 720),
      const Size(360, 800),
      const Size(780, 390),
    ]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('page title and selection $locale $size scale=$scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final fixture = _Fixture();
          addTearDown(fixture.close);
          await _mount(tester, fixture, locale: locale, scale: scale);
          final primary = find.byType(PrimaryAppBar);
          final primaryWidget = tester.widget<PrimaryAppBar>(primary);
          expect(primaryWidget.titleWidget, isA<ConnectionStatusTitle>());
          expect(primaryWidget.actionIcon, Icons.add_comment_rounded);
          expect(primaryWidget.compact, isTrue);
          expect(
            primaryWidget.preferredSize.height,
            PrimaryHeaderGeometry.compactHeight,
          );
          expect(primaryWidget.onActionPressed, isNotNull);
          final action = find.byType(IconButton);
          final primaryRect = tester.getRect(primary);
          final actionRect = tester.getRect(action);
          final titleRect = tester.getRect(find.byType(ConnectionStatusTitle));
          final row = find.byKey(const ValueKey('cached'));
          final rowElement = tester.element(row);
          final rowRect = tester.getRect(row);
          final initialState = fixture.bloc.state;
          final scroll = tester.state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          );
          final offset = scroll.position.pixels;
          await tester.tap(find.byType(TextField));
          await _pump(tester);
          final focus = FocusManager.instance.primaryFocus;

          fixture.status.reportNetworkAvailability(false);
          await tester.pump();
          for (var frame = 0; frame < 10; frame++) {
            await tester.pump(const Duration(milliseconds: 30));
            final label = tester.getRect(find.byType(AnimatedConnectingText));
            expect(label.left, closeTo(titleRect.left, .01));
            expect(label.right, lessThanOrEqualTo(actionRect.left + .01));
            expect(tester.getRect(primary), primaryRect);
            expect(tester.getRect(action), actionRect);
            expect(tester.getRect(row), rowRect);
            expect(tester.element(row), same(rowElement));
            expect(scroll.position.pixels, offset);
            expect(fixture.bloc.state, same(initialState));
            expect(FocusManager.instance.primaryFocus, same(focus));
            expect(tester.takeException(), isNull);
          }
          expect(fixture.repository.requests, isEmpty);

          fixture.bloc.add(const ChatSelectionToggled('cached'));
          await _pump(tester);
          expect(find.byType(SelectionToolbar), findsOneWidget);
          expect(find.byType(PrimaryAppBar), findsNothing);
          final toolbar = find.byType(SelectionToolbar);
          final toolbarRect = tester.getRect(toolbar);
          fixture.status.reportNetworkAvailability(true);
          await _pump(tester);
          fixture.status.reportNetworkAvailability(false);
          await _pump(tester);
          expect(tester.getRect(toolbar), toolbarRect);
          expect(fixture.bloc.state.selectedChatIds, {'cached'});
          expect(find.byType(AnimatedConnectingText), findsNothing);
          // The existing selection action still receives taps while offline.
          await tester.tap(
            find.descendant(
              of: toolbar,
              matching: find.byIcon(Icons.done_all_rounded),
            ),
          );
          await _pump(tester);
          expect(fixture.repository.markedRead, [
            {'cached'},
          ]);
          expect(fixture.bloc.state.isSelectionMode, isFalse);
          expect(find.byType(AnimatedConnectingText), findsOneWidget);
          expect(fixture.repository.requests, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final scenario in [
    (
      name: 'network page',
      page: const SocketException('offline'),
      refresh: null,
      provider: true,
      retry: true,
      label: false,
    ),
    (
      name: 'network refresh',
      page: null,
      refresh: const SocketException('offline'),
      provider: true,
      retry: false,
      label: false,
    ),
    (
      name: 'both network',
      page: TimeoutException('page'),
      refresh: const SocketException('offline'),
      provider: true,
      retry: true,
      label: false,
    ),
    (
      name: 'data page',
      page: const FormatException('page data'),
      refresh: null,
      provider: true,
      retry: true,
      label: true,
    ),
    (
      name: 'data refresh',
      page: null,
      refresh: StateError('cache failure'),
      provider: true,
      retry: true,
      label: true,
    ),
    (
      name: 'data page and network refresh',
      page: const FormatException('page data'),
      refresh: const SocketException('offline'),
      provider: true,
      retry: true,
      label: true,
    ),
    (
      name: 'network page and data refresh',
      page: const SocketException('offline'),
      refresh: const FormatException('refresh data'),
      provider: true,
      retry: true,
      label: true,
    ),
    (
      name: 'no provider network fallback',
      page: const SocketException('offline'),
      refresh: null,
      provider: false,
      retry: true,
      label: true,
    ),
    (
      name: 'no provider network refresh fallback',
      page: null,
      refresh: const SocketException('offline'),
      provider: false,
      retry: true,
      label: true,
    ),
  ]) {
    testWidgets('cached rows footer: ${scenario.name}', (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      fixture.status.reportNetworkAvailability(false);
      await _mount(
        tester,
        fixture,
        withProvider: scenario.provider,
        pageError: scenario.page,
        refreshError: scenario.refresh,
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(ChatsPage)))!;
      final retry = find.widgetWithText(FilledButton, l10n.repeat);
      expect(find.byKey(const ValueKey('cached')), findsOneWidget);
      expect(
        find.text(l10n.failedToLoadChats),
        scenario.label ? findsOneWidget : findsNothing,
      );
      if (scenario.retry) {
        expect(retry.hitTestable(), findsOneWidget);
        await tester.tap(retry);
        await _pump(tester);
        expect(fixture.repository.requests, [true]);
      } else {
        expect(retry, findsNothing);
        expect(find.byType(AnimatedConnectingText), findsOneWidget);
        // Suppression follows provider availability, including retained errors
        // after the connection has recovered.
        fixture.status.reportNetworkAvailability(true);
        await _pump(tester);
        expect(retry, findsNothing);
        expect(find.byType(AnimatedConnectingText), findsNothing);
        expect(fixture.repository.requests, isEmpty);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('retained network page error keeps retry after head recovery', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    const pageError = SocketException('continuation failed');
    fixture.status.reportNetworkAvailability(false);
    await _mount(
      tester,
      fixture,
      pageError: pageError,
      refreshError: const SocketException('head failed'),
      hasMoreRemote: true,
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(ChatsPage)))!;
    final retry = find.widgetWithText(FilledButton, l10n.repeat);
    expect(find.byType(AnimatedConnectingText), findsOneWidget);
    expect(find.text(l10n.failedToLoadChats), findsNothing);
    expect(retry.hitTestable(), findsOneWidget);
    expect(fixture.repository.requests, isEmpty);

    // A successful head refresh clears only refreshError. The repository keeps
    // the failed continuation until the user explicitly retries that page.
    fixture.status.reportNetworkAvailability(true);
    fixture.bloc.add(
      ChatsListViewUpdated(
        ChatListViewState(
          chats: [_chat().copyWith(lastMessage: 'refreshed head preview')],
          ready: true,
          hasMoreRemote: true,
          error: pageError,
        ),
        0,
      ),
    );
    await _pump(tester);
    expect(fixture.bloc.state.paginationError, same(pageError));
    expect(fixture.bloc.state.refreshError, isNull);
    expect(find.byType(AnimatedConnectingText), findsNothing);
    expect(find.text(l10n.navChats), findsOneWidget);
    expect(find.text('refreshed head preview'), findsOneWidget);
    expect(find.text(l10n.failedToLoadChats), findsNothing);
    expect(retry.hitTestable(), findsOneWidget);
    expect(fixture.repository.requests, isEmpty);

    await tester.tap(retry);
    await _pump(tester);
    // The real Bloc forwards ChatsLoadMoreRequested(retry: true) to the source.
    expect(fixture.repository.requests, [true]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final error in [
    const SocketException('initial network failure'),
    const FormatException('initial data failure'),
  ]) {
    testWidgets('empty initial failure retains retry: $error', (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      fixture.status.reportNetworkAvailability(false);
      await _mount(tester, fixture, rows: const [], pageError: error);
      final l10n = AppLocalizations.of(tester.element(find.byType(ChatsPage)))!;
      expect(find.text(l10n.failedToLoadChats), findsOneWidget);
      final retry = find.widgetWithText(FilledButton, l10n.repeat);
      expect(retry.hitTestable(), findsOneWidget);
      await tester.tap(retry);
      await _pump(tester);
      expect(fixture.repository.requests, [true]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('compact loading indicator remains 24 with stroke 2.5', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await _mount(tester, fixture, loadingMore: true);
    final spinner = find.byType(CircularProgressIndicator);
    expect(tester.getSize(spinner), const Size(24, 24));
    expect(tester.widget<CircularProgressIndicator>(spinner).strokeWidth, 2.5);
    fixture.status.reportNetworkAvailability(false);
    await _pump(tester);
    expect(tester.getSize(spinner), const Size(24, 24));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Chat _chat() => Chat(
  id: 'cached',
  peerId: '',
  userName: 'Cached peer',
  lastMessage: 'cached preview',
  lastMessageTime: DateTime(2026),
  unreadCount: 1,
  isOnline: true,
  isLastMessageFromMe: false,
);

Future<void> _pump(WidgetTester tester) async {
  // A queued Bloc event can reach BlocBuilder after the first frame. Build
  // that state before advancing the clock so its toolbar transition actually
  // gets the full settling interval. Keep this bounded for spinner cases.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  String locale = 'ru',
  double scale = 1,
  bool withProvider = true,
  List<Chat>? rows,
  Object? pageError,
  Object? refreshError,
  bool loadingMore = false,
  bool hasMoreRemote = false,
}) async {
  // Feed repository snapshots through the real Bloc, without network work.
  fixture.bloc.add(
    ChatsListViewUpdated(
      ChatListViewState(
        chats: rows ?? [_chat()],
        ready: true,
        error: pageError,
        refreshError: refreshError,
        isLoadingRemote: loadingMore,
        hasMoreRemote: hasMoreRemote,
      ),
      0,
    ),
  );
  Widget app = RepositoryProvider<IChatsRepository>.value(
    value: fixture.repository,
    child: BlocProvider.value(
      value: fixture.bloc,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
        ),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding:
                MediaQuery.sizeOf(context).width >
                    MediaQuery.sizeOf(context).height
                ? const EdgeInsets.only(left: 28, right: 12)
                : const EdgeInsets.only(top: 24),
          ),
          child: child!,
        ),
        home: const ChatsPage(),
      ),
    ),
  );
  if (withProvider) {
    app = RepositoryProvider<AppConnectionStatus>.value(
      value: fixture.status,
      child: app,
    );
  }
  await tester.pumpWidget(app);
  await _pump(tester);
}

class _Fixture {
  final repository = _Repository();
  late final bloc = ChatsBloc(chatsRepository: repository);
  final status = AppConnectionStatus(
    accountSessionController: AccountSessionController(initialUserId: 'u'),
    presentationDelay: Duration.zero,
  );

  Future<void> close() async {
    await bloc.close();
    status.dispose();
  }
}

class _Repository implements IChatsRepository, IChatsListRepository {
  final requests = <bool>[];
  final markedRead = <Set<String>>[];

  @override
  Future<String?> resolveAvatar(Chat chat) async => null;
  @override
  Stream<ChatListViewState> watchChatList() => const Stream.empty();
  @override
  Future<void> setChatListQuery(String query) async {}
  @override
  Future<void> loadMoreChatList({bool retry = false}) async =>
      requests.add(retry);
  @override
  void setChatListObservedIds(
    Set<String> visibleIds,
    Set<String> selectedIds,
  ) {}
  @override
  Future<void> markAsRead(Set<String> ids) async => markedRead.add(Set.of(ids));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
