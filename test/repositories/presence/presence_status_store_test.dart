import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/repositories/presence/presence_snapshot.dart';
import 'package:yap_chat/repositories/presence/presence_status_store.dart';

void main() {
  test(
    'new realtime observations dominate old RPC snapshots in both directions',
    () async {
      final store = PresenceStatusStore();
      var ticket = store.captureSnapshot();
      store.record('peer', isOnline: true);
      store.applySnapshot(ticket, {'peer': false, 'other': true});
      expect(store.onlineUserIds, {'peer', 'other'});
      ticket = store.captureSnapshot();
      store.record('peer', isOnline: false);
      store.applySnapshot(ticket, {'peer': true});
      expect(store.onlineUserIds, {'other'});
      expect((await store.watchSnapshots().first).confirmedOfflineUserIds, {
        'peer',
      });
      await store.dispose();
    },
  );

  test('unchanged events also invalidate older snapshots', () async {
    final store = PresenceStatusStore();
    store.record('peer', isOnline: true);
    final ticket = store.captureSnapshot();
    store.record('peer', isOnline: true);
    store.applySnapshot(ticket, {'peer': false});
    expect(store.onlineUserIds, {'peer'});
    await store.dispose();
  });

  test('newer RPC wins regardless of response order', () async {
    final store = PresenceStatusStore();
    final first = store.captureSnapshot();
    final second = store.captureSnapshot();
    store.applySnapshot(second, {'peer': false});
    store.applySnapshot(first, {'peer': true});
    expect(store.onlineUserIds, isEmpty);
    final third = store.captureSnapshot();
    store.applySnapshot(third, {'peer': true});
    expect(store.onlineUserIds, {'peer'});
    await store.dispose();
  });

  test(
    'clear rejects old-account responses and is not a peer logout',
    () async {
      final store = PresenceStatusStore();
      store.record('peer', isOnline: true);
      final ticket = store.captureSnapshot();
      store.clear();
      store.applySnapshot(ticket, {'peer': true});
      final snapshot = await store.watchSnapshots().first;
      expect(snapshot.onlineUserIds, isEmpty);
      expect(snapshot.confirmedOfflineUserIds, isEmpty);
      await store.dispose();
    },
  );

  test('suspension preserves peers but rejects pending responses', () async {
    final store = PresenceStatusStore();
    store.record('peer', isOnline: true);
    final ticket = store.captureSnapshot();
    store.suspend();
    store.applySnapshot(ticket, {'peer': false});
    expect(store.onlineUserIds, {'peer'});
    await store.dispose();
  });

  test(
    'recovery expiry only forgets unrefreshed online, without false last-seen',
    () {
      fakeAsync((clock) {
        final store = PresenceStatusStore();
        final snapshots = <PresenceSnapshot>[];
        final subscription = store.watchSnapshots().listen(snapshots.add);
        store.recordAll({'stale': true, 'fresh': true, 'offline': false});
        store.beginRevalidation(const Duration(seconds: 16));
        clock.elapse(const Duration(seconds: 8));
        store.record('fresh', isOnline: true);
        clock.elapse(const Duration(seconds: 8));
        clock.flushMicrotasks();
        final snapshot = snapshots.last;
        expect(snapshot.onlineUserIds, {'fresh'});
        expect(snapshot.confirmedOfflineUserIds, {'offline'});
        unawaited(subscription.cancel());
        unawaited(store.dispose());
        clock.flushMicrotasks();
      });
    },
  );

  test('initial subscription cannot miss a same-turn change', () async {
    final store = PresenceStatusStore();
    final events = <Set<String>>[];
    final subscription = store.watch().listen(events.add);
    store.record('peer', isOnline: true);
    await Future<void>.delayed(Duration.zero);
    expect(events.last, {'peer'});
    await subscription.cancel();
    await store.dispose();
  });

  test(
    'a new connection loss covers peers refreshed during previous recovery',
    () {
      fakeAsync((clock) {
        final store = PresenceStatusStore();
        store.record('peer', isOnline: true);
        store.beginRevalidation(const Duration(seconds: 16));
        clock.elapse(const Duration(seconds: 8));
        store.applySnapshot(store.captureSnapshot(), {'peer': true});
        store.beginRevalidation(const Duration(seconds: 16), restart: false);
        clock.elapse(const Duration(seconds: 8));
        expect(store.onlineUserIds, isEmpty);
        unawaited(store.dispose());
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'offline snapshots do not manufacture an offline event timestamp',
    () async {
      final store = PresenceStatusStore();
      store.record('peer', isOnline: true);
      store.suspend();
      store.applySnapshot(store.captureSnapshot(), {'peer': false});
      final snapshot = await store.watchSnapshots().first;
      expect(snapshot.confirmedOfflineUserIds, {'peer'});
      expect(snapshot.offlineEventUserIds, isEmpty);
      await store.dispose();
    },
  );

  test('emits only when an online status actually changes', () async {
    final store = PresenceStatusStore();
    final snapshots = <Set<String>>[];
    final subscription = store.watch().listen(snapshots.add);
    await Future<void>.delayed(Duration.zero);

    store.record('peer-a', isOnline: true);
    store.record('peer-a', isOnline: true);
    store.recordAll({'peer-a': true, 'peer-b': true});
    store.record('peer-a', isOnline: false);
    await Future<void>.delayed(Duration.zero);

    expect(snapshots, [
      isEmpty,
      {'peer-a'},
      {'peer-a', 'peer-b'},
      {'peer-b'},
    ]);

    await subscription.cancel();
    await store.dispose();
  });

  test('clear removes every volatile status', () async {
    final store = PresenceStatusStore();
    store.recordAll({'peer-a': true, 'peer-b': true});

    store.clear();

    expect(store.onlineUserIds, isEmpty);
    await store.dispose();
  });
}
