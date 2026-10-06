import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/repositories/presence/presence.dart';

class PresenceState extends Equatable {
  const PresenceState({
    this.onlineUserIds = const {},
    this.confirmedOfflineUserIds = const {},
    this.offlineEventUserIds = const {},
  });

  final Set<String> onlineUserIds;
  final Set<String> confirmedOfflineUserIds;
  final Set<String> offlineEventUserIds;

  bool isOnline(String userId) => onlineUserIds.contains(userId);
  bool isConfirmedOffline(String userId) =>
      confirmedOfflineUserIds.contains(userId);
  bool hasNewOfflineEvent(String userId, PresenceState previous) =>
      offlineEventUserIds.contains(userId) &&
      !previous.offlineEventUserIds.contains(userId);

  @override
  List<Object?> get props => [
    onlineUserIds,
    confirmedOfflineUserIds,
    offlineEventUserIds,
  ];
}

class PresenceCubit extends Cubit<PresenceState> {
  PresenceCubit({required IPresenceRepository repository})
    : super(const PresenceState()) {
    if (repository is IPresenceLifecycleRepository) {
      _subscription = (repository as IPresenceLifecycleRepository)
          .watchPresenceSnapshots()
          .listen(
            (snapshot) => emit(
              PresenceState(
                onlineUserIds: snapshot.onlineUserIds,
                confirmedOfflineUserIds: snapshot.confirmedOfflineUserIds,
                offlineEventUserIds: snapshot.offlineEventUserIds,
              ),
            ),
          );
    } else {
      _subscription = repository.watchOnlineUserIds().listen(
        (ids) => emit(
          PresenceState(
            onlineUserIds: ids,
            confirmedOfflineUserIds: state.onlineUserIds.difference(ids),
            offlineEventUserIds: state.onlineUserIds.difference(ids),
          ),
        ),
      );
    }
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
