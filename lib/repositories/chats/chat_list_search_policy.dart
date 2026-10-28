/// Bounded, session-local evidence. Persisted/offline coverage alone never
/// proves that a server catalog or a previous search is still complete/fresh.
class ChatListSearchPolicy {
  ChatListSearchPolicy({int Function()? elapsedMicros})
    : _elapsed = elapsedMicros ?? _clock();

  static const debounce = Duration(milliseconds: 350);
  static const minimumInterval = Duration(seconds: 1);
  static const freshness = Duration(seconds: 30);
  static const maximumQueries = 8;
  final int Function() _elapsed;
  final _queries = <String, ({String revision, int at})>{};
  int _version = 0;
  int? _completeAt, _lastSearchAt;
  int _blockedUntil = 0;
  int _quotaUntil = 0;
  bool _offline = false;
  Object? _error;

  static int Function() _clock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsedMicroseconds;
  }

  int get version => _version;
  bool _fresh(int at) => _elapsed() - at < freshness.inMicroseconds;
  bool get hasCompleteCatalog => _completeAt != null && _fresh(_completeAt!);
  bool get canRequest => !_offline && _elapsed() >= _blockedUntil;
  Object? get blockedError => canRequest ? null : _error;
  int get retainedQueries => _queries.length;

  Duration delay({bool immediate = false}) {
    final remaining = _lastSearchAt == null
        ? 0
        : minimumInterval.inMicroseconds - (_elapsed() - _lastSearchAt!);
    final minimum = immediate ? 0 : debounce.inMicroseconds;
    return Duration(microseconds: remaining > minimum ? remaining : minimum);
  }

  void started() => _lastSearchAt = _elapsed();

  void invalidate() {
    _version++;
    _completeAt = null;
    _queries.clear();
  }

  void reset() {
    invalidate();
    _lastSearchAt = null;
    _offline = false;
    _blockedUntil = 0;
    _quotaUntil = 0;
    _error = null;
  }

  /// A deliberate retry/reconnect may probe the network once. It cannot bypass
  /// a known server quota cooldown.
  void allowProbe() => _offline = false;

  void connected() {
    _offline = false;
    _blockedUntil = _quotaUntil;
  }

  void confirmHead(int ticket, {required bool complete}) {
    connected();
    if (ticket != _version) return;
    _completeAt = complete ? _elapsed() : null;
  }

  bool canReuse(String query, String? revision) {
    final value = _queries[query];
    if (value == null || value.revision != revision || !_fresh(value.at)) {
      _queries.remove(query);
      return false;
    }
    _queries.remove(query);
    _queries[query] = value;
    return true;
  }

  void remember(String query, String revision, int ticket) {
    connected();
    if (ticket != _version) return;
    _queries.remove(query);
    _queries[query] = (revision: revision, at: _elapsed());
    while (_queries.length > maximumQueries) {
      _queries.remove(_queries.keys.first);
    }
  }

  void failed(Object error, {required bool transport, required bool quota}) {
    _error = error;
    if (transport) {
      _offline = true;
      invalidate();
    }
    final until = _elapsed() + Duration(seconds: quota ? 60 : 2).inMicroseconds;
    if (quota && until > _quotaUntil) _quotaUntil = until;
    if (until > _blockedUntil) _blockedUntil = until;
  }
}
