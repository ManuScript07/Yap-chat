part of 'chats_repository.dart';

extension _ChatsSearch on ChatsRepository {
  Future<void> _retrySearch(String query, int generation) async {
    _searchPolicy.allowProbe();
    await _scheduleSearch(query, generation, immediate: true);
  }

  bool _searchCurrent(
    String query,
    int generation,
    AccountSessionSnapshot scope,
  ) =>
      _listCurrent &&
      _accountSessionController.isCurrent(scope) &&
      query == _activeListQuery &&
      generation == _listGeneration;

  /// Return true when no HTTP is needed/allowed. Local results have their own
  /// SQLite subscription and are never delayed by this decision or its timer.
  Future<bool> _useSearchCache(
    String query,
    int generation,
    AccountSessionSnapshot scope,
  ) async {
    if (!_searchCurrent(query, generation, scope)) return true;
    if (_listError != null) {
      _refreshingList = false;
      _emitList();
      return true;
    }
    if (_searchPolicy.hasCompleteCatalog) {
      _searchTimer?.cancel();
      _searchTimer = null;
      _hasMoreRemote = false;
      _refreshingList = false;
      _listRefreshError = null;
      _emitList();
      return true;
    }
    final cached = await _cache.readListState(
      query: query,
      ownerUserId: scope.userId,
    );
    if (!_searchCurrent(query, generation, scope)) return true;
    // The local subscription can fail while this metadata read is pending.
    if (_listError != null) {
      _refreshingList = false;
      _emitList();
      return true;
    }
    if (cached.hasRemotePage &&
        _searchPolicy.canReuse(query, cached.revision)) {
      _hasMoreRemote = cached.nextCursor != null && _searchPolicy.canRequest;
      _refreshingList = false;
      _listRefreshError = null;
      _emitList();
      return true;
    }
    if (!_searchPolicy.canRequest) {
      _hasMoreRemote = false;
      _refreshingList = false;
      _listRefreshError = _searchPolicy.blockedError;
      _emitList();
      return true;
    }
    return false;
  }

  Future<void> _scheduleSearch(
    String query,
    int generation, {
    bool immediate = false,
  }) async {
    final scope = _listScope!;
    _searchTimer?.cancel();
    _searchTimer = null;
    try {
      if (await _useSearchCache(query, generation, scope)) return;
    } catch (error) {
      if (_searchCurrent(query, generation, scope)) {
        _listError = error;
        _cacheListReady = true;
        _refreshingList = false;
        _emitList();
      }
      return;
    }
    if (!_searchCurrent(query, generation, scope) || _listError != null) return;
    _refreshingList = true;
    _searchTimer = Timer(_searchPolicy.delay(immediate: immediate), () {
      _searchTimer = null;
      if (!_searchCurrent(query, generation, scope) || _isRealtimePaused) {
        return;
      }
      unawaited(
        _requestPage(
          query,
          true,
          generation,
        ).catchError((Object _, StackTrace _) {}),
      );
    });
    _emitList();
  }

  void _recordListReadFailure(Object error) {
    final quota =
        error is PostgrestException &&
        (error.code == 'PT429' || error.code == '42901');
    // Access/validation/quota failures do not imply a disconnected transport.
    final transport =
        error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException;
    _searchPolicy.failed(error, transport: transport, quota: quota);
  }
}
