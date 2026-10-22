/// Only scalar metadata, not decoded images or a second file cache. Media paths
/// are immutable; bounded retention also covers remounts of historical windows.
class ChatMediaAspectRatioCache {
  ChatMediaAspectRatioCache({this.capacity = 512}) : assert(capacity > 0);

  final int capacity;
  final _ratios = <String, double>{};

  double? lookup(String path) {
    final ratio = _ratios.remove(path);
    if (ratio != null) _ratios[path] = ratio;
    return ratio;
  }

  void remember(String path, double ratio) {
    if (!ratio.isFinite || ratio <= 0) return;
    _ratios.remove(path);
    _ratios[path] = ratio;
    while (_ratios.length > capacity) {
      _ratios.remove(_ratios.keys.first);
    }
  }

  void clear() => _ratios.clear();
}

final chatMediaAspectRatios = ChatMediaAspectRatioCache();
