abstract interface class IPresenceRepository {
  Stream<Set<String>> watchOnlineUserIds();

  Future<void> connect(String userId);

  Future<void> disconnect();
}

abstract interface class IPresenceWatchRepository {
  Future<void> setWatchScope(String scopeId, Iterable<String> userIds);

  Future<void> removeWatchScope(String scopeId);
}

extension PresenceWatchRepositoryAccess on IPresenceRepository {
  Future<void> setWatchScope(String scopeId, Iterable<String> userIds) {
    final repository = this;
    return repository is IPresenceWatchRepository
        ? (repository as IPresenceWatchRepository).setWatchScope(
            scopeId,
            userIds,
          )
        : Future.value();
  }

  Future<void> removeWatchScope(String scopeId) {
    final repository = this;
    return repository is IPresenceWatchRepository
        ? (repository as IPresenceWatchRepository).removeWatchScope(scopeId)
        : Future.value();
  }
}
