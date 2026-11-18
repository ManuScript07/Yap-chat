import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

void main() {
  late AccountSessionController accounts;
  late FeedActionsCubit cubit;
  late _Repository repository;
  late Duration elapsed;

  setUp(() {
    accounts = AccountSessionController(initialUserId: 'viewer');
    final account = accounts.capture();
    repository = _Repository();
    elapsed = Duration.zero;
    cubit = FeedActionsCubit(
      repository,
      account,
      () => accounts.isCurrent(account),
      elapsed: () => elapsed,
    );
  });
  tearDown(() => cubit.close());

  test('post count is shared and ordered by its server revision', () {
    FeedPost snapshot(int count, [int? revision]) => FeedPost(
      id: 'post',
      authorId: 'author',
      authorName: 'author',
      text: '',
      createdAt: DateTime.utc(2026),
      commentCount: count,
      commentCountRevision: revision,
    );

    final feedCard = snapshot(5);
    final details = snapshot(5, 10);
    cubit.recordProjection(details, cubit.projectionVersion);
    cubit.recordCommentCount(details, (count: 6, revision: 11));
    expect(cubit.commentCountFor(feedCard), 6);
    expect(cubit.commentCountFor(details), 6);

    final afterCreation = cubit.state;
    cubit.recordCommentCount(details, (count: 6, revision: 11));
    cubit.recordProjection(snapshot(5, 10), cubit.projectionVersion);
    expect(cubit.state, same(afterCreation));

    // A newer projection can legitimately lower the number after a deletion.
    cubit.recordProjection(snapshot(4, 13), cubit.projectionVersion);
    cubit.recordCommentCount(details, (count: 7, revision: 12));
    expect(cubit.commentCountFor(feedCard), 4);
    expect(cubit.commentCountFor(details), 4);

    accounts.setAuthenticatedUser('different-account');
    cubit.recordCommentCount(details, (count: 9, revision: 14));
    expect(cubit.state.commentCounts['post'], (count: 4, revision: 13));
  });

  test(
    'two cards share one subscription mutation and its confirmed state',
    () async {
      final first = cubit.toggleFollow(_post('one'));
      await cubit.toggleFollow(_post('two'));
      expect(repository.followCalls, 1);
      expect(cubit.state.busy, {'author:author'});
      repository.follow.complete((
        version: 1,
        following: true,
        canFollow: true,
      ));
      await first;
      expect(cubit.followFor(_post('two'))?.following, isTrue);
      expect(cubit.state.busy, isEmpty);
    },
  );

  test('rapid repeat taps share the in-flight and cooldown limits', () async {
    final post = _post('one');
    await Future.wait([for (var i = 0; i < 25; i++) cubit.act(post)]);
    await Future.wait([for (var i = 0; i < 25; i++) cubit.act(post)]);
    // One user intent, replayed once by the timeout retry.
    expect(repository.actions, hasLength(2));
    expect(repository.actions.map((action) => action.$4).toSet(), hasLength(1));
    expect(cubit.reactionFor(post).liked, isTrue);
    elapsed = const Duration(milliseconds: 350);
    await cubit.act(post);
    expect(repository.actions.last.$2, FeedPostAction.unlike);
    expect(repository.actions.last.$3, 1);
  });

  test('a block discards a delayed follow response', () async {
    final post = _post('one');
    final pending = cubit.toggleFollow(post);
    cubit.peerBlocked(post.authorId);
    repository.follow.complete((version: 1, following: true, canFollow: true));
    await pending;
    expect(cubit.state.follows, isEmpty);
    expect(cubit.state.busy, isEmpty);
  });

  test(
    'reconnect verifies known friends in one batch without erasing rows',
    () async {
      final removed = _locationPost('removed');
      final kept = _locationPost('kept');
      final unknown = _locationPost('unknown');
      final oldVersion = cubit.projectionVersion;
      cubit.recordProjection(removed, oldVersion);
      cubit.recordProjection(kept, oldVersion);
      final result = Completer<Set<String>>();
      var calls = 0;
      final check = cubit.recheckFriendships((authors) {
        calls++;
        expect(authors, {'removed', 'kept'});
        return result.future;
      });
      expect(cubit.coordinatesFor(removed), removed.coordinates);
      cubit.recordProjection(unknown, oldVersion);
      expect(cubit.canShow(unknown), isTrue);
      expect(cubit.coordinatesFor(unknown), isNull);
      result.complete({'kept'});
      await check;
      expect(calls, 1);
      expect(cubit.coordinatesFor(removed), isNull);
      expect(cubit.canShow(removed), isTrue);
      expect(cubit.coordinatesFor(kept), kept.coordinates);
    },
  );

  test(
    'a stale reconnect reply cannot override a later friendship event',
    () async {
      final post = _locationPost('author');
      cubit.recordProjection(post, cubit.projectionVersion);
      final result = Completer<Set<String>>();
      final check = cubit.recheckFriendships((_) => result.future);
      cubit.friendshipRemoved(post.authorId);
      cubit.friendshipAdded(post.authorId);
      expect(cubit.coordinatesFor(post), isNull);
      final freshPost = _locationPost('author');
      cubit.recordProjection(freshPost, cubit.projectionVersion);
      result.complete({});
      await check;
      expect(cubit.coordinatesFor(post), isNull);
      expect(cubit.coordinatesFor(freshPost), freshPost.coordinates);
    },
  );

  test(
    'the account uses one in-flight batch for repeated reconnects',
    () async {
      final friends = _FriendAccess();
      final scope = FeedAccountScope(accounts, repository, friends: friends);
      addTearDown(friends.events.close);
      addTearDown(scope.dispose);
      final actions = scope.actionsFor(accounts.capture())!;
      final post = _locationPost('author');
      actions.recordProjection(post, actions.projectionVersion);
      const reconnect = (
        kind: FriendAccessChangeKind.reconnected,
        peerId: null,
      );
      for (var index = 0; index < 20; index++) {
        friends.events.add(reconnect);
      }
      await Future<void>.delayed(Duration.zero);
      expect(friends.checks, hasLength(1));
      friends.checks.first.complete({});
      await Future<void>.delayed(Duration.zero);
      expect(friends.checks, hasLength(2));
      expect(actions.coordinatesFor(post), post.coordinates);
      friends.checks.last.complete({'author'});
      await Future<void>.delayed(Duration.zero);
      friends.events.add((
        kind: FriendAccessChangeKind.removed,
        peerId: 'author',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(actions.coordinatesFor(post), isNull);
      expect(friends.checks, hasLength(2));
    },
  );

  test('one account scope shares mutation locks across entry points', () async {
    final scope = FeedAccountScope(accounts, repository);
    addTearDown(scope.dispose);
    final account = accounts.capture();
    final card = scope.actionsFor(account)!;
    final details = scope.actionsFor(accounts.capture())!;
    expect(identical(card, details), isTrue);
    final follow = card.toggleFollow(_post('one'));
    await details.toggleFollow(_post('two'));
    expect(repository.followCalls, 1);
    accounts.setAuthenticatedUser('other');
    expect(scope.actionsFor(account), isNull);
    expect(identical(details, scope.actionsFor(accounts.capture())), isFalse);
    repository.follow.complete((version: 1, following: true, canFollow: true));
    await follow;
    expect(details.state.follows, isEmpty);
  });

  test(
    'a timeout retries the same intent with the original version and receipt',
    () async {
      final post = _post('one');
      await cubit.act(post);
      expect(repository.actions, hasLength(2));
      expect(repository.actions[0], repository.actions[1]);
      expect(cubit.reactionFor(post), (version: 1, liked: true, likes: 3));
    },
  );

  test(
    'late account responses do not expose or publish follow state',
    () async {
      final post = _post('one');
      final pending = cubit.toggleFollow(post);
      accounts.setAuthenticatedUser('other');
      repository.follow.complete((
        version: 1,
        following: true,
        canFollow: true,
      ));
      await pending;
      expect(cubit.canShow(post), isFalse);
      expect(cubit.state.follows, isEmpty);
    },
  );

  test(
    'report hides the post while blocking also hides other posts by its author',
    () async {
      final first = _post('one');
      final second = _post('two');
      await cubit.report(first, FeedReportReason.spam);
      expect(cubit.canShow(first), isFalse);
      expect(cubit.canShow(second), isTrue);
      cubit.setBlocked({'author'});
      expect(cubit.canShow(second), isFalse);
      cubit.setBlocked({});
      expect(cubit.canShow(second), isFalse);
      final fresh = _post('three');
      cubit.recordProjection(fresh, cubit.projectionVersion);
      expect(cubit.canShow(fresh), isTrue);
      expect(repository.reportCalls, 1);
    },
  );
}

FeedPost _locationPost(String author) => FeedPost(
  id: author,
  authorId: author,
  authorName: author,
  text: 'text',
  createdAt: DateTime.utc(2026),
  coordinates: (latitude: 1, longitude: 1),
  nearby: true,
);

class _FriendAccess implements IFriendAccessRepository {
  final events = StreamController<FriendAccessChange>.broadcast();
  final checks = <Completer<Set<String>>>[];

  @override
  Stream<FriendAccessChange> watchFriendAccessChanges() => events.stream;

  @override
  Future<Set<String>> verifyCurrentFriends(Set<String> peerIds) {
    final request = Completer<Set<String>>();
    checks.add(request);
    return request.future;
  }
}

FeedPost _post(String id) => FeedPost(
  id: id,
  authorId: 'author',
  authorName: 'author',
  text: 'text',
  createdAt: DateTime.utc(2026),
  follow: (version: 0, following: false, canFollow: true),
  reaction: (version: 0, liked: false, likes: 2),
  delivery: (id: id, expiresAt: DateTime.now().add(const Duration(minutes: 3))),
);

class _Repository extends MockFeedRepository implements IFeedPostRepository {
  final follow = Completer<FeedFollowState>();
  final actions = <(FeedDelivery, FeedPostAction, int, String)>[];
  int followCalls = 0;
  int reportCalls = 0;

  @override
  Future<FeedFollowState> setFollow(
    String authorId,
    FeedFollowState current,
    String requestId,
    AccountSessionSnapshot account,
  ) {
    followCalls++;
    return follow.future;
  }

  @override
  Future<({int version, bool liked})> act(
    FeedDelivery delivery,
    FeedPostAction action,
    int version,
    String requestId,
    AccountSessionSnapshot account,
  ) async {
    actions.add((delivery, action, version, requestId));
    if (actions.length == 1) throw TimeoutException('test');
    return (version: 1, liked: true);
  }

  @override
  Future<void> report(
    String id,
    FeedReportReason reason,
    String requestId,
    AccountSessionSnapshot account,
  ) async {
    reportCalls++;
  }

  @override
  Future<FeedFollowState> getFollow(
    String authorId,
    AccountSessionSnapshot account,
  ) => throw UnimplementedError();

  @override
  Future<FeedPost?> getPost(String id, AccountSessionSnapshot account) =>
      throw UnimplementedError();

  @override
  Future<void> repost(
    String id,
    String requestId,
    AccountSessionSnapshot account,
  ) => throw UnimplementedError();
}
