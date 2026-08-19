import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/repositories/presence/presence.dart';

class PresenceState extends Equatable {
  const PresenceState({this.onlineUserIds = const {}});

  final Set<String> onlineUserIds;

  bool isOnline(String userId) => onlineUserIds.contains(userId);

  @override
  List<Object?> get props => [onlineUserIds];
}

class PresenceCubit extends Cubit<PresenceState> {
  PresenceCubit({required IPresenceRepository repository})
    : _repository = repository,
      super(const PresenceState()) {
    _subscription = _repository.watchOnlineUserIds().listen(
      (ids) => emit(PresenceState(onlineUserIds: ids)),
    );
  }

  final IPresenceRepository _repository;
  late final StreamSubscription<Set<String>> _subscription;

  Future<void> connect(String userId) => _repository.connect(userId);

  Future<void> disconnect() => _repository.disconnect();

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _repository.disconnect();
    return super.close();
  }
}
