import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

void main() {
  late _Feed feed;
  late AccountSessionController accounts;
  late FeedCubit timeline;
  late DateTime now;

  setUp(() {
    feed = _Feed();
    accounts = AccountSessionController(initialUserId: 'viewer');
    final account = accounts.capture();
    now = DateTime.utc(2026, 11, 13);
    timeline = FeedCubit(
      tab: FeedTab.forYou,
      repository: feed,
      account: account,
      isCurrentAccount: () => accounts.isCurrent(account),
      now: () => now,
    );
  });
  tearDown(() => timeline.close());

  List<String> ids() => [
    for (var i = 0; i < timeline.state.rows.posts.length; i++)
      timeline.state.rows.posts[i].id,
  ];

  test('follows empty continuations and includes unique final items', () async {
    feed.respond(null, _page(['a'], next: '1'));
    feed.respond('1', _page([], next: '2'));
    feed.respond('2', _page(['a', 'b', 'b']));
    await timeline.activate(atTop: true);
    timeline.toggleExpanded('a');
    final first = timeline.loadMore();
    expect(timeline.loadMore(), same(first));
    await first;
    expect(feed.calls, [null, '1', '2']);
    expect(ids(), ['a', 'b']);
    expect(timeline.state.expandedIds, {'a'});
    expect(timeline.state.canContinue, isFalse);
  });

  test('bounds empty scans and stops cursor cycles', () async {
    feed.respond(null, _page([], next: '1'));
    feed.respond('1', _page([], next: '2'));
    feed.respond('2', _page([], next: '3'));
    feed.respond('3', _page([], next: '1'));
    await timeline.activate(atTop: true);
    expect(feed.calls, [null, '1', '2']);
    expect(timeline.state.canContinue, isTrue);
    await timeline.loadMore();
    expect(feed.calls, [null, '1', '2', '3']);
    expect(timeline.state.canContinue, isFalse);
  });

  test(
    'refresh supersedes a late append and preserves existing rows until success',
    () async {
      final tail = Completer<FeedPageResult>();
      final head = Completer<FeedPageResult>();
      feed.respond(null, _page(['a'], next: '1'));
      feed.responses['1'] = () => tail.future;
      await timeline.activate(atTop: true);
      final append = timeline.loadMore();
      await Future<void>.value();
      feed.responses[null] = () => head.future;
      final refresh = timeline.refresh(force: true);
      expect(ids(), ['a']);
      tail.complete(_page(['late']));
      await append;
      expect(ids(), ['a']);
      head.complete(_page(['new']));
      await refresh;
      expect(ids(), ['new']);
    },
  );

  test(
    'reopens expired sessions without moving the displayed anchor',
    () async {
      feed.respond(null, _page(['a', 'b'], next: 'old', expiresAt: now));
      await timeline.activate(atTop: true);
      feed.respond(null, _page(['b', 'c']));
      await timeline.loadMore();
      expect(feed.calls, [null, null]);
      expect(ids(), ['a', 'b', 'c']);
    },
  );

  test(
    'clears rows invalidated by server access changes before reloading',
    () async {
      feed.respond(null, _page(['a'], next: '1'));
      await timeline.activate(atTop: true);
      final head = Completer<FeedPageResult>();
      feed.responses['1'] = () async => throw FeedFailure.sessionInvalidated;
      feed.responses[null] = () => head.future;
      final load = timeline.loadMore();
      await Future<void>.delayed(Duration.zero);
      expect(ids(), isEmpty);
      head.complete(_page(['b']));
      await load;
      expect(ids(), ['b']);
    },
  );

  test(
    'inactive and stale accounts cannot start or commit a continuation',
    () async {
      final head = Completer<FeedPageResult>();
      feed.responses[null] = () => head.future;
      await timeline.refresh();
      expect(feed.calls, isEmpty);
      final load = timeline.activate(atTop: true);
      await Future<void>.value();
      accounts.setAuthenticatedUser('other');
      head.complete(_page(['private'], next: '1'));
      await load;
      expect(ids(), isEmpty);
      expect(feed.calls, [null]);
    },
  );

  test('append error keeps rows and retry uses the same cursor', () async {
    feed.respond(null, _page(['a'], next: '1'));
    feed.responses['1'] = () async => throw TimeoutException('test');
    await timeline.activate(atTop: true);
    await timeline.loadMore();
    expect(ids(), ['a']);
    expect(timeline.state.failure, isA<TimeoutException>());
    await timeline.loadMore();
    expect(feed.calls, [null, '1']);
    feed.respond('1', _page(['b']));
    await timeline.loadMore(retry: true);
    expect(feed.calls, [null, '1', '1']);
    expect(ids(), ['a', 'b']);
  });

  test(
    'retry after a failed refresh reloads the head with existing rows visible',
    () async {
      feed.respond(null, _page(['a'], next: '1'));
      await timeline.activate(atTop: true);
      feed.responses[null] = () async => throw TimeoutException('test');
      await timeline.refresh(force: true);
      expect(ids(), ['a']);
      feed.respond(null, _page(['b']));
      await timeline.retry();
      expect(feed.calls, [null, null, null]);
      expect(ids(), ['b']);
    },
  );

  test('blocked authors are filtered from current and future rows', () async {
    feed.respond(null, _page(['a', 'b'], next: '1'));
    feed.respond('1', _page(['a', 'c']));
    await timeline.activate(atTop: true);
    timeline.updateBlockedAuthors({'a'});
    expect(ids(), ['b']);
    await timeline.loadMore();
    expect(ids(), ['b', 'c']);
  });

  test(
    'loading and expanding reuse the rows, and append publishes a snapshot',
    () async {
      final tail = Completer<FeedPageResult>();
      feed.respond(null, _page(['a'], next: '1'));
      feed.responses['1'] = () => tail.future;
      await timeline.activate(atTop: true);
      final head = timeline.state;
      timeline.toggleExpanded('a');
      final expanded = timeline.state;
      final append = timeline.loadMore();
      expect(timeline.state.loading, isTrue);
      expect(timeline.state.rows, same(head.rows));
      expect(head.expandedIds, isEmpty);
      tail.complete(_page(['b']));
      await append;
      expect(ids(), ['a', 'b']);
      expect(head.rows.posts.single.id, 'a');
      expect(timeline.state.expandedIds, same(expanded.expandedIds));
    },
  );

  test('closing the cubit drops pending responses', () async {
    final head = Completer<FeedPageResult>();
    feed.responses[null] = () => head.future;
    final load = timeline.activate(atTop: true);
    await Future<void>.value();
    final state = timeline.state;
    await timeline.close();
    head.complete(_page(['late']));
    await load;
    expect(timeline.state, same(state));
  });
}

FeedPageResult _page(List<String> ids, {String? next, DateTime? expiresAt}) =>
    FeedPageResult(
      posts: [
        for (final id in ids)
          FeedPost(
            id: id,
            authorId: id,
            authorName: id,
            text: id,
            createdAt: DateTime.utc(2026),
          ),
      ],
      expiresAt: expiresAt,
      nextCursor: next == null
          ? null
          : (sessionId: 'session', token: next, position: null),
    );

class _Feed implements IFeedRepository {
  final calls = <String?>[];
  final responses = <String?, Future<FeedPageResult> Function()>{};

  void respond(String? token, FeedPageResult page) {
    responses[token] = () async => page;
  }

  @override
  Future<FeedPageResult> fetch(
    FeedTab tab, {
    required AccountSessionSnapshot account,
    FeedCursor? cursor,
  }) {
    calls.add(cursor?.token);
    return responses[cursor?.token]!();
  }

  @override
  Future<Uint8List> downloadThumbnail(
    FeedPhoto photo, {
    required AccountSessionSnapshot account,
    required bool Function() stillNeeded,
  }) async => throw UnimplementedError();
}
