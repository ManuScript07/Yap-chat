import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// Short-lived decoded frames for a small set of already cached local files.
/// No resolver/network requests, cache scans or permanent image retention.
class LocalAvatarFrames {
  LocalAvatarFrames._();

  final _loads = <_LocalAvatarFrame>[];
  bool _disposed = false;

  static Future<LocalAvatarFrames> prepare(
    BuildContext context,
    Iterable<String> paths, {
    required bool Function() isCurrent,
    double size = 56,
    int limit = 12,
    Duration budget = const Duration(milliseconds: 120),
  }) async {
    final lease = LocalAvatarFrames._();
    final configuration = createLocalImageConfiguration(context);
    final width = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    final remaining = paths.toSet().take(limit).iterator;
    var stopped = false;
    bool active() => !stopped && !lease._disposed && isCurrent();
    Future<void> worker() async {
      while (active() && remaining.moveNext()) {
        final file = File(remaining.current);
        try {
          if (!await file.exists() || !active()) continue;
          final load = _LocalAvatarFrame(
            ResizeImage.resizeIfNeeded(width, null, FileImage(file)),
            configuration,
          );
          lease._loads.add(load);
          await load.ready;
        } catch (_) {
          // Evicted or corrupt files retain the normal lazy avatar fallback.
        }
      }
    }

    try {
      await Future.wait([worker(), worker()]).timeout(budget);
    } catch (_) {
      // Preparing presentation must not block offline/search recovery.
    } finally {
      stopped = true;
    }
    return lease;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final load in _loads) {
      load.close();
    }
    _loads.clear();
  }
}

class _LocalAvatarFrame {
  _LocalAvatarFrame(ImageProvider provider, ImageConfiguration configuration) {
    _stream = provider.resolve(configuration);
    _listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        if (!_ready.isCompleted) _ready.complete();
      },
      onError: (_, _) {
        close();
      },
    );
    _stream.addListener(_listener);
  }

  final _ready = Completer<void>();
  late final ImageStream _stream;
  late final ImageStreamListener _listener;
  bool _closed = false;
  Future<void> get ready => _ready.future;

  void close() {
    if (_closed) return;
    _closed = true;
    _stream.removeListener(_listener);
    if (!_ready.isCompleted) _ready.complete();
  }
}
