// Regression coverage for loading, cache continuation and remote page ownership.
// Uses production UI/Bloc/repository/SQLite; only the server boundary is controlled.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/repositories/presence/presence.dart';
import 'package:yap_chat/ui/ui.dart';

final _reports = <Map<String, Object?>>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Match the production metrics using the bundled variable font. Assign the
    // mutable styles before their lazy Google Fonts getters perform network IO.
    AppTextStyles.chatName = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 18,
      fontWeight: FontWeight.w500,
      height: 1.33,
    );
    AppTextStyles.messagePreview = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.25,
    );
    AppTextStyles.metadata = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.14,
    );
    AppTextStyles.badgeText = const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.14,
    );
    for (final family in ['Roboto', 'RobotoFlex']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    }
  });
  tearDownAll(() {
    final file = File('.dart_tool/chat_list_loading_diagnosis/results.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_reports),
    );
  });

  for (final query in ['peer', 'missing']) {
    testWidgets('search frame diagnosis query=$query', (tester) async {
      final h = (await tester.runAsync(
        () => _Harness.create(2, complete: true),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'diagnosis-main', turns: 24);
      expect(h.bloc.state.chats, hasLength(2));
      final requests = h.remote.pages.length;
      h.trace.headGate = Completer<void>();
      await tester.enterText(find.byType(TextField), query);
      await _frames(tester, h, 'diagnosis-local-read-pending', turns: 3);
      final pending = {
        'query': h.bloc.state.searchQuery,
        'status': h.bloc.state.status.name,
        'rows': find.byType(ChatListItem).evaluate().length,
        'spinner': find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
        'not_found': find.text('ничего не нашли').evaluate().isNotEmpty,
      };
      expect(h.bloc.state.status, ChatsStatus.loading);
      expect(find.byType(ChatListItem), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      h.trace.headGate!.complete();
      await _frames(tester, h, 'diagnosis-local-read-ready', turns: 20);
      expect(h.bloc.state.status, ChatsStatus.success);
      expect(h.bloc.state.chats.length, query == 'peer' ? 2 : 0);
      expect(h.remote.pages.length, requests);
      await _finish(
        tester,
        h,
        'search-frame-$query',
        extra: {'pending_frame': pending},
      );
    });
  }

  for (final count in [0, 2, 49, 50, 51]) {
    for (final offline in [false, true]) {
      testWidgets('loading diagnosis startup cached=$count offline=$offline', (
        tester,
      ) async {
        final h = await tester.runAsync(() => _Harness.create(count));
        final harness = h!;
        harness.remote.offline = offline;
        await _mount(tester, harness);
        await _frames(tester, harness, 'startup', turns: 24);
        if (count > 0) {
          expect(harness.bloc.state.chats.length, count.clamp(0, 50));
          expect(harness.bloc.state.status, ChatsStatus.success);
        } else {
          expect(
            harness.bloc.state.status,
            offline ? ChatsStatus.failure : ChatsStatus.success,
          );
        }
        expect(
          harness.bloc.state.loadError,
          offline ? isA<SocketException>() : isNull,
        );
        expect(harness.remote.fullReads, 0);
        expect(harness.remote.maximumConcurrent, lessThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
        await _finish(tester, harness, 'startup-$count-$offline');
      });
    }
  }

  for (final complete in [false, true]) {
    testWidgets(
      'loading diagnosis file cache restart offline complete=$complete',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('chat-loading-probe-'),
        ))!;
        final file = File('${directory.path}/cache.sqlite');
        addTearDown(() async {
          await tester.runAsync(() async {
            for (final entry in directory.listSync(followLinks: false)) {
              if (entry is! File) {
                throw StateError(
                  'Unexpected entry in owned diagnostic directory',
                );
              }
              entry.deleteSync();
            }
            directory.deleteSync();
          });
        });
        await tester.runAsync(() async {
          final writer = AppDatabase.forTesting(NativeDatabase(file));
          try {
            final cache = ChatsCacheDataSource(
              database: writer,
              userIdProvider: () => 'owner',
            );
            await cache.replaceAll([_chat(0), _chat(1)]);
            if (complete) {
              final backend = _Remote([_chat(0), _chat(1)]);
              await cache.applyListPage(
                await cache.beginListRefresh(),
                backend.page('', null, 50),
              );
              await backend.sdk.dispose();
            }
          } finally {
            await writer.close();
          }
        });
        final h = (await tester.runAsync(
          () => _Harness.create(2, file: file, seed: false),
        ))!;
        h.remote.offline = true;
        await _mount(tester, h);
        await _frames(tester, h, 'reopened-file-offline', turns: 24);
        expect(h.bloc.state.chats.map((c) => c.id), [_chat(1).id, _chat(0).id]);
        await _finish(tester, h, 'file-restart-$complete');
      },
    );

    testWidgets(
      'loading diagnosis two cached rows and held refresh complete=$complete',
      (tester) async {
        final h = (await tester.runAsync(
          () => _Harness.create(2, complete: complete),
        ))!;
        h.remote.hold = Completer<void>();
        await _mount(tester, h);
        await _frames(tester, h, 'held-head', turns: 16);
        expect(h.remote.pages, hasLength(1));
        expect(h.bloc.state.chats, hasLength(2));
        expect(find.byType(ListView), findsOneWidget);
        expect(h.remote.pages.single.after, isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(h.bloc.state.hasMoreRemote, false);
        final before = h.snapshot();
        h.remote.hold!.complete();
        await _frames(tester, h, 'released-head', turns: 30);
        expect(h.bloc.state.chats, hasLength(2));
        expect(h.bloc.state.hasMoreChats, false);
        expect(h.bloc.state.loadError, isNull);
        expect(h.remote.maximumConcurrent, 1);
        expect(h.remote.pages, hasLength(1));
        expect(h.trace.continuationReads, 0);
        await _finish(
          tester,
          h,
          'held-refresh-$complete',
          extra: {'while_held': before},
        );
      },
    );
  }

  testWidgets(
    'loading regression initial head is shared with the production UI consumer',
    (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(2)))!;
      h.remote.hold = Completer<void>();
      await _mount(tester, h, recordViews: false);
      await _frames(tester, h, 'single-consumer-held', turns: 16);
      expect(h.bloc.state.chats, hasLength(2));
      expect(h.remote.pages, hasLength(1));
      h.remote.hold!.complete();
      await _frames(tester, h, 'single-consumer-complete', turns: 30);
      expect(h.remote.pages, hasLength(1));
      expect(
        h.remote.pages.every((r) => r.after == null && r.query.isEmpty),
        true,
      );
      expect(h.bloc.state.loadError, isNull);
      await _finish(tester, h, 'single-consumer-head');
    },
  );

  testWidgets('loading diagnosis a slow local cache is independent of HTTP', (
    tester,
  ) async {
    final h = (await tester.runAsync(() => _Harness.create(2)))!;
    h.trace.headGate = Completer<void>();
    h.remote.hold = Completer<void>();
    await _mount(tester, h);
    await _frames(tester, h, 'held-cache', turns: 8);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 160));
    expect(h.trace.headReads, greaterThan(0));
    expect(h.bloc.state.chats, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    h.trace.headGate!.complete();
    await _frames(tester, h, 'cache-ready-http-held', turns: 16);
    expect(h.bloc.state.chats, hasLength(2));
    expect(find.byType(ListView), findsOneWidget);
    expect(h.remote.pages, hasLength(1));
    h.remote.hold!.complete();
    await _frames(tester, h, 'all-ready', turns: 24);
    await _finish(tester, h, 'slow-cache');
  });

  testWidgets('loading regression confirmed end does no continuation work', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => _Harness.create(2, complete: true),
    ))!;
    await _mount(tester, h);
    await _frames(tester, h, 'ready', turns: 24);
    expect(h.bloc.state.hasMoreChats, false);
    final pages = h.remote.pages.length;
    final offset = h.views.length;
    h.trace.tailGate = Completer<void>();
    h.bloc.add(const ChatsLoadMoreRequested());
    await _frames(tester, h, 'forced-cache-probe', turns: 8);
    expect(h.views.skip(offset).any((v) => v.isLoadingCache), false);
    expect(h.remote.pages.length, pages);
    h.trace.tailGate!.complete();
    await _frames(tester, h, 'probe-done', turns: 10);
    expect(h.bloc.state.hasMoreChats, false);
    expect(h.remote.pages.length, pages);
    await _finish(tester, h, 'empty-local-probe');
  });

  testWidgets(
    'a fresh complete catalog searches locally even when network disappears',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Harness.create(2, complete: true),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      h.remote.offline = true;
      h.remote.hold = Completer<void>();
      final pages = h.remote.pages.length;
      await tester.enterText(find.byType(TextField), 'peer');
      await tester.pump(const Duration(milliseconds: 220));
      await _frames(tester, h, 'search-waiting-for-http', turns: 12);
      expect(
        h.remote.pages.skip(pages).where((r) => r.query == 'peer'),
        isEmpty,
      );
      h.remote.hold!.complete();
      await _frames(tester, h, 'offline-search', turns: 24);
      expect(h.remote.pages.skip(pages).any((r) => r.query == 'peer'), false);
      expect(h.bloc.state.chats, hasLength(2));
      expect(h.bloc.state.loadError, isNull);
      expect(find.textContaining('не удалось загрузить чаты'), findsNothing);
      await _finish(tester, h, 'offline-search');
    },
  );

  for (final mode in ['quota', 'malformed']) {
    testWidgets(
      'loading diagnosis separates transport from $mode error facts',
      (tester) async {
        final h = (await tester.runAsync(
          () => _Harness.create(2, complete: true),
        ))!;
        h.remote.status = mode == 'quota' ? 429 : 200;
        h.remote.malformed = mode == 'malformed';
        await _mount(tester, h);
        await _frames(tester, h, 'non-transport-error', turns: 24);
        expect(h.bloc.state.chats, hasLength(2));
        expect(
          h.bloc.state.loadError,
          mode == 'quota' ? isA<PostgrestException>() : isA<FormatException>(),
        );
        expect(
          find.textContaining('не удалось загрузить чаты'),
          findsOneWidget,
        );
        await _finish(tester, h, 'error-$mode');
      },
    );
  }

  for (final count in [49, 50, 51, 1000]) {
    testWidgets(
      'loading diagnosis actual scroll distinguishes continuation cached=$count',
      (tester) async {
        final h = (await tester.runAsync(
          () => _Harness.create(count, complete: true),
        ))!;
        await _mount(tester, h);
        await _frames(tester, h, 'before-scroll', turns: 24);
        expect(h.remote.pages, hasLength(1));
        final scroll = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scroll).position;
        position.jumpTo(position.maxScrollExtent);
        await _frames(tester, h, 'after-scroll', turns: 32);
        expect(h.bloc.state.chats.length, count.clamp(0, 100));
        expect(
          h.bloc.state.chats.map((c) => c.id).toSet().length,
          h.bloc.state.chats.length,
        );
        expect(
          h.remote.pages.where((r) => r.after != null).length,
          count > 50 ? 1 : 0,
        );
        expect(h.bloc.state.hasMoreChats, count > 100);
        await _finish(tester, h, 'scroll-$count');
      },
    );
  }

  testWidgets(
    'loading diagnosis warm page reentry reuses the existing shared watcher',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Harness.create(2, complete: true),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'first-entry', turns: 24);
      final pages = h.remote.pages.length;
      await tester.pumpWidget(const SizedBox.shrink());
      var closed = false;
      unawaited(h.bloc.close().then((_) => closed = true));
      for (var i = 0; i < 20 && !closed; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
      expect(closed, true);
      await _mount(tester, h, reentry: true);
      await _frames(tester, h, 'warm-reentry', turns: 16);
      expect(h.bloc.state.chats, hasLength(2));
      expect(h.remote.pages.length, pages);
      await _finish(tester, h, 'warm-reentry');
    },
  );

  testWidgets(
    'loading diagnosis periodic failure preserves cache and subscribed recovery clears it',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Harness.create(2, complete: true),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      h.remote.offline = true;
      await tester.pump(const Duration(seconds: 21));
      await _frames(tester, h, 'periodic-offline', turns: 24);
      expect(h.bloc.state.chats, hasLength(2));
      expect(h.bloc.state.loadError, isA<SocketException>());
      h.remote.offline = false;
      h.remote.changes.add(
        const ConversationChange(conversationId: null, reason: 'subscribed'),
      );
      await _frames(tester, h, 'recovered', turns: 32);
      expect(h.bloc.state.chats, hasLength(2));
      expect(h.bloc.state.loadError, isNull);
      await _finish(tester, h, 'periodic-and-recovery');
    },
  );

  for (final complete in [false, true]) {
    testWidgets(
      'refresh retry is coalesced with no next page complete=$complete',
      (tester) async {
        final h = (await tester.runAsync(
          () => _Harness.create(2, complete: complete),
        ))!;
        h.remote.offline = true;
        await _mount(tester, h);
        await _frames(tester, h, 'head-failed', turns: 24);
        expect(h.remote.pages, hasLength(1));
        expect(h.bloc.state.refreshError, isA<SocketException>());
        expect(h.bloc.state.paginationError, isNull);
        expect(h.bloc.state.hasMoreRemote, false);
        expect(find.text('не удалось загрузить чаты'), findsOneWidget);
        expect(find.text('повторить'), findsOneWidget);
        h.remote.offline = false;
        h.remote.hold = Completer<void>();
        await tester.tap(find.widgetWithText(FilledButton, 'повторить'));
        for (var i = 0; i < 20; i++) {
          h.bloc.add(const ChatsLoadMoreRequested(retry: true));
        }
        await _frames(tester, h, 'retry-held', turns: 16);
        expect(h.remote.pages, hasLength(2));
        expect(h.bloc.state.chats, hasLength(2));
        expect(h.bloc.state.isRefreshing, true);
        h.remote.hold!.complete();
        await _frames(tester, h, 'retry-done', turns: 24);
        expect(h.remote.pages, hasLength(2));
        expect(h.bloc.state.loadError, isNull);
        expect(h.bloc.state.isRefreshing, false);
        expect(find.byType(FilledButton), findsNothing);
        expect(h.remote.maximumConcurrent, 1);
        await _finish(tester, h, 'head-retry-$complete');
      },
    );
  }

  for (final count in [0, 1, 49, 50, 51]) {
    testWidgets('search complete-catalog boundary $count', (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(count)))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      await tester.enterText(find.byType(TextField), 'peer 1');
      await _frames(tester, h, 'local-boundary', turns: 4);
      expect(h.remote.pages, hasLength(1));
      expect(h.bloc.state.searchQuery, 'peer 1');
      await tester.pump(const Duration(milliseconds: 360));
      await _frames(tester, h, 'remote-boundary', turns: 24);
      expect(
        h.remote.pages.where((p) => p.query.isNotEmpty),
        hasLength(count <= 50 ? 0 : 1),
      );
      expect(h.bloc.state.loadError, isNull);
      if (count <= 50) {
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
      await _finish(tester, h, 'search-boundary-$count');
    });
  }

  testWidgets(
    'reused search continues both cached and remote pages without another head',
    (tester) async {
      var micros = 0;
      final h = (await tester.runAsync(
        () => _Harness.create(
          1000,
          seed: false,
          searchPolicy: ChatListSearchPolicy(elapsedMicros: () => micros),
        ),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      await tester.enterText(find.byType(TextField), 'peer 9');
      await tester.pump(const Duration(milliseconds: 360));
      await _frames(tester, h, 'search-first-page', turns: 24);
      expect(h.bloc.state.chats, hasLength(50));
      _jumpToEnd(tester);
      await _frames(tester, h, 'search-second-page', turns: 24);
      expect(h.bloc.state.chats, hasLength(100));
      for (final query in ['peer 8', 'peer 9']) {
        micros += 2000000;
        await tester.enterText(find.byType(TextField), query);
        await tester.pump(const Duration(milliseconds: 360));
        await _frames(tester, h, 'switch-$query', turns: 24);
      }
      expect(
        h.remote.pages.where((p) => p.query == 'peer 9' && p.after == null),
        hasLength(1),
      );
      _jumpToEnd(tester);
      await _frames(tester, h, 'reused-continuation', turns: 24);
      expect(h.bloc.state.chats, hasLength(111));
      expect(h.bloc.state.chats.map((c) => c.id).toSet(), hasLength(111));
      expect(h.bloc.state.hasMoreRemote, false);
      _jumpToEnd(tester);
      await _frames(tester, h, 'cached-tail-confirmed', turns: 16);
      expect(h.bloc.state.hasMoreChats, false);
      expect(h.remote.pages.where((p) => p.query == 'peer 9'), hasLength(3));
      await _finish(tester, h, 'search-reused-pagination');
    },
  );

  testWidgets(
    'a changed persisted search revision rejects a fresh memory memo',
    (tester) async {
      var micros = 0;
      final h = (await tester.runAsync(
        () => _Harness.create(
          1000,
          searchPolicy: ChatListSearchPolicy(elapsedMicros: () => micros),
        ),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      for (final query in ['peer 9', 'peer 8']) {
        micros += 2000000;
        await tester.enterText(find.byType(TextField), query);
        await tester.pump(const Duration(milliseconds: 360));
        await _frames(tester, h, 'original-$query', turns: 24);
      }
      await tester.runAsync(() => h.cache.beginListRefresh(query: 'peer 9'));
      micros += 2000000;
      await tester.enterText(find.byType(TextField), 'peer 9');
      await tester.pump(const Duration(milliseconds: 360));
      await _frames(tester, h, 'revision-changed', turns: 24);
      expect(h.remote.pages.where((p) => p.query == 'peer 9'), hasLength(2));
      expect(h.bloc.state.loadError, isNull);
      await _finish(tester, h, 'search-revision-invalidation');
    },
  );

  testWidgets(
    'rapid query replacement preserves the current SQLite tail subscription',
    (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(50)))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      await tester.enterText(find.byType(TextField), 'peer 1');
      await tester.enterText(find.byType(TextField), 'peer 2');
      await tester.enterText(find.byType(TextField), 'peer');
      await _frames(tester, h, 'new-query-running', turns: 12);
      expect(h.bloc.state.chats, hasLength(50));
      expect(h.bloc.state.hasMoreCached, false);
      final older = _chat(1001).copyWith(lastMessageTime: DateTime.utc(2020));
      await tester.runAsync(
        () => h.cache.applySummaryBatch({older.id}, [older]),
      );
      await _frames(tester, h, 'new-tail-event', turns: 16);
      expect(h.bloc.state.hasMoreCached, true);
      h.bloc.add(const ChatsLoadMoreRequested());
      await _frames(tester, h, 'new-tail-loaded', turns: 16);
      expect(h.bloc.state.chats, hasLength(51));
      expect(h.bloc.state.chats.last.id, older.id);
      expect(h.bloc.state.loadError, isNull);
      expect(h.remote.pages, hasLength(1));
      await _finish(tester, h, 'search-cancellation-race');
    },
  );

  testWidgets(
    'a local search read failure is retryable and does not mark network offline',
    (tester) async {
      final policy = ChatListSearchPolicy();
      final h = (await tester.runAsync(
        () => _Harness.create(1000, searchPolicy: policy),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      h.trace.searchFailure = StateError('local search read failed');
      await tester.enterText(find.byType(TextField), 'peer 9');
      await _frames(tester, h, 'local-error', turns: 8);
      expect(h.bloc.state.status, ChatsStatus.failure);
      expect(h.bloc.state.paginationError, isA<StateError>());
      expect(h.bloc.state.refreshError, isNull);
      expect(policy.canRequest, true);
      expect(h.remote.pages, hasLength(1));
      h.trace.searchFailure = null;
      h.bloc.add(const ChatsLoadMoreRequested(retry: true));
      await _frames(tester, h, 'local-retry', turns: 24);
      expect(h.bloc.state.chats, isNotEmpty);
      expect(h.bloc.state.loadError, isNull);
      expect(policy.canRequest, true);
      await _finish(tester, h, 'search-sqlite-failure');
    },
  );

  testWidgets('closing the only UI consumer cancels an unsent search', (
    tester,
  ) async {
    final h = (await tester.runAsync(() => _Harness.create(1000)))!;
    await _mount(tester, h, recordViews: false);
    await _frames(tester, h, 'ready', turns: 24);
    await tester.enterText(find.byType(TextField), 'peer 9');
    await _frames(tester, h, 'local-before-close', turns: 3);
    expect(h.remote.pages, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    var closed = false;
    unawaited(h.bloc.close().then((_) => closed = true));
    await _frames(tester, h, 'closed', turns: 12);
    expect(closed, true);
    await tester.pump(const Duration(seconds: 1));
    await _frames(tester, h, 'after-debounce', turns: 12);
    expect(h.remote.pages, hasLength(1));
    await _finish(tester, h, 'search-close-before-send');
  });

  testWidgets(
    'logout and return to the same user cannot send a previous session search',
    (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(1000)))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      await tester.enterText(find.byType(TextField), 'peer 9');
      await _frames(tester, h, 'before-session-change', turns: 3);
      h.account.setAuthenticatedUser(null);
      h.account.setAuthenticatedUser('owner');
      await tester.pump(const Duration(seconds: 1));
      await _frames(tester, h, 'new-session', turns: 12);
      expect(h.remote.pages, hasLength(1));
      await _finish(tester, h, 'search-stale-session');
    },
  );

  testWidgets(
    'search shows local rows before debounce and sends only the latest prefix',
    (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(1000)))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      h.remote.hold = Completer<void>();
      final before = h.remote.pages.length;
      for (final query in ['p', 'pe', 'peer', 'peer 9']) {
        await tester.enterText(find.byType(TextField), query);
        await _frames(tester, h, 'local-$query', turns: 3);
        expect(h.bloc.state.searchQuery, query);
        expect(h.bloc.state.chats, isNotEmpty);
        expect(
          h.bloc.state.chats.every(
            (c) => c.userName.toLowerCase().startsWith(query),
          ),
          true,
        );
        expect(h.remote.pages, hasLength(before));
      }
      await tester.pump(const Duration(milliseconds: 360));
      await _frames(tester, h, 'latest-remote-held', turns: 12);
      expect(h.remote.pages, hasLength(before + 1));
      expect(h.remote.pages.last.query, 'peer 9');
      expect(h.bloc.state.chats, isNotEmpty);
      h.remote.hold!.complete();
      await _frames(tester, h, 'latest-ready', turns: 24);
      expect(h.bloc.state.loadError, isNull);
      await _finish(tester, h, 'search-local-before-server');
    },
  );

  testWidgets(
    'fresh A-B-A search reuses committed cursor and skips periodic duplicate',
    (tester) async {
      var micros = 0;
      final policy = ChatListSearchPolicy(elapsedMicros: () => micros);
      final h = (await tester.runAsync(
        () => _Harness.create(1000, searchPolicy: policy),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      for (final query in ['peer 9', 'peer 8', 'peer 9']) {
        micros += 2000000;
        await tester.enterText(find.byType(TextField), query);
        await tester.pump(const Duration(milliseconds: 360));
        await _frames(tester, h, 'reuse-$query', turns: 24);
        expect(h.bloc.state.loadError, isNull);
      }
      expect(h.remote.pages.where((p) => p.query == 'peer 9'), hasLength(1));
      expect(h.remote.pages.where((p) => p.query == 'peer 8'), hasLength(1));
      final cursor = (await tester.runAsync(
        () => h.cache.readListState(query: 'peer 9'),
      ))!.nextCursor;
      expect(cursor, isNotNull);
      final beforePeriodic = h.remote.pages.length;
      micros += 21000000;
      await tester.pump(const Duration(seconds: 21));
      await _frames(tester, h, 'periodic-reuses-fresh-query', turns: 24);
      expect(h.remote.pages, hasLength(beforePeriodic + 1));
      expect(h.remote.pages.where((p) => p.query == 'peer 9'), hasLength(1));
      final before = h.remote.pages.length;
      h.remote.changes.add(
        const ConversationChange(conversationId: null, reason: 'subscribed'),
      );
      await _frames(tester, h, 'recovery-invalidates-search', turns: 40);
      await tester.pump(const Duration(seconds: 1));
      await _frames(tester, h, 'recovery-settled', turns: 24);
      expect(h.remote.pages.length, greaterThan(before));
      expect(h.remote.pages.where((p) => p.query == 'peer 9'), hasLength(2));
      expect(h.bloc.state.chats, isNotEmpty);
      await _finish(tester, h, 'search-reuse-and-recovery');
    },
  );

  testWidgets(
    'old persisted complete coverage cannot suppress a search before fresh head',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Harness.create(2, complete: true),
      ))!;
      h.remote.hold = Completer<void>();
      await _mount(tester, h);
      await _frames(tester, h, 'head-held', turns: 16);
      await tester.enterText(find.byType(TextField), 'peer');
      await _frames(tester, h, 'search-waits-for-queue', turns: 32);
      expect(h.bloc.state.chats, hasLength(2));
      expect(h.remote.pages, hasLength(1));
      h.remote.hold!.complete();
      await _frames(tester, h, 'fresh-head-proves-complete', turns: 24);
      expect(h.remote.pages, hasLength(1));
      expect(h.bloc.state.isRefreshing, false);
      expect(h.bloc.state.hasMoreRemote, false);
      await _finish(tester, h, 'search-proof-only-after-head');
    },
  );

  testWidgets(
    'complete catalog proof expires and an absent cached name reaches server',
    (tester) async {
      var micros = 0;
      final h = (await tester.runAsync(
        () => _Harness.create(
          2,
          searchPolicy: ChatListSearchPolicy(elapsedMicros: () => micros),
        ),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      await tester.enterText(find.byType(TextField), 'not-here');
      await _frames(tester, h, 'fresh-local-empty', turns: 24);
      expect(h.remote.pages, hasLength(1));
      micros = 31000000;
      h.remote.rows.add(_chat(2).copyWith(userName: 'New person'));
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump(const Duration(milliseconds: 360));
      await _frames(tester, h, 'expired-proof', turns: 24);
      expect(h.remote.pages, hasLength(2));
      expect(h.remote.pages.last.query, 'new');
      expect(h.bloc.state.chats.single.userName, 'New person');
      await _finish(tester, h, 'search-proof-expiry');
    },
  );

  testWidgets(
    '429 search cooldown blocks edits and retries but permits recovery after expiry',
    (tester) async {
      var micros = 0;
      final h = (await tester.runAsync(
        () => _Harness.create(
          1000,
          searchPolicy: ChatListSearchPolicy(elapsedMicros: () => micros),
        ),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'ready', turns: 24);
      h.remote.status = 429;
      await tester.enterText(find.byType(TextField), 'peer 9');
      await tester.pump(const Duration(milliseconds: 360));
      await _frames(tester, h, 'quota-search', turns: 24);
      expect(h.remote.pages, hasLength(2));
      expect(h.bloc.state.refreshError, isA<PostgrestException>());
      for (final query in ['peer 8', 'peer 7', 'peer 6']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pump(const Duration(seconds: 1));
        await _frames(tester, h, 'quota-edit-$query', turns: 12);
        h.bloc.add(const ChatsLoadMoreRequested(retry: true));
        await _frames(tester, h, 'quota-retry-$query', turns: 12);
        expect(h.remote.pages, hasLength(2));
        expect(h.bloc.state.chats, isNotEmpty);
      }
      micros = 61000000;
      h.remote.status = 200;
      await tester.enterText(find.byType(TextField), 'peer 5');
      await tester.pump(const Duration(milliseconds: 360));
      await _frames(tester, h, 'quota-expired', turns: 24);
      expect(h.remote.pages, hasLength(3));
      expect(h.bloc.state.loadError, isNull);
      await _finish(tester, h, 'search-quota-cooldown');
    },
  );

  testWidgets(
    'known offline transport uses all cached search results without per-edit RPC',
    (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(1000)))!;
      h.remote.offline = true;
      await _mount(tester, h);
      await _frames(tester, h, 'offline-head', turns: 24);
      for (final query in ['p', 'peer 1', 'peer 9', 'absent']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pump(const Duration(seconds: 1));
        await _frames(tester, h, 'offline-edit-$query', turns: 12);
        expect(h.remote.pages, hasLength(1));
        expect(h.bloc.state.isRefreshing, false);
        expect(h.bloc.state.chats.isNotEmpty, query != 'absent');
      }
      h.remote.offline = false;
      h.remote.changes.add(
        const ConversationChange(conversationId: null, reason: 'subscribed'),
      );
      await _frames(tester, h, 'offline-recovery', turns: 40);
      await tester.pump(const Duration(seconds: 1));
      await _frames(tester, h, 'offline-recovery-query', turns: 24);
      expect(h.remote.pages, hasLength(3));
      expect(h.remote.pages.last.query, 'absent');
      expect(h.bloc.state.loadError, isNull);
      await _finish(tester, h, 'search-offline-edits-and-recovery');
    },
  );

  testWidgets(
    'returning from search refreshes unconfirmed main coverage once',
    (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(2)))!;
      h.remote.offline = true;
      await _mount(tester, h);
      await _frames(tester, h, 'offline-main', turns: 24);
      await tester.enterText(find.byType(TextField), 'peer');
      await tester.pump(const Duration(milliseconds: 220));
      await _frames(tester, h, 'offline-search', turns: 24);
      expect(h.remote.pages, hasLength(1));
      h.remote.offline = false;
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 220));
      await _frames(tester, h, 'main-restored', turns: 24);
      expect(h.remote.pages, hasLength(2));
      expect(h.remote.pages.last.query, isEmpty);
      expect(h.remote.pages.last.after, isNull);
      expect(h.bloc.state.chats, hasLength(2));
      expect(h.bloc.state.isRefreshing, false);
      expect(h.bloc.state.loadError, isNull);
      await _finish(tester, h, 'restored-unconfirmed-main');
    },
  );

  testWidgets(
    'a failed head is retained when the initial SQLite read is slow',
    (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(2)))!;
      h.remote.offline = true;
      h.trace.headGate = Completer<void>();
      await _mount(tester, h);
      await _frames(tester, h, 'failed-http-with-cache-held', turns: 16);
      expect(h.remote.pages, hasLength(1));
      h.trace.headGate!.complete();
      await _frames(tester, h, 'slow-cache-after-failed-http', turns: 24);
      expect(h.bloc.state.chats, hasLength(2));
      expect(h.bloc.state.status, ChatsStatus.success);
      expect(h.bloc.state.refreshError, isA<SocketException>());
      expect(h.bloc.state.isRefreshing, false);
      expect(h.remote.pages, hasLength(1));
      await _finish(tester, h, 'slow-cache-failed-http');
    },
  );

  testWidgets('an empty offline cache can retry the initial head and recover', (
    tester,
  ) async {
    final h = (await tester.runAsync(() => _Harness.create(2, seed: false)))!;
    h.remote.offline = true;
    await _mount(tester, h);
    await _frames(tester, h, 'empty-offline', turns: 24);
    expect(h.bloc.state.status, ChatsStatus.failure);
    expect(h.bloc.state.paginationError, isNull);
    expect(h.bloc.state.refreshError, isA<SocketException>());
    h.remote.offline = false;
    await tester.tap(find.widgetWithText(FilledButton, 'повторить'));
    await _frames(tester, h, 'empty-recovered', turns: 24);
    expect(h.remote.pages, hasLength(2));
    expect(h.bloc.state.status, ChatsStatus.success);
    expect(h.bloc.state.chats, hasLength(2));
    expect(h.bloc.state.loadError, isNull);
    await _finish(tester, h, 'empty-cache-retry');
  });

  testWidgets('cached next page stays accessible during a held head refresh', (
    tester,
  ) async {
    final h = (await tester.runAsync(() => _Harness.create(1000)))!;
    h.remote.hold = Completer<void>();
    await _mount(tester, h);
    await _frames(tester, h, 'held-head', turns: 24);
    expect(h.bloc.state.chats, hasLength(50));
    _jumpToEnd(tester);
    await _frames(tester, h, 'cached-page-with-http-held', turns: 24);
    expect(h.bloc.state.chats, hasLength(100));
    expect(h.remote.pages, hasLength(1));
    expect(h.bloc.state.isRefreshing, true);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    h.remote.hold!.complete();
    await _frames(tester, h, 'head-done', turns: 24);
    expect(h.bloc.state.chats, hasLength(100));
    expect(h.remote.pages, hasLength(1));
    await _finish(tester, h, 'cache-does-not-wait-for-refresh');
  });

  testWidgets(
    'all 1000 cached chats remain reachable offline without more HTTP',
    (tester) async {
      final h = (await tester.runAsync(() => _Harness.create(1000)))!;
      h.remote.offline = true;
      await _mount(tester, h);
      await _frames(tester, h, 'offline-head', turns: 24);
      for (var i = 0; i < 19; i++) {
        _jumpToEnd(tester);
        await _frames(tester, h, 'offline-page-$i', turns: 12);
        expect(h.bloc.state.chats.length, (i + 2) * 50);
      }
      expect(h.bloc.state.chats.map((c) => c.id).toSet(), hasLength(1000));
      expect(h.bloc.state.hasMoreCached, false);
      final reads = h.trace.continuationReads;
      _jumpToEnd(tester);
      for (var i = 0; i < 10; i++) {
        h.bloc.add(const ChatsLoadMoreRequested());
      }
      await _frames(tester, h, 'offline-end', turns: 20);
      expect(h.trace.continuationReads, reads);
      expect(h.remote.pages, hasLength(1));
      expect(h.remote.fullReads, 0);
      await _finish(tester, h, 'all-offline-1000');
    },
  );

  testWidgets(
    'remote page failure retries the same cursor once and retains rows',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Harness.create(200, seed: false),
      ))!;
      await _mount(tester, h);
      await _frames(tester, h, 'remote-head', turns: 24);
      expect(h.bloc.state.chats, hasLength(50));
      h.remote.continuationStatus = 429;
      _jumpToEnd(tester);
      await _frames(tester, h, 'remote-page-failed', turns: 24);
      expect(h.remote.pages, hasLength(2));
      expect(h.remote.pages.last.after, isNotNull);
      expect(h.bloc.state.paginationError, isA<PostgrestException>());
      expect(h.bloc.state.refreshError, isNull);
      expect(h.bloc.state.chats, hasLength(50));
      _jumpToEnd(tester);
      await _frames(tester, h, 'no-auto-error-loop', turns: 24);
      expect(h.remote.pages, hasLength(2));
      h.remote.continuationStatus = null;
      h.remote.hold = Completer<void>();
      await tester.tap(find.widgetWithText(FilledButton, 'повторить'));
      await _frames(tester, h, 'remote-page-retry-held', turns: 16);
      expect(h.remote.pages, hasLength(3));
      expect(
        h.remote.pages.last.after!.conversationId,
        h.remote.pages[1].after!.conversationId,
      );
      expect(h.bloc.state.isLoadingMore, true);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .strokeWidth,
        2.5,
      );
      h.remote.hold!.complete();
      await _frames(tester, h, 'remote-page-retry-done', turns: 24);
      expect(h.bloc.state.chats, hasLength(100));
      expect(h.bloc.state.chats.map((c) => c.id).toSet(), hasLength(100));
      expect(h.bloc.state.loadError, isNull);
      expect(h.remote.maximumConcurrent, 1);
      await _finish(tester, h, 'remote-page-retry');
    },
  );

  testWidgets(
    'confirmed short server pages fill viewport without fetching whole catalog',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Harness.create(40, seed: false),
      ))!;
      h.remote.responseLimit = 2;
      await _mount(tester, h);
      await _frames(tester, h, 'short-pages', turns: 80);
      expect(h.remote.pages.length, inExclusiveRange(1, 15));
      expect(h.bloc.state.chats.length, h.remote.pages.length * 2);
      expect(
        h.bloc.state.chats.map((c) => c.id).toSet(),
        hasLength(h.bloc.state.chats.length),
      );
      expect(h.remote.pages.skip(1).every((p) => p.after != null), true);
      expect(
        h.remote.pages.skip(1).map((p) => p.after!.conversationId).toSet(),
        hasLength(h.remote.pages.length - 1),
      );
      final pages = h.remote.pages.length;
      await _frames(tester, h, 'filled-viewport-idle', turns: 32);
      expect(h.remote.pages, hasLength(pages));
      expect(find.byType(FilledButton), findsNothing);
      await _finish(tester, h, 'short-pages-autofill');
    },
  );
}

void _jumpToEnd(WidgetTester tester) {
  final scroll = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scroll).position;
  position.jumpTo(position.maxScrollExtent);
}

Future<void> _mount(
  WidgetTester tester,
  _Harness h, {
  bool reentry = false,
  bool recordViews = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  // Keep both subscriptions: the recorder observes facts, the real Bloc/UI uses
  // the same shared stream. No second remote data source is constructed.
  if (!reentry) {
    h.subscription = recordViews
        ? h.repository.watchChatList().listen(h.views.add)
        : const Stream<ChatListViewState>.empty().listen((_) {});
  }
  h.bloc = ChatsBloc(chatsRepository: h.repository)
    ..add(const ChatsLoadStarted());
  await tester.pumpWidget(
    RepositoryProvider<IChatsRepository>.value(
      value: h.repository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ChatsBloc>.value(value: h.bloc),
          BlocProvider(
            create: (_) => PresenceCubit(repository: MockPresenceRepository()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChatsPage(),
        ),
      ),
    ),
  );
  _sample(tester, h, 'first-frame');
  addTearDown(() => _dispose(tester, h));
}

Future<void> _frames(
  WidgetTester tester,
  _Harness h,
  String phase, {
  required int turns,
}) async {
  for (var i = 0; i < turns; i++) {
    // Native SQLite uses real async work. This is a deterministic frame probe,
    // not a wall-clock Android/FPS benchmark or pumpAndSettle on an active spinner.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    _sample(tester, h, phase);
  }
}

void _sample(WidgetTester tester, _Harness h, String phase) {
  final list = find.byType(ListView).evaluate().isNotEmpty;
  final spinner = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
  final retry = find.byType(FilledButton).evaluate().isNotEmpty;
  final sample = <String, Object?>{
    'phase': phase,
    'rows': h.bloc.state.chats.length,
    'status': h.bloc.state.status.name,
    'full_spinner': spinner && !list,
    'footer_spinner': spinner && list,
    'retry': retry,
    'cache_loading': h.views.lastOrNull?.isLoadingCache,
    'remote_loading': h.views.lastOrNull?.isLoadingRemote,
    'refreshing': h.views.lastOrNull?.isRefreshing,
    'has_more_cached': h.bloc.state.hasMoreCached,
    'has_more_remote': h.bloc.state.hasMoreRemote,
    'error': h.bloc.state.loadError?.runtimeType.toString(),
    'refresh_error': h.bloc.state.refreshError?.runtimeType.toString(),
  };
  // Store transitions, not every identical frame.
  if (h.frames.isEmpty || jsonEncode(h.frames.last) != jsonEncode(sample)) {
    h.frames.add(sample);
  }
}

Future<void> _finish(
  WidgetTester tester,
  _Harness h,
  String name, {
  Map<String, Object?> extra = const {},
}) async {
  _reports.add({'name': name, ...h.snapshot(), ...extra, 'frames': h.frames});
  expect(h.remote.fullReads, 0);
  expect(h.trace.messageRequests, 0);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await _dispose(tester, h);
}

Future<void> _dispose(WidgetTester tester, _Harness h) async {
  var done = false;
  Object? failure;
  StackTrace? stack;
  unawaited(
    h.dispose().then(
      (_) => done = true,
      onError: (Object error, StackTrace trace) {
        failure = error;
        stack = trace;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 200 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  expect(
    done,
    true,
    reason:
        'All repository subscriptions and native SQLite must close; stage=${h.cleanupStage}',
  );
  await tester.runAsync(h.closeDatabase);
}

Chat _chat(int i) => Chat(
  id: i.toString().padLeft(8, '0'),
  peerId: 'peer-$i',
  userName: 'Peer $i',
  lastMessage: 'preview',
  lastMessageTime: DateTime.utc(2026).add(Duration(seconds: i)),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);

class _Harness {
  _Harness(
    this.db,
    this.media,
    this.account,
    this.cache,
    this.remote,
    this.repository,
    this.trace,
    this.messageClient,
  );
  final AppDatabase db;
  final MediaCacheService media;
  final AccountSessionController account;
  final ChatsCacheDataSource cache;
  final _Remote remote;
  final ChatsRepository repository;
  final _Trace trace;
  final SupabaseClient messageClient;
  late ChatsBloc bloc;
  late StreamSubscription<ChatListViewState> subscription;
  final views = <ChatListViewState>[];
  final frames = <Map<String, Object?>>[];
  String cleanupStage = 'not-started';

  static Future<_Harness> create(
    int count, {
    bool complete = false,
    File? file,
    bool seed = true,
    ChatListSearchPolicy? searchPolicy,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final trace = _Trace();
    final db = AppDatabase.forTesting(
      (file == null ? NativeDatabase.memory() : NativeDatabase(file))
          .interceptWith(trace),
    );
    final account = AccountSessionController(initialUserId: 'owner');
    final media = MediaCacheService(database: db);
    final cache = ChatsCacheDataSource(
      database: db,
      userIdProvider: () => 'owner',
    );
    final remote = _Remote([for (var i = 0; i < count; i++) _chat(i)]);
    if (seed) await cache.replaceAll(remote.rows);
    if (complete) {
      await cache.applyListPage(
        await cache.beginListRefresh(),
        remote.page('', null, 50),
      );
    }
    final config = AppConfig(
      environment: AppEnvironment.prod,
      preferences: await SharedPreferences.getInstance(),
      talker: Talker(settings: TalkerSettings(enabled: false)),
      env: const {},
      database: db,
      accountSessionController: account,
    );
    final messages = ChatCacheDataSource(
      database: db,
      userIdProvider: () => 'owner',
    );
    final messageClient = SupabaseClient(
      'http://localhost',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        trace.messageRequests++;
        throw StateError(
          'Unexpected message-history HTTP while opening the chat list',
        );
      }),
    );
    final messageRemote = ChatRemoteDataSource(client: messageClient);
    final repository = ChatsRepository(
      enableListPagination: true,
      searchPolicy: searchPolicy,
      config: config,
      cache: cache,
      remote: remote,
      mediaCache: media,
      chatCache: messages,
      conversationSync: ConversationSyncService(
        cache: messages,
        remote: messageRemote,
        hydrator: ChatMessageHydrator(
          config: config,
          remote: messageRemote,
          mediaCache: media,
        ),
        chatsCache: cache,
        accountSessionController: account,
      ),
      accountSessionController: account,
    );
    trace.enabled = true;
    return _Harness(
      db,
      media,
      account,
      cache,
      remote,
      repository,
      trace,
      messageClient,
    );
  }

  Map<String, Object?> snapshot() => {
    'page_requests': [
      for (final r in remote.pages)
        {'query': r.query, 'after': r.after?.conversationId},
    ],
    'head_reads': trace.headReads,
    'tail_reads': trace.tailReads,
    'continuation_reads': trace.continuationReads,
    'remote_maximum_concurrent': remote.maximumConcurrent,
    'full_remote_reads': remote.fullReads,
    'metadata_batch_calls': remote.metadataBatches,
    'unread_state_calls': remote.unreadCalls,
    'message_history_http_calls': trace.messageRequests,
    'cache_loading_emissions': views.where((v) => v.isLoadingCache).length,
  };

  Future<void>? _disposal;
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    for (final gate in [trace.headGate, trace.tailGate, remote.hold]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    cleanupStage = 'pause';
    await repository.pauseRealtime();
    cleanupStage = 'bloc';
    await bloc.close();
    cleanupStage = 'recording-subscription';
    await subscription.cancel();
    cleanupStage = 'commits';
    await account.drainCommits();
    cleanupStage = 'remote-stream';
    await remote.changes.close();
    await remote.sdk.dispose();
    await messageClient.dispose();
    media.dispose();
    cleanupStage = 'done';
  }

  Future<void>? _databaseClose;
  Future<void> closeDatabase() => _databaseClose ??= db.close();
}

class _Trace extends QueryInterceptor {
  Object? searchFailure;
  bool enabled = false;
  int headReads = 0, tailReads = 0, continuationReads = 0;
  int messageRequests = 0;
  Completer<void>? headGate, tailGate;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String sql,
    List<Object?> args,
  ) async {
    if (searchFailure != null &&
        sql.contains('FROM cached_chats c') &&
        sql.contains('LIKE')) {
      throw searchFailure!;
    }
    if (enabled &&
        sql.contains('FROM cached_chats c') &&
        sql.contains('LIMIT ?')) {
      final continuation = sql.contains('AND COALESCE');
      final sentinel = args.last == 2;
      if (sentinel) {
        tailReads++;
      } else if (continuation) {
        continuationReads++;
      } else {
        headReads++;
      }
      final gate = sentinel
          ? null
          : continuation
          ? tailGate
          : headGate;
      if (gate != null) await gate.future;
    }
    return executor.runSelect(sql, args);
  }
}

class _Remote extends ChatsRemoteDataSource {
  factory _Remote(List<Chat> rows) {
    late final _Remote remote;
    final sdk = SupabaseClient(
      'http://localhost',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) => remote._reply(request)),
    );
    remote = _Remote._(rows, sdk);
    return remote;
  }
  _Remote._(this.rows, this.sdk)
    : super(
        client: sdk,
        talker: Talker(settings: TalkerSettings(enabled: false)),
      );
  final SupabaseClient sdk;
  @override
  String get currentUserId => 'owner';
  final List<Chat> rows;
  bool offline = false;
  int status = 200;
  int? continuationStatus;
  int? responseLimit;
  bool malformed = false;
  Completer<void>? hold;
  final changes = StreamController<ConversationChange>.broadcast();
  final pages = <({String query, ChatListPageCursor? after})>[];
  int fullReads = 0, active = 0, maximumConcurrent = 0;
  int metadataBatches = 0, unreadCalls = 0;
  @override
  Stream<ConversationChange> watchChanges() => changes.stream;
  @override
  Future<void> pauseChanges() async {}
  @override
  Future<void> resumeChanges() async {}
  // fetchChatListPage is deliberately NOT overridden: production PostgREST
  // serialization and response validation run through the real Supabase SDK.
  Future<http.Response> _reply(http.Request request) async {
    expectSync(request.url.path, '/rest/v1/rpc/get_chat_list_page');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final searchQuery = body['search_query'] as String;
    final after = body['after_activity_at'] == null
        ? null
        : ChatListPageCursor(
            activityAt: DateTime.parse(body['after_activity_at'] as String),
            conversationId: body['after_conversation_id'] as String,
            query: searchQuery,
          );
    final pageSize = body['page_size'] as int;
    pages.add((query: searchQuery, after: after));
    active++;
    maximumConcurrent = active > maximumConcurrent ? active : maximumConcurrent;
    try {
      if (hold != null) await hold!.future;
      if (offline) throw const SocketException('diagnostic offline');
      final responseStatus = after == null
          ? status
          : continuationStatus ?? status;
      if (responseStatus != 200) {
        return http.Response(
          jsonEncode({
            'code': 'PT429',
            'message': 'chat_list_page_rate_limited',
          }),
          responseStatus,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (malformed) {
        return http.Response(
          jsonEncode({
            'items': 'invalid',
            'has_more': false,
            'query': searchQuery,
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      final response = page(searchQuery, after, responseLimit ?? pageSize);
      return http.Response(
        jsonEncode({
          'query': response.query,
          'has_more': response.nextCursor != null,
          'unread_total': response.unreadTotal,
          'next_cursor': response.nextCursor == null
              ? null
              : {
                  'query': response.query,
                  'activity_at': response.nextCursor!.activityAt
                      .toIso8601String(),
                  'conversation_id': response.nextCursor!.conversationId,
                },
          'items': [
            for (final item in response.items)
              {
                'id': item.chat.id,
                'peer_id': item.chat.peerId,
                'peer_display_name': item.chat.userName,
                'last_message_text': item.chat.lastMessage,
                'last_message_sender_id': item.chat.peerId,
                'last_message_at': item.chat.lastMessageTime.toIso8601String(),
                'list_activity_at': item.activityAt.toIso8601String(),
                'unread_count': item.chat.unreadCount,
                'is_muted': item.chat.isMuted,
              },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    } finally {
      active--;
    }
  }

  ChatListPage page(String query, ChatListPageCursor? after, int size) {
    final candidates =
        rows
            .where(
              (c) =>
                  c.userName.toLowerCase().startsWith(query) &&
                  (after == null ||
                      c.lastMessageTime.isBefore(after.activityAt) ||
                      c.lastMessageTime == after.activityAt &&
                          c.id.compareTo(after.conversationId) < 0),
            )
            .toList()
          ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    final selected = candidates.take(size).toList();
    return ChatListPage(
      query: query,
      unreadTotal: 0,
      items: [
        for (final c in selected)
          ChatListPageItem(chat: c, activityAt: c.lastMessageTime),
      ],
      nextCursor: candidates.length <= size
          ? null
          : ChatListPageCursor(
              activityAt: selected.last.lastMessageTime,
              conversationId: selected.last.id,
              query: query,
            ),
    );
  }

  @override
  Future<List<Chat>> fetchChats() async {
    fullReads++;
    throw StateError('Unexpected unbounded legacy request');
  }

  @override
  Future<List<Chat>> fetchChatsByIds(Set<String> ids) async {
    metadataBatches++;
    if (offline) throw const SocketException('diagnostic offline');
    return rows.where((r) => ids.contains(r.id)).toList();
  }

  @override
  Future<ChatUnreadState> fetchUnreadState({
    Set<String> conversationIds = const {},
  }) async {
    unreadCalls++;
    if (offline) throw const SocketException('diagnostic offline');
    return ChatUnreadState(
      chats: rows.where((r) => conversationIds.contains(r.id)).toList(),
      unreadTotal: 0,
    );
  }
}
