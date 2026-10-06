/// Unknown (e.g. a lost local connection) is not a confirmed peer logout.
class PresenceSnapshot {
  const PresenceSnapshot({
    this.onlineUserIds = const {},
    this.confirmedOfflineUserIds = const {},
    this.offlineEventUserIds = const {},
  });

  final Set<String> onlineUserIds;
  final Set<String> confirmedOfflineUserIds;

  /// Only an actual event may be treated as a logout happening now. An RPC
  /// snapshot proves offline, but says nothing about when the peer left.
  final Set<String> offlineEventUserIds;
}
