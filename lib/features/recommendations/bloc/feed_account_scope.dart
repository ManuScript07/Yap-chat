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
  }) {
    _accounts.generationChanges.addListener(_reset);
  }

  final AccountSessionController _accounts;
  final IFeedRepository _repository;
  final IBlocklistRepository? blocks;
  final IProfileFriendsRepository? friends;
  FeedActionsCubit? _actions;
  StreamSubscription<Set<String>>? _blocks;
  StreamSubscription<String>? _profiles;

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
    );
    _blocks = blocks?.watchBlockedUserIds().listen(
      actions.setBlocked,
      onError: (Object _) {},
    );
    _profiles = friends?.watchProfileChanges().listen(
      actions.revalidateAuthor,
      onError: (Object _) {},
    );
    return actions;
  }

  void _reset() {
    unawaited(_blocks?.cancel());
    unawaited(_profiles?.cancel());
    unawaited(_actions?.close());
    _blocks = null;
    _profiles = null;
    _actions = null;
  }

  void dispose() {
    _accounts.generationChanges.removeListener(_reset);
    _reset();
  }
}
