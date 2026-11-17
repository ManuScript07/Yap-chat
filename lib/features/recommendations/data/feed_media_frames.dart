import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yap_chat/repositories/feed/feed.dart';

/// Holds an owned reference to each frame. Callers own the clones they read.
class FeedMediaFrames {
  FeedMediaFrames({required this.maxBytes, this.maxFrames = 64});

  final int maxBytes;
  final int maxFrames;
  final _frames = <(String, String, int), (FeedPost, ui.Image)>{};
  int _bytes = 0;

  ui.Image? find(FeedPost post, String path, int size) {
    final key = (post.id, path, size);
    final entry = _frames.remove(key);
    if (entry == null) return null;
    _frames[key] = (post, entry.$2);
    return entry.$2.clone();
  }

  ui.Image? findPreview(FeedPost post, String path) {
    int? size;
    for (final (postId, storagePath, decodeSize) in _frames.keys) {
      if (postId == post.id && storagePath == path) size = decodeSize;
    }
    return size == null ? null : find(post, path, size);
  }

  void store(FeedPost post, String path, int size, ui.Image image) {
    final bytes = _weight(image);
    if (bytes > maxBytes) return;
    final key = (post.id, path, size);
    _remove(key);
    _frames[key] = (post, image.clone());
    _bytes += bytes;
    while (_bytes > maxBytes || _frames.length > maxFrames) {
      _remove(_frames.keys.first);
    }
  }

  void removeUnavailable(bool Function(FeedPost) allowed) {
    final keys = [
      for (final entry in _frames.entries)
        if (!allowed(entry.value.$1)) entry.key,
    ];
    for (final key in keys) {
      _remove(key);
    }
  }

  void clear() {
    for (final entry in _frames.values) {
      entry.$2.dispose();
    }
    _frames.clear();
    _bytes = 0;
  }

  void _remove((String, String, int) key) {
    final entry = _frames.remove(key);
    if (entry == null) return;
    _bytes -= _weight(entry.$2);
    entry.$2.dispose();
  }

  static int _weight(ui.Image image) => image.width * image.height * 4;
}

Future<ui.Image> decodeFeedFrame(Uint8List bytes, int maxSide) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final scale = math.min(
        1.0,
        maxSide / math.max(descriptor.width, descriptor.height),
      );
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
