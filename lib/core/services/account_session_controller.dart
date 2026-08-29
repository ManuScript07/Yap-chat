import 'dart:async';

/// Immutable identity of an authenticated account at the moment an operation
/// starts. The generation also changes when the same account signs out and in
/// again, so work from the previous session cannot commit into the new one.
class AccountSessionSnapshot {
  const AccountSessionSnapshot({
    required this.userId,
    required this.generation,
  });

  final String userId;
  final int generation;
}

class StaleAccountSessionException implements Exception {
  const StaleAccountSessionException();
}

/// Owns the process-wide account boundary for repository work.
///
/// Remote work may continue after a session switch, but every account-scoped
/// local commit must pass through [commit]. Changing the account invalidates
/// queued commits immediately. [drainCommits] lets logout wait for a commit
/// that was already running before deleting that account's local data.
class AccountSessionController {
  AccountSessionController({String? initialUserId})
    : _userId = _normalize(initialUserId);

  String? _userId;
  int _generation = 0;
  Future<void> _commitQueue = Future<void>.value();

  String? get userId => _userId;

  void setAuthenticatedUser(String? userId) {
    final normalized = _normalize(userId);
    if (_userId == normalized) return;
    _userId = normalized;
    _generation++;
  }

  AccountSessionSnapshot capture() {
    final currentUserId = _userId;
    if (currentUserId == null) throw const StaleAccountSessionException();
    return AccountSessionSnapshot(
      userId: currentUserId,
      generation: _generation,
    );
  }

  bool isCurrent(AccountSessionSnapshot snapshot) =>
      _userId == snapshot.userId && _generation == snapshot.generation;

  void ensureCurrent(AccountSessionSnapshot snapshot) {
    if (!isCurrent(snapshot)) throw const StaleAccountSessionException();
  }

  Future<T> commit<T>(
    AccountSessionSnapshot snapshot,
    Future<T> Function() operation,
  ) {
    final completer = Completer<T>();
    final queued = _commitQueue.then(
      (_) async {
        ensureCurrent(snapshot);
        completer.complete(await operation());
      },
      onError: (_) async {
        ensureCurrent(snapshot);
        completer.complete(await operation());
      },
    );
    _commitQueue = queued.catchError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });
    return completer.future;
  }

  Future<void> drainCommits() => _commitQueue.catchError((_) {});

  static String? _normalize(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
