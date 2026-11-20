import 'dart:async';

import 'package:yap_chat/core/services/services.dart';
import 'package:yap_chat/repositories/repositories.dart';

import 'feed_actions_cubit.dart';

/// Shares mutation locks and server versions across every feed entry point.
class FeedAccountScope {
  FeedAccountScope(
    this._accounts,
    this._repository, {
    this.blocks,
    this.friends,
    this.postSnapshots,
    this.outbox,
  }) {
    _accounts.generationChanges.addListener(_reset);
  }

  final AccountSessionController _accounts;
  final IFeedRepository _repository;
  final IBlocklistRepository? blocks;
  final IFriendAccessRepository? friends;
  final FeedPostSnapshotStore? postSnapshots;
  final FeedCommentOutbox? outbox;
  FeedActionsCubit? _actions;
  StreamSubscription<Set<String>>? _blocks;
  StreamSubscription<FriendAccessChange>? _friendAccess;
  StreamSubscription<FeedCommentDelivery>? _deliveries;

  FeedActionsCubit? actionsFor(AccountSessionSnapshot account) {
    final repository = _repository;
    if (!_accounts.isCurrent(account) || repository is! IFeedPostRepository) {
      return null;
    }
    if (_actions case final actions?) return actions;
    final actions = _actions = FeedActionsCubit(
      repository as IFeedPostRepository,
      account,
      () => _accounts.isCurrent(account),
      postSnapshots: postSnapshots,
      outbox: outbox,
    );
    _deliveries = outbox?.deliveries.listen((delivery) {
      if (!_accounts.isCurrent(account) ||
          delivery.account.generation != account.generation ||
          delivery.account.userId != account.userId) {
        return;
      }
      if (delivery.failure == FeedCommentFailure.postUnavailable) {
        actions.hidePost(delivery.postId);
      }
      if (delivery.receipt?.postCount case final count?) {
        actions.recordDeliveredCommentCount(delivery.postId, count);
      }
    });
    _blocks = blocks?.watchBlockedUserIds().listen(
      actions.setBlocked,
      onError: (Object _) {},
    );
    if (friends case final access?) {
      if (repository is FeedRepository) {
        unawaited(actions.recheckFriendships(access.verifyCurrentFriends));
      }
      _friendAccess = access.watchFriendAccessChanges().listen((change) {
        switch (change) {
          case (kind: FriendAccessChangeKind.removed, peerId: final String id):
            actions.friendshipRemoved(id);
          case (kind: FriendAccessChangeKind.added, peerId: final String id):
            actions.friendshipAdded(id);
          case (kind: FriendAccessChangeKind.blocked, peerId: final String id):
            actions.peerBlocked(id);
          case (kind: FriendAccessChangeKind.reconnected, peerId: _):
            unawaited(actions.recheckFriendships(access.verifyCurrentFriends));
          default:
            break;
        }
      });
    }
    return actions;
  }

  void _reset() {
    unawaited(_blocks?.cancel());
    unawaited(_friendAccess?.cancel());
    unawaited(_deliveries?.cancel());
    unawaited(_actions?.close());
    _blocks = null;
    _friendAccess = null;
    _deliveries = null;
    _actions = null;
  }

  void dispose() {
    _accounts.generationChanges.removeListener(_reset);
    _reset();
  }
}
