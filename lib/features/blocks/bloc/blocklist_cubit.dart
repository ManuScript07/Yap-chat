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
  }

  final IBlocklistRepository _repository;
  late final StreamSubscription<Set<String>> _subscription;
  late final StreamSubscription<Set<String>> _pendingSubscription;

  Future<void> refresh() async {
    try {
      await _repository.refreshBlockedUsers();
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
