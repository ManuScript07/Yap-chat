/// Persisted retry policy for the chat outbox.
///
/// The jitter is derived from the stable operation id instead of process-local
/// randomness. Once a retry time is persisted it therefore remains meaningful
/// after an application restart, while independently-created UUIDs still keep
/// concurrent clients from retrying in lockstep.
class PendingMessageRetryPolicy {
  const PendingMessageRetryPolicy._();

  static const maxAutomaticAttempts = 8;
  static const _baseDelay = Duration(seconds: 5);
  static const _maximumDelay = Duration(minutes: 30);
  static const _rateLimitMinimumDelay = Duration(minutes: 1);

  static Duration delayAfterFailure({
    required int attempts,
    required String operationId,
    required bool rateLimited,
  }) {
    assert(attempts > 0);
    final exponent = (attempts - 1).clamp(0, 30);
    final unboundedMilliseconds = _baseDelay.inMilliseconds * (1 << exponent);
    final cappedMilliseconds = unboundedMilliseconds.clamp(
      _baseDelay.inMilliseconds,
      _maximumDelay.inMilliseconds,
    );
    final jitteredMilliseconds = _applyJitter(
      cappedMilliseconds,
      '$operationId:$attempts',
    );
    final delay = Duration(milliseconds: jitteredMilliseconds);
    return rateLimited && delay < _rateLimitMinimumDelay
        ? _rateLimitMinimumDelay
        : delay;
  }

  static int _applyJitter(int milliseconds, String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    // A symmetric ten-percent jitter, in milliseconds.
    final offsetPercent = (hash % 2001) - 1000;
    return milliseconds + (milliseconds * offsetPercent ~/ 10000);
  }
}
