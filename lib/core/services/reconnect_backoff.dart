import 'dart:async';
import 'dart:math' as math;

/// Планирует только одну попытку переподключения и увеличивает задержку
/// между последовательными сбоями.
class ReconnectBackoff {
  ReconnectBackoff({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.onError,
  });

  final Duration initialDelay;
  final Duration maxDelay;
  final void Function(Object error, StackTrace stackTrace)? onError;

  Timer? _timer;
  int _attempt = 0;

  bool get isScheduled => _timer != null;

  Duration? schedule(Future<void> Function() action) {
    if (_timer != null) return null;

    final multiplier = 1 << math.min(_attempt, 10);
    final delayMilliseconds = math.min(
      initialDelay.inMilliseconds * multiplier,
      maxDelay.inMilliseconds,
    );
    final delay = Duration(milliseconds: delayMilliseconds);
    _attempt++;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(
        Future<void>.sync(action).catchError((Object error, StackTrace stack) {
          onError?.call(error, stack);
        }),
      );
    });
    return delay;
  }

  void reset() {
    cancel();
    _attempt = 0;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
