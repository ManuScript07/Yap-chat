import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/repositories/blocks/blocks.dart';

class BlocklistState extends Equatable {
  const BlocklistState({
    this.blockedUserIds = const {},
    this.pendingUserIds = const {},
    this.isLoaded = false,
  });

  final Set<String> blockedUserIds;
  final Set<String> pendingUserIds;
  final bool isLoaded;

  bool blocks(String userId) => blockedUserIds.contains(userId);
  bool isPending(String userId) => pendingUserIds.contains(userId);

  @override
  List<Object?> get props => [blockedUserIds, pendingUserIds, isLoaded];
}

class BlocklistCubit extends Cubit<BlocklistState> {
  BlocklistCubit({required IBlocklistRepository repository})
    : _repository = repository,
      super(const BlocklistState()) {
    _subscription = repository.watchBlockedUserIds().listen(
      (ids) => emit(
        BlocklistState(
          blockedUserIds: ids,
          pendingUserIds: state.pendingUserIds,
          // A locally added entry is authoritative for the current session,
          // even if the first background refresh has not finished yet.
          isLoaded: state.isLoaded || ids.isNotEmpty,
        ),
      ),
    );
    _pendingSubscription = repository.watchPendingUserIds().listen(
      (ids) => emit(
        BlocklistState(
          blockedUserIds: state.blockedUserIds,
          pendingUserIds: ids,
          isLoaded: state.isLoaded,
        ),
      ),
    );
    // The account controller is restored before providers are built. Starting
    // here makes a persisted Supabase session hydrate its blacklist even if a
    // UI AuthBloc listener attaches after the initial authenticated state.
    unawaited(hydrateAndRefresh());
  }

  final IBlocklistRepository _repository;
  late final StreamSubscription<Set<String>> _subscription;
  late final StreamSubscription<Set<String>> _pendingSubscription;
  Future<void>? _refreshOperation;
  Future<void>? _hydrateOperation;
  DateTime? _lastSuccessfulRefreshAt;

  Future<void> hydrateAndRefresh() async {
    await hydrate();
    await refreshIfStale();
  }

  Future<void> hydrate() =>
      _hydrateOperation ??= _hydrateInternal().whenComplete(
        () => _hydrateOperation = null,
      );

  Future<void> _hydrateInternal() async {
    try {
      final snapshot = await _repository.readCachedBlockedUsers();
      _lastSuccessfulRefreshAt = snapshot?.cachedAt;
      if (!isClosed) {
        emit(
          BlocklistState(
            blockedUserIds: snapshot == null
                ? state.blockedUserIds
                : snapshot.users.map((user) => user.id).toSet(),
            pendingUserIds: state.pendingUserIds,
            isLoaded: state.isLoaded || snapshot != null,
          ),
        );
      }
    } catch (_) {
      // A missing or unreadable SQLite cache must not block authentication.
      if (!isClosed) {
        emit(
          BlocklistState(
            blockedUserIds: state.blockedUserIds,
            pendingUserIds: state.pendingUserIds,
            isLoaded: false,
          ),
        );
      }
    }
  }

  Future<void> refreshIfStale({
    Duration maxAge = const Duration(minutes: 5),
  }) {
    final lastRefresh = _lastSuccessfulRefreshAt;
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < maxAge) {
      return Future<void>.value();
    }
    return refresh();
  }

  Future<void> refresh() =>
      _refreshOperation ??= _refreshInternal().whenComplete(
        () => _refreshOperation = null,
      );

  Future<void> _refreshInternal() async {
    try {
      await _repository.refreshBlockedUsers();
      _lastSuccessfulRefreshAt = DateTime.now();
      if (!isClosed) {
        emit(
          BlocklistState(
            blockedUserIds: state.blockedUserIds,
            pendingUserIds: state.pendingUserIds,
            isLoaded: true,
          ),
        );
      }
    } catch (_) {
      // Cached values are still usable while the network is unavailable.
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _pendingSubscription.cancel();
    return super.close();
  }
}
