import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

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

  test(
    'relationship invalidation discards a delayed follow response',
    () async {
      final post = _post('one');
      final pending = cubit.toggleFollow(post);
      cubit.revalidateAuthor(post.authorId);
      repository.follow.complete((
        version: 1,
        following: true,
        canFollow: true,
      ));
      await pending;
      expect(cubit.state.follows, isEmpty);
      expect(cubit.state.busy, isEmpty);
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
      expect(repository.reportCalls, 1);
    },
  );
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
