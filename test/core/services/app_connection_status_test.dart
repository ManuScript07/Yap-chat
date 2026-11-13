import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/services/services.dart';

const _delay = Duration(milliseconds: 250);
const _offline = SocketException('offline');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('presentation', () {
    _test('unknown authenticated state is quiet and entirely passive', (h) {
      expect(h.status.value, isFalse);
      expect(h.clock.pendingTimers, isEmpty);
      h.clock.elapse(const Duration(days: 1));
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
    });

    _test('uses the default 250 ms delay, exactly once', (h) {
      expect(h.status.presentationDelay, _delay);
      h.status.reportNetworkAvailability(false);
      expect(h.status.value, isFalse);
      h.clock.elapse(const Duration(milliseconds: 249));
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
      h.clock.elapse(const Duration(milliseconds: 1));
      expect(h.status.value, isTrue);
      expect(h.notifications, [true]);
      h.clock.elapse(const Duration(hours: 1));
      expect(h.notifications, [true]);
      expect(h.clock.periodicTimerCount, 0);
    });

    _test('recovery before the delay cancels the presentation', (h) {
      h.status.reportNetworkAvailability(false);
      h.clock.elapse(const Duration(milliseconds: 249));
      h.status.reportNetworkAvailability(true);
      h.clock.elapse(const Duration(seconds: 1));
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
      expect(h.clock.pendingTimers, isEmpty);
    });

    _test('repeated failure evidence does not postpone the deadline', (h) {
      final ticket = h.ticket;
      h.status.realtimeConnecting(ticket);
      h.clock.elapse(const Duration(milliseconds: 100));
      h.status.realtimeUnavailable(ticket);
      h.failApi(_offline);
      h.clock.elapse(const Duration(milliseconds: 149));
      expect(h.status.value, isFalse);
      h.clock.elapse(const Duration(milliseconds: 1));
      expect(h.status.value, isTrue);
      expect(h.notifications, [true]);
    });

    _test('a new loss after recovery gets its own full delay', (h) {
      h.status.reportNetworkAvailability(false);
      h.clock.elapse(const Duration(milliseconds: 200));
      h.status.reportNetworkAvailability(true);
      h.status.reportNetworkAvailability(false);
      h.clock.elapse(const Duration(milliseconds: 249));
      expect(h.status.value, isFalse);
      h.clock.elapse(const Duration(milliseconds: 1));
      expect(h.status.value, isTrue);
    });

    _test('recovery hides immediately and does not notify redundantly', (h) {
      h.status.reportNetworkAvailability(false);
      h.show();
      h.status.reportNetworkAvailability(false);
      h.status.reportNetworkAvailability(true);
      expect(h.status.value, isFalse);
      h.status.reportNetworkAvailability(true);
      h.succeedApi();
      expect(h.notifications, [true, false]);
    });

    _test('zero delay publishes synchronously', (h) {
      h.status.reportNetworkAvailability(false);
      expect(h.status.value, isTrue);
      expect(h.clock.pendingTimers, isEmpty);
    }, delay: Duration.zero);

    _test('a custom delay is honored', (h) {
      h.status.reportNetworkAvailability(false);
      h.clock.elapse(const Duration(milliseconds: 499));
      expect(h.status.value, isFalse);
      h.clock.elapse(const Duration(milliseconds: 1));
      expect(h.status.value, isTrue);
    }, delay: const Duration(milliseconds: 500));
  });

  group('independent API and realtime lanes', () {
    _test('a healthy API cannot clear realtime loss', (h) {
      final channel = h.ticket;
      h.status.realtimeUnavailable(channel);
      h.show();
      h.succeedApi();
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(channel);
      expect(h.status.value, isFalse);
    });

    _test('a subscribed channel cannot clear API loss', (h) {
      h.failApi(_offline);
      h.show();
      h.status.realtimeSubscribed(h.ticket);
      expect(h.status.value, isTrue);
      h.succeedApi();
      expect(h.status.value, isFalse);
    });

    for (final realtimeFirst in [false, true]) {
      for (final recoverApiFirst in [false, true]) {
        _test('both lanes fail (RT first=$realtimeFirst), '
            'recover independently (API first=$recoverApiFirst)', (h) {
          final channel = h.ticket;
          if (realtimeFirst) h.status.realtimeUnavailable(channel);
          h.failApi(_offline);
          if (!realtimeFirst) h.status.realtimeUnavailable(channel);
          h.show();
          if (recoverApiFirst) {
            h.succeedApi();
            expect(h.status.value, isTrue);
            h.status.realtimeSubscribed(channel);
          } else {
            h.status.realtimeSubscribed(channel);
            expect(h.status.value, isTrue);
            h.succeedApi();
          }
          expect(h.status.value, isFalse);
          expect(h.notifications, [true, false]);
        });
      }
    }

    _test('a rejected private channel alone is not network loss', (h) {
      final channel = h.ticket;
      h.status.realtimeConnecting(channel);
      h.status.realtimeRejected(channel);
      h.show();
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
    });

    _test('rejection cannot conceal an independent API failure', (h) {
      h.failApi(_offline);
      h.status.realtimeRejected(h.ticket);
      h.show();
      expect(h.status.value, isTrue);
      h.succeedApi();
      expect(h.status.value, isFalse);
    });

    _test('an intentional realtime pause does not clear API failure', (h) {
      h.status.realtimeUnavailable(h.ticket);
      h.failApi(_offline);
      h.show();
      h.status.realtimePaused();
      expect(h.status.value, isTrue);
      h.succeedApi();
      expect(h.status.value, isFalse);
    });

    _test('an intentional realtime pause cancels its pending banner', (h) {
      h.status.realtimeConnecting(h.ticket);
      h.status.realtimePaused();
      h.show();
      expect(h.status.value, isFalse);
      expect(h.clock.pendingTimers, isEmpty);
    });

    _test('null realtime observations provide no evidence', (h) {
      h.status.realtimeConnecting(null);
      h.status.realtimeUnavailable(null);
      h.show();
      expect(h.status.value, isFalse);
      h.status.realtimeUnavailable(h.ticket);
      h.show();
      h.status.realtimeSubscribed(null);
      h.status.realtimeRejected(null);
      expect(h.status.value, isTrue);
    });
  });

  group('request ordering and network epochs', () {
    for (final oldFails in [false, true]) {
      for (final oldCompletesFirst in [false, true]) {
        _test('older API fails=$oldFails, completes first=$oldCompletesFirst', (
          h,
        ) {
          final older = h.start<Object>();
          final newer = h.start<Object>();
          void finishOlder() {
            if (oldFails) {
              older.source.completeError(_offline);
            } else {
              older.source.complete(Object());
            }
            h.flush();
          }

          void finishNewer() {
            if (oldFails) {
              newer.source.complete(Object());
            } else {
              newer.source.completeError(_offline);
            }
            h.flush();
          }

          if (oldCompletesFirst) {
            finishOlder();
            finishNewer();
          } else {
            finishNewer();
            finishOlder();
          }
          h.show();
          expect(h.status.value, !oldFails);
          expect(older.completed, isTrue);
          expect(newer.completed, isTrue);
        });
      }
    }

    _test('capturing unrelated work does not invalidate an API completion', (
      h,
    ) {
      final pending = h.start<void>();
      h.ticket;
      h.status.synchronizeSession();
      pending.source.completeError(_offline);
      h.flush();
      h.show();
      expect(h.status.value, isTrue);
    });

    _test('duplicate route notifications preserve in-flight work', (h) {
      h.status.reportNetworkAvailability(true);
      final pending = h.start<void>();
      h.status.reportNetworkAvailability(true);
      pending.source.completeError(_offline);
      h.flush();
      h.show();
      expect(h.status.value, isTrue);
    });

    for (final lateFailure in [false, true]) {
      for (final staleCompletesFirst in [false, true]) {
        _test('online route handoff ignores old API (fails=$lateFailure, '
            'old completes first=$staleCompletesFirst)', (h) {
          h.status.reportNetworkAvailability(true, generation: 10);
          final oldRoute = h.ticket;
          final pending = h.start<void>();
          h.status.reportNetworkAvailability(true, generation: 11);
          final newRoute = h.ticket;
          expect(newRoute.network, isNot(oldRoute.network));
          expect(h.status.value, isFalse);
          expect(h.notifications, isEmpty);

          void finishStale() {
            if (lateFailure) {
              pending.source.completeError(_offline);
            } else {
              pending.source.complete();
            }
            h.flush();
          }

          void finishFresh() {
            if (lateFailure) {
              h.succeedApi();
            } else {
              h.failApi(_offline);
            }
            h.show();
          }

          if (staleCompletesFirst) {
            finishStale();
            h.show();
            expect(h.status.value, isFalse);
            expect(h.notifications, isEmpty);
            finishFresh();
          } else {
            finishFresh();
            finishStale();
            h.show();
          }
          expect(pending.completed, isTrue);
          expect(h.status.value, !lateFailure);
        });
      }
    }

    _test('duplicate online route generation preserves pending API work', (h) {
      h.status.reportNetworkAvailability(true, generation: 10);
      final before = h.ticket;
      final pending = h.start<void>();
      h.status.reportNetworkAvailability(true, generation: 10);
      expect(h.ticket.network, before.network);
      pending.source.completeError(_offline);
      h.flush();
      h.show();
      expect(h.status.value, isTrue);
    });

    _test('an online route handoff preserves the existing channel owner', (h) {
      h.status.reportNetworkAvailability(true, generation: 10);
      final channel = h.ticket;
      h.status.realtimeConnecting(channel);
      h.status.realtimeSubscribed(channel);
      h.status.reportNetworkAvailability(true, generation: 11);
      h.status.realtimeUnavailable(channel);
      h.show();
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(channel);
      expect(h.status.value, isFalse);
    });

    _test('neither lane can declare recovery while there is no route', (h) {
      h.status.reportNetworkAvailability(false);
      h.succeedApi();
      h.status.realtimeSubscribed(h.ticket);
      h.show();
      expect(h.status.value, isTrue);
      expect(h.notifications, [true]);
    });

    for (final lateFailure in [false, true]) {
      _test('old-route API completion is ignored (fails=$lateFailure)', (h) {
        h.status.reportNetworkAvailability(true);
        final beforeLoss = h.start<void>();
        h.status.reportNetworkAvailability(false);
        h.show();
        h.status.reportNetworkAvailability(true);
        h.failApi(_offline);
        h.show();
        if (lateFailure) {
          // Establish healthy evidence in the new epoch first.
          h.succeedApi();
          beforeLoss.source.completeError(_offline);
        } else {
          beforeLoss.source.complete();
        }
        h.flush();
        h.show();
        expect(h.status.value, !lateFailure);
      });
    }

    _test('a request started offline cannot recover a later network epoch', (
      h,
    ) {
      h.status.reportNetworkAvailability(false);
      final offlineRequest = h.start<void>();
      h.status.reportNetworkAvailability(true);
      h.failApi(_offline);
      h.show();
      offlineRequest.source.complete();
      h.flush();
      expect(h.status.value, isTrue);
      h.succeedApi();
      expect(h.status.value, isFalse);
    });

    _test('a restored route alone does not confirm the surviving channel', (h) {
      h.status.reportNetworkAvailability(true);
      final channel = h.ticket;
      h.status.realtimeSubscribed(channel);
      h.status.reportNetworkAvailability(false);
      h.show();
      h.status.reportNetworkAvailability(true);
      h.succeedApi();
      expect(h.status.value, isTrue);
      // Fresh channel traffic can use its original subscription observation.
      h.status.realtimeSubscribed(channel);
      expect(h.status.value, isFalse);
    });

    _test('an obsolete channel cannot conceal a replacement failure', (h) {
      final oldChannel = h.ticket;
      h.status.realtimeConnecting(oldChannel);
      final replacement = h.ticket;
      h.status.realtimeConnecting(replacement);
      h.status.realtimeUnavailable(replacement);
      h.show();
      h.status.realtimeSubscribed(oldChannel);
      expect(h.status.value, isTrue);
    });

    _test('an obsolete channel cannot reintroduce loss after replacement', (h) {
      final oldChannel = h.ticket;
      h.status.realtimeConnecting(oldChannel);
      final replacement = h.ticket;
      h.status.realtimeConnecting(replacement);
      h.status.realtimeSubscribed(replacement);
      h.status.realtimeUnavailable(oldChannel);
      h.show();
      expect(h.status.value, isFalse);
    });

    _test('unrelated newer API observations do not age out the channel', (h) {
      final channel = h.ticket;
      h.status.realtimeConnecting(channel);
      h.succeedApi();
      h.succeedApi();
      h.status.realtimeSubscribed(channel);
      h.show();
      expect(h.status.value, isFalse);
      h.status.realtimeUnavailable(channel);
      h.show();
      expect(h.status.value, isTrue);
    });

    _test('an obsolete rejection cannot conceal a replacement failure', (h) {
      final oldChannel = h.ticket;
      h.status.realtimeConnecting(oldChannel);
      final replacement = h.ticket;
      h.status.realtimeConnecting(replacement);
      h.status.realtimeUnavailable(replacement);
      h.show();
      h.status.realtimeRejected(oldChannel);
      expect(h.status.value, isTrue);
    });
  });

  group('account boundaries', () {
    _test('retrying a rejected private channel is not network loss', (h) {
      final denied = h.ticket;
      h.status.realtimeConnecting(denied);
      h.status.realtimeRejected(denied);
      h.status.realtimeConnecting(h.ticket);
      h.show();
      expect(h.status.value, isFalse);
      final retry = h.ticket;
      h.status.realtimeConnecting(retry);
      h.status.realtimeUnavailable(retry);
      h.show();
      expect(h.status.value, isTrue);
    });

    _test('intentional pause rejects late callbacks of its old channel', (h) {
      final old = h.ticket;
      h.status.realtimeConnecting(old);
      h.status.realtimePaused();
      h.status.realtimeUnavailable(old);
      h.show();
      expect(h.status.value, isFalse);
      final replacement = h.ticket;
      h.status.realtimeConnecting(replacement);
      h.status.realtimeUnavailable(replacement);
      h.show();
      h.status.realtimeSubscribed(old);
      expect(h.status.value, isTrue);
    });

    _test('an intentional pause fences every already captured RT callback', (
      h,
    ) {
      final old = h.ticket;
      h.status.realtimeConnecting(old);
      final queuedBeforePause = h.ticket;
      h.status.realtimePaused();
      for (final stale in [old, queuedBeforePause]) {
        h.status.realtimeConnecting(stale);
        h.status.realtimeUnavailable(stale);
        h.show();
        expect(h.status.value, isFalse);
      }
      final replacement = h.ticket;
      h.status.realtimeConnecting(replacement);
      h.status.realtimeUnavailable(replacement);
      h.show();
      for (final stale in [old, queuedBeforePause]) {
        h.status.realtimeSubscribed(stale);
        h.status.realtimeRejected(stale);
        expect(h.status.value, isTrue);
      }
      h.status.realtimeSubscribed(replacement);
      expect(h.status.value, isFalse);
    });

    _test('reactivation cannot reuse a channel from an inactive session', (h) {
      final old = h.ticket;
      h.status.realtimeConnecting(old);
      h.status.realtimeSubscribed(old);
      h.status.synchronizeSession(active: false);
      h.status.synchronizeSession();
      h.status.realtimeUnavailable(old);
      h.show();
      expect(h.status.value, isFalse);
      final replacement = h.ticket;
      h.status.realtimeConnecting(replacement);
      h.status.realtimeUnavailable(replacement);
      h.show();
      h.status.realtimeSubscribed(old);
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(replacement);
      expect(h.status.value, isFalse);
    });

    for (final fails in [false, true]) {
      _test('an actual channel pause does not cancel API work (fails=$fails)', (
        h,
      ) {
        if (!fails) h.failApi(_offline);
        final pending = h.start<void>();
        h.status.realtimePaused();
        if (fails) {
          pending.source.completeError(_offline);
        } else {
          pending.source.complete();
        }
        h.flush();
        h.show();
        expect(h.status.value, fails);
      });
    }

    _test('logged-out and inactive states suppress all observations', (h) {
      h.account.setAuthenticatedUser(null);
      h.status.synchronizeSession();
      expect(h.status.capture(), isNull);
      h.status.reportNetworkAvailability(false);
      h.failApi(_offline);
      h.show();
      expect(h.status.value, isFalse);
      h.account.setAuthenticatedUser('account-a');
      h.status.synchronizeSession(active: false);
      expect(h.status.capture(), isNull);
      h.show();
      expect(h.status.value, isFalse);
      h.status.synchronizeSession();
      h.show();
      expect(h.status.value, isTrue);
    });

    _test('logout hides an already visible banner synchronously', (h) {
      h.failApi(_offline);
      h.show();
      h.account.setAuthenticatedUser(null);
      h.status.synchronizeSession();
      expect(h.status.value, isFalse);
      expect(h.status.capture(), isNull);
      expect(h.notifications, [true, false]);
    });

    _test(
      'the delayed callback rechecks the account even without an auth tick',
      (h) {
        h.failApi(_offline);
        h.clock.elapse(const Duration(milliseconds: 249));
        h.account.setAuthenticatedUser(null);
        h.clock.elapse(const Duration(milliseconds: 1));
        expect(h.status.value, isFalse);
        expect(h.notifications, isEmpty);
      },
    );

    for (final nextUser in ['account-b', 'account-a']) {
      for (final lateFailure in [false, true]) {
        _test('late API fails=$lateFailure after logout/login as $nextUser', (
          h,
        ) {
          final pending = h.start<void>();
          final oldChannel = h.ticket;
          h.account.setAuthenticatedUser(null);
          h.account.setAuthenticatedUser(nextUser);
          h.status.synchronizeSession();
          if (!lateFailure) h.failApi(_offline);
          if (lateFailure) {
            pending.source.completeError(_offline);
          } else {
            pending.source.complete();
          }
          h.status.realtimeConnecting(oldChannel);
          h.status.realtimeUnavailable(oldChannel);
          h.status.realtimeSubscribed(oldChannel);
          h.flush();
          h.show();
          expect(h.status.value, !lateFailure);
          final current = h.ticket;
          expect(current.session.userId, nextUser);
          expect(
            current.session.generation,
            isNot(oldChannel.session.generation),
          );
        });
      }
    }

    _test(
      'capture notices an account switch without explicit synchronization',
      (h) {
        final stale = h.ticket;
        h.status.realtimeUnavailable(stale);
        h.show();
        h.account.setAuthenticatedUser('account-b');
        final current = h.ticket;
        expect(current.session.userId, 'account-b');
        expect(h.status.value, isFalse);
        h.status.realtimeUnavailable(stale);
        h.show();
        expect(h.status.value, isFalse);
      },
    );

    _test('an old timer cannot shorten the next account presentation delay', (
      h,
    ) {
      h.status.reportNetworkAvailability(false);
      h.clock.elapse(const Duration(milliseconds: 200));
      h.account.setAuthenticatedUser('account-b');
      h.status.synchronizeSession();
      h.clock.elapse(const Duration(milliseconds: 249));
      expect(h.status.value, isFalse);
      h.clock.elapse(const Duration(milliseconds: 1));
      expect(h.status.value, isTrue);
    });

    _test('an active-state reset restarts the full delay', (h) {
      h.status.reportNetworkAvailability(false);
      h.clock.elapse(const Duration(milliseconds: 200));
      h.status.synchronizeSession(active: false);
      h.status.synchronizeSession();
      h.clock.elapse(const Duration(milliseconds: 249));
      expect(h.status.value, isFalse);
      h.clock.elapse(const Duration(milliseconds: 1));
      expect(h.status.value, isTrue);
    });

    _test('switching accounts resets an already visible offline banner', (h) {
      h.status.reportNetworkAvailability(false);
      h.show();
      h.account.setAuthenticatedUser('account-b');
      h.status.synchronizeSession();
      expect(h.status.value, isFalse);
      h.clock.elapse(const Duration(milliseconds: 249));
      expect(h.status.value, isFalse);
      h.clock.elapse(const Duration(milliseconds: 1));
      expect(h.status.value, isTrue);
      expect(h.notifications, [true, false, true]);
    });

    _test('duplicate session synchronization preserves current requests', (h) {
      final pending = h.start<void>();
      h.status.synchronizeSession();
      h.status.synchronizeSession();
      pending.source.completeError(_offline);
      h.flush();
      h.show();
      expect(h.status.value, isTrue);
    });
  });

  group('lifecycle', () {
    _test('short inactivity keeps presentation and valid API work', (h) {
      final pending = h.start<void>();
      h.status.setForeground(false);
      expect(h.status.capture(), isNotNull);
      pending.source.completeError(_offline);
      h.flush();
      h.show();
      expect(h.status.value, isTrue);
      h.status.setForeground(true);
      h.clock.elapse(const Duration(milliseconds: 249));
      expect(h.status.value, isTrue);
      h.clock.elapse(const Duration(milliseconds: 1));
      expect(h.status.value, isTrue);
    });

    _test('recovery during short inactivity remains valid after resume', (h) {
      h.failApi(_offline);
      h.show();
      final pending = h.start<void>();
      h.status.setForeground(false);
      expect(h.status.value, isTrue);
      pending.source.complete();
      h.flush();
      h.status.setForeground(true);
      h.show();
      expect(h.status.value, isFalse);
    });

    _test('short inactivity does not invalidate an existing channel', (h) {
      final channel = h.ticket;
      h.status.realtimeConnecting(channel);
      h.status.setForeground(false);
      h.status.realtimeSubscribed(channel);
      h.status.setForeground(true);
      h.show();
      expect(h.status.value, isFalse);
      h.status.realtimeUnavailable(channel);
      h.show();
      expect(h.status.value, isTrue);
    });

    for (final lateFailure in [false, true]) {
      _test('background invalidates old API work (fails=$lateFailure)', (h) {
        final pending = h.start<void>();
        final channel = h.ticket;
        h.status.setForeground(false, suspended: true);
        expect(h.status.capture(), isNull);
        h.status.realtimePaused();
        h.status.setForeground(true);
        if (!lateFailure) h.failApi(_offline);
        if (lateFailure) {
          pending.source.completeError(_offline);
        } else {
          pending.source.complete();
        }
        h.status.realtimeUnavailable(channel);
        h.status.realtimeSubscribed(channel);
        h.flush();
        h.show();
        expect(h.status.value, !lateFailure);
      });
    }

    _test('background stays suspended through inactive until resumed', (h) {
      final beforeBackground = h.ticket;
      h.status.setForeground(false, suspended: true);
      h.status.setForeground(false);
      h.status.realtimePaused();
      expect(h.status.capture(), isNull);
      h.failApi(_offline);
      h.status.realtimeUnavailable(beforeBackground);
      h.show();
      expect(h.status.value, isFalse);
      h.status.setForeground(true);
      expect(h.status.capture(), isNotNull);
      h.show();
      expect(h.status.value, isFalse);
      h.failApi(_offline);
      h.show();
      expect(h.status.value, isTrue);
    });

    _test(
      'an actual background pause prevents old channel heartbeat recovery',
      (h) {
        final beats = h.watchHeartbeats();
        final channel = h.ticket;
        h.status.realtimeSubscribed(channel);
        h.status.setForeground(false, suspended: true);
        h.status.realtimePaused();
        h.status.setForeground(true);
        final replacement = h.ticket;
        h.status.realtimeConnecting(replacement);
        beats.add(RealtimeHeartbeatStatus.ok);
        h.show();
        expect(h.status.value, isTrue);
        h.status.realtimeSubscribed(replacement);
        expect(h.status.value, isFalse);
      },
    );

    _test(
      'an actual pause fences callbacks across repeated background signals',
      (h) {
        h.status.setForeground(false, suspended: true);
        h.status.setForeground(true);
        final channel = h.ticket;
        h.status.realtimeUnavailable(channel);
        h.show();
        h.status.setForeground(false, suspended: true);
        h.status.realtimePaused();
        h.status.setForeground(false, suspended: true);
        h.status.setForeground(true);
        h.status.realtimeUnavailable(channel);
        h.show();
        expect(h.status.value, isFalse);
      },
    );

    for (final lateFailure in [false, true]) {
      _test('coalesced resume retains channel but ignores old API '
          '(fails=$lateFailure)', (h) {
        final channel = h.ticket;
        h.status.realtimeConnecting(channel);
        h.status.realtimeSubscribed(channel);
        final pending = h.start<void>();
        h.status.setForeground(false, suspended: true);
        h.status.setForeground(false);
        expect(h.status.capture(), isNull);
        // The coordinator coalesces this pause/resume. No channel was stopped.
        h.status.setForeground(true);
        expect(h.ticket.lifecycle, isNot(channel.lifecycle));
        h.status.realtimeUnavailable(channel);
        h.show();
        expect(h.status.value, isTrue);
        // A fresh broadcast still carries the surviving channel's old token.
        h.status.realtimeSubscribed(channel);
        expect(h.status.value, isFalse);
        if (lateFailure) {
          pending.source.completeError(_offline);
        } else {
          h.failApi(_offline);
          h.show();
          pending.source.complete();
        }
        h.flush();
        h.show();
        expect(h.status.value, !lateFailure);
        h.succeedApi();
        expect(h.status.value, isFalse);
      });
    }

    _test('coalesced resume retains private-channel heartbeat confirmation', (
      h,
    ) {
      final beats = h.watchHeartbeats();
      final channel = h.ticket;
      h.status.realtimeConnecting(channel);
      h.status.realtimeSubscribed(channel);
      h.status.setForeground(false, suspended: true);
      h.status.setForeground(false);
      h.status.setForeground(true);
      // No broadcast or join occurred after resume. Existing confirmation
      // must still allow the SDK heartbeat to report channel transport loss.
      beats.add(RealtimeHeartbeatStatus.timeout);
      h.show();
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(channel);
      expect(h.status.value, isFalse);
    });

    _test('a retained channel can finish subscribing during background', (h) {
      final beats = h.watchHeartbeats();
      final channel = h.status.captureRealtime()!;
      h.status.realtimeConnecting(channel);
      h.status.setForeground(false, suspended: true);
      expect(h.status.capture(), isNull);
      // The owner coalesces pause/resume and never calls realtimePaused().
      h.status.realtimeSubscribed(channel);
      h.status.setForeground(false);
      h.show();
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
      h.status.setForeground(true);
      h.show();
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
      // No post-resume broadcast or subscription callback is needed. A
      // heartbeat error proves the background join retained confirmation.
      beats.add(RealtimeHeartbeatStatus.error);
      h.show();
      expect(h.status.value, isTrue);
      beats.add(RealtimeHeartbeatStatus.ok);
      expect(h.status.value, isFalse);
      expect(h.notifications, [true, false]);
    });

    _test(
      'captureRealtime allows a channel to start and subscribe in background',
      (h) {
        final beats = h.watchHeartbeats();
        h.status.setForeground(false, suspended: true);
        expect(h.status.capture(), isNull);
        final channel = h.status.captureRealtime();
        expect(channel, isNotNull);
        h.status.realtimeConnecting(channel);
        h.show();
        expect(h.status.value, isFalse);
        expect(h.clock.pendingTimers, isEmpty);
        h.status.realtimeSubscribed(channel);
        h.show();
        expect(h.status.value, isFalse);
        expect(h.notifications, isEmpty);
        h.status.setForeground(true);
        h.show();
        expect(h.status.value, isFalse);
        expect(h.notifications, isEmpty);
        beats.add(RealtimeHeartbeatStatus.error);
        h.show();
        expect(h.status.value, isTrue);
        beats.add(RealtimeHeartbeatStatus.ok);
        expect(h.status.value, isFalse);
      },
    );

    _test(
      'a background channel start remains connecting until its actual join',
      (h) {
        h.status.setForeground(false, suspended: true);
        final channel = h.status.captureRealtime();
        expect(channel, isNotNull);
        h.status.realtimeConnecting(channel);
        h.show();
        expect(h.status.value, isFalse);
        h.status.setForeground(true);
        h.show();
        expect(h.status.value, isTrue);
        h.status.realtimeSubscribed(channel);
        expect(h.status.value, isFalse);
      },
    );

    _test('a real owner pause still rejects joins received during background', (
      h,
    ) {
      final beats = h.watchHeartbeats();
      final channel = h.status.captureRealtime()!;
      h.status.realtimeConnecting(channel);
      h.status.setForeground(false, suspended: true);
      h.status.realtimePaused();
      h.status.realtimeConnecting(channel);
      h.status.realtimeUnavailable(channel);
      h.status.realtimeSubscribed(channel);
      h.status.realtimeRejected(channel);
      h.show();
      expect(h.status.value, isFalse);
      h.status.setForeground(true);
      beats.add(RealtimeHeartbeatStatus.error);
      h.show();
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
      final replacement = h.status.captureRealtime()!;
      h.status.realtimeConnecting(replacement);
      h.status.realtimeUnavailable(replacement);
      h.show();
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(channel);
      beats.add(RealtimeHeartbeatStatus.ok);
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(replacement);
      expect(h.status.value, isFalse);
    });

    _test('captureRealtime still requires an active authenticated session', (
      h,
    ) {
      h.status.setForeground(false, suspended: true);
      expect(h.status.captureRealtime(), isNotNull);
      h.status.synchronizeSession(active: false);
      expect(h.status.captureRealtime(), isNull);
      h.status.synchronizeSession();
      expect(h.status.captureRealtime(), isNotNull);
      h.account.setAuthenticatedUser(null);
      expect(h.status.captureRealtime(), isNull);
      h.account.setAuthenticatedUser('account-b');
      final current = h.status.captureRealtime();
      expect(current, isNotNull);
      expect(current!.session.userId, 'account-b');
      h.status.dispose();
      expect(h.status.captureRealtime(), isNull);
    });

    for (final lateFailure in [false, true]) {
      _test('long-inactive request invalidation preserves channel '
          '(old API fails=$lateFailure)', (h) {
        final channel = h.ticket;
        h.status.realtimeConnecting(channel);
        h.status.realtimeSubscribed(channel);
        if (!lateFailure) h.failApi(_offline);
        final pending = h.start<void>();
        final before = h.ticket;
        h.status.setForeground(false);
        h.clock.elapse(const Duration(seconds: 30));
        h.status.invalidatePendingRequests();
        h.status.setForeground(true);
        expect(h.ticket.lifecycle, isNot(before.lifecycle));
        if (lateFailure) {
          pending.source.completeError(_offline);
        } else {
          pending.source.complete();
        }
        h.flush();
        h.show();
        expect(h.status.value, !lateFailure);
        h.succeedApi();
        expect(h.status.value, isFalse);
        h.status.realtimeUnavailable(channel);
        h.show();
        expect(h.status.value, isTrue);
        h.status.realtimeSubscribed(channel);
        expect(h.status.value, isFalse);
      });
    }

    _test(
      'request invalidation retains channel confirmation without rejoining',
      (h) {
        final beats = h.watchHeartbeats();
        final channel = h.ticket;
        h.status.realtimeConnecting(channel);
        h.status.realtimeSubscribed(channel);
        h.status.invalidatePendingRequests();
        h.status.invalidatePendingRequests();
        beats.add(RealtimeHeartbeatStatus.timeout);
        h.show();
        expect(h.status.value, isTrue);
        h.status.realtimeSubscribed(channel);
        expect(h.status.value, isFalse);
      },
    );
  });

  group('heartbeat observation', () {
    _test('heartbeats cannot confirm a channel that never subscribed', (h) {
      final beats = h.watchHeartbeats();
      h.status.realtimeConnecting(h.ticket);
      for (final beat in RealtimeHeartbeatStatus.values) {
        beats.add(beat);
      }
      h.show();
      expect(h.status.value, isTrue);
    });

    for (final failure in [
      RealtimeHeartbeatStatus.timeout,
      RealtimeHeartbeatStatus.error,
    ]) {
      _test('$failure reports loss only after channel confirmation', (h) {
        final beats = h.watchHeartbeats();
        beats.add(failure);
        h.show();
        expect(h.status.value, isFalse);
        h.status.realtimeSubscribed(h.ticket);
        beats.add(failure);
        h.show();
        expect(h.status.value, isTrue);
        h.succeedApi();
        expect(h.status.value, isTrue);
        h.status.realtimeSubscribed(h.ticket);
        expect(h.status.value, isFalse);
      });
    }

    _test(
      'heartbeat error recovers on the next OK without broadcast or rejoin',
      (h) {
        final beats = h.watchHeartbeats();
        final channel = h.ticket;
        h.status.realtimeConnecting(channel);
        h.status.realtimeSubscribed(channel);
        beats.add(RealtimeHeartbeatStatus.error);
        h.show();
        expect(h.status.value, isTrue);
        beats.add(RealtimeHeartbeatStatus.sent);
        expect(h.status.value, isTrue);
        beats.add(RealtimeHeartbeatStatus.ok);
        expect(h.status.value, isFalse);
        expect(h.notifications, [true, false]);
        // The recovered channel remains confirmed for subsequent heartbeats.
        beats.add(RealtimeHeartbeatStatus.error);
        h.show();
        expect(h.status.value, isTrue);
        beats.add(RealtimeHeartbeatStatus.ok);
        expect(h.status.value, isFalse);
      },
    );

    _test('an OK before 250 ms cancels a transient heartbeat-error banner', (
      h,
    ) {
      final beats = h.watchHeartbeats();
      h.status.realtimeSubscribed(h.ticket);
      beats.add(RealtimeHeartbeatStatus.error);
      h.clock.elapse(const Duration(milliseconds: 249));
      beats.add(RealtimeHeartbeatStatus.ok);
      h.show();
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
      expect(h.clock.pendingTimers, isEmpty);
    });

    _test(
      'heartbeat-error recovery leaves an independent API failure visible',
      (h) {
        final beats = h.watchHeartbeats();
        h.status.realtimeSubscribed(h.ticket);
        h.failApi(_offline);
        beats.add(RealtimeHeartbeatStatus.error);
        h.show();
        beats.add(RealtimeHeartbeatStatus.ok);
        expect(h.status.value, isTrue);
        h.succeedApi();
        expect(h.status.value, isFalse);
      },
    );

    _test('a heartbeat timeout still requires fresh channel evidence', (h) {
      final beats = h.watchHeartbeats();
      final channel = h.ticket;
      h.status.realtimeSubscribed(channel);
      beats.add(RealtimeHeartbeatStatus.error);
      beats.add(RealtimeHeartbeatStatus.ok);
      beats.add(RealtimeHeartbeatStatus.timeout);
      h.show();
      expect(h.status.value, isTrue);
      beats.add(RealtimeHeartbeatStatus.ok);
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(channel);
      expect(h.status.value, isFalse);
    });

    _test(
      'an actual pause revokes confirmation retained after heartbeat error',
      (h) {
        final beats = h.watchHeartbeats();
        final oldChannel = h.ticket;
        h.status.realtimeConnecting(oldChannel);
        h.status.realtimeSubscribed(oldChannel);
        beats.add(RealtimeHeartbeatStatus.error);
        h.status.realtimePaused();
        final replacement = h.ticket;
        h.status.realtimeConnecting(replacement);
        h.show();
        beats.add(RealtimeHeartbeatStatus.ok);
        h.status.realtimeSubscribed(oldChannel);
        expect(h.status.value, isTrue);
        h.status.realtimeSubscribed(replacement);
        expect(h.status.value, isFalse);
      },
    );

    _test('a sent heartbeat is not recovery evidence', (h) {
      final beats = h.watchHeartbeats();
      h.status.reportNetworkAvailability(true);
      h.status.realtimeSubscribed(h.ticket);
      h.status.reportNetworkAvailability(false);
      h.status.reportNetworkAvailability(true);
      beats.add(RealtimeHeartbeatStatus.sent);
      h.show();
      expect(h.status.value, isTrue);
      beats.add(RealtimeHeartbeatStatus.ok);
      expect(h.status.value, isFalse);
    });

    _test('a healthy heartbeat cannot conceal API loss', (h) {
      final beats = h.watchHeartbeats();
      h.status.realtimeSubscribed(h.ticket);
      h.failApi(_offline);
      h.show();
      beats.add(RealtimeHeartbeatStatus.ok);
      expect(h.status.value, isTrue);
      h.succeedApi();
      expect(h.status.value, isFalse);
    });

    _test('heartbeats do not age out the confirmed channel observation', (h) {
      final beats = h.watchHeartbeats();
      final channel = h.ticket;
      h.status.realtimeSubscribed(channel);
      beats.add(RealtimeHeartbeatStatus.ok);
      beats.add(RealtimeHeartbeatStatus.sent);
      h.status.realtimeUnavailable(channel);
      h.show();
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(channel);
      expect(h.status.value, isFalse);
    });

    _test('a healthy socket cannot confirm an explicitly failed channel', (h) {
      final beats = h.watchHeartbeats();
      final channel = h.ticket;
      h.status.realtimeSubscribed(channel);
      h.status.realtimeUnavailable(channel);
      h.show();
      beats.add(RealtimeHeartbeatStatus.ok);
      expect(h.status.value, isTrue);
      h.status.realtimeSubscribed(channel);
      expect(h.status.value, isFalse);
    });

    _test('a heartbeat cannot declare recovery with no network route', (h) {
      final beats = h.watchHeartbeats();
      h.status.realtimeSubscribed(h.ticket);
      h.status.reportNetworkAvailability(false);
      beats.add(RealtimeHeartbeatStatus.ok);
      h.show();
      expect(h.status.value, isTrue);
      h.status.reportNetworkAvailability(true);
      expect(h.status.value, isTrue);
      beats.add(RealtimeHeartbeatStatus.ok);
      expect(h.status.value, isFalse);
    });

    _test('a healthy heartbeat cannot repair a rejected private channel', (h) {
      final beats = h.watchHeartbeats();
      h.status.realtimeSubscribed(h.ticket);
      h.status.realtimeRejected(h.ticket);
      beats.add(RealtimeHeartbeatStatus.ok);
      beats.add(RealtimeHeartbeatStatus.timeout);
      h.show();
      expect(h.status.value, isFalse);
    });

    _test('logout/login cannot reuse the previous channel confirmation', (h) {
      final beats = h.watchHeartbeats();
      h.status.realtimeSubscribed(h.ticket);
      h.account.setAuthenticatedUser(null);
      h.account.setAuthenticatedUser('account-a');
      h.status.synchronizeSession();
      beats.add(RealtimeHeartbeatStatus.timeout);
      h.show();
      expect(h.status.value, isFalse);
      h.status.realtimeConnecting(h.ticket);
      beats.add(RealtimeHeartbeatStatus.ok);
      h.show();
      expect(h.status.value, isTrue);
    });

    _test('only one existing heartbeat stream is observed', (h) {
      final first = h.watchHeartbeats();
      final second = h.watchHeartbeats();
      expect(first.hasListener, isTrue);
      expect(second.hasListener, isFalse);
      h.status.realtimeSubscribed(h.ticket);
      second.add(RealtimeHeartbeatStatus.timeout);
      h.show();
      expect(h.status.value, isFalse);
      first.add(RealtimeHeartbeatStatus.timeout);
      h.show();
      expect(h.status.value, isTrue);
    });
  });

  group('error classification', () {
    final connectionErrors = <String, Object>{
      'timeout': TimeoutException('deadline'),
      'socket': _offline,
      'TLS': const TlsException('handshake'),
      'HTTP client': http.ClientException('connection closed'),
      for (final code in [
        '502',
        '503',
        '504',
        'PGRST000',
        'PGRST001',
        'PGRST002',
      ])
        code: PostgrestException(message: 'service unavailable', code: code),
    };
    final localErrors = <String, Object>{
      'explicit abort': http.RequestAbortedException(),
      'format': const FormatException('bad JSON'),
      'permission': PlatformException(code: 'permission_denied'),
      'domain': StateError('conversation is closed'),
      'argument': ArgumentError('invalid local input'),
    };
    final serverErrors = <String, Object>{
      for (final code in [
        '400',
        '401',
        '403',
        '404',
        '409',
        '422',
        '429',
        '500',
        '42501',
        '23505',
        'P0001',
        'PGRST116',
        'PGRST301',
      ])
        code: PostgrestException(
          message: 'permission/quota/domain',
          code: code,
        ),
      'missing code': const PostgrestException(message: 'domain error'),
    };

    for (final entry in connectionErrors.entries) {
      _test('${entry.key} is connection loss and preserves error/stack', (h) {
        expect(AppConnectionStatus.isConnectionFailure(entry.value), isTrue);
        final stack = StackTrace.fromString('original ${entry.key} stack');
        final pending = h.failApi(entry.value, stack: stack);
        h.show();
        expect(h.status.value, isTrue);
        expect(pending.error, same(entry.value));
        expect(pending.stack.toString(), stack.toString());
      });
    }

    for (final entry in {...localErrors, ...serverErrors}.entries) {
      _test('${entry.key} does not invent network loss', (h) {
        expect(AppConnectionStatus.isConnectionFailure(entry.value), isFalse);
        final stack = StackTrace.fromString('original ${entry.key} stack');
        final pending = h.failApi(entry.value, stack: stack);
        h.show();
        expect(h.status.value, isFalse);
        expect(pending.error, same(entry.value));
        expect(pending.stack.toString(), stack.toString());
      });

      _test('${entry.key} cannot clear independent realtime loss', (h) {
        h.status.realtimeUnavailable(h.ticket);
        h.show();
        h.failApi(entry.value);
        expect(h.status.value, isTrue);
      });
    }

    for (final entry in localErrors.entries) {
      _test('${entry.key} cannot clear an established API failure', (h) {
        h.failApi(_offline);
        h.show();
        h.failApi(entry.value);
        expect(h.status.value, isTrue);
        h.succeedApi();
        expect(h.status.value, isFalse);
      });

      _test('${entry.key} does not supersede older valid API evidence', (h) {
        final pending = h.start<void>();
        h.failApi(entry.value);
        pending.source.completeError(_offline);
        h.flush();
        h.show();
        expect(h.status.value, isTrue);
      });
    }

    test('null and arbitrary text are not connection evidence', () {
      expect(AppConnectionStatus.isConnectionFailure(null), isFalse);
      expect(AppConnectionStatus.isConnectionFailure('503 timeout'), isFalse);
      expect(AppConnectionStatus.isConnectionFailure(Object()), isFalse);
    });
  });

  group('transparent observation and diagnostics', () {
    _test('returns the exact original success value and invokes once', (h) {
      final expected = Object();
      var calls = 0;
      final result = _Result<Object>(
        h.status.observe(() {
          calls++;
          return Future.value(expected);
        }),
      );
      h.flush();
      expect(calls, 1);
      expect(result.completed, isTrue);
      expect(result.value, same(expected));
      expect(result.error, isNull);
    });

    _test('preserves a nullable result', (h) {
      final result = _Result<Object?>(
        h.status.observe(() => Future.value(null)),
      );
      h.flush();
      expect(result.completed, isTrue);
      expect(result.value, isNull);
      expect(result.error, isNull);
    });

    _test('synchronous throws preserve the original error and stack', (h) {
      final error = StateError('synchronous failure');
      final stack = StackTrace.fromString('original synchronous stack');
      final result = _Result<void>(
        h.status.observe<void>(() {
          Error.throwWithStackTrace(error, stack);
        }),
      );
      h.flush();
      expect(result.error, same(error));
      expect(result.stack.toString(), stack.toString());
      h.show();
      expect(h.status.value, isFalse);
    });

    for (final diagnosticsEnabled in [false, true]) {
      _test('diagnostics enabled=$diagnosticsEnabled cannot gate status', (h) {
        final diagnostics = AppDiagnostics(enabled: diagnosticsEnabled);
        var calls = 0;
        final error = TimeoutException('server unavailable');
        final stack = StackTrace.fromString('original RPC stack');
        final result = _Result<void>(
          observeSupabaseRpc<void>(h.status, diagnostics, 'test_rpc', () {
            calls++;
            return Future<void>.error(error, stack);
          }),
        );
        h.flush();
        h.show();
        expect(calls, 1);
        expect(h.status.value, isTrue);
        expect(result.error, same(error));
        expect(result.stack.toString(), stack.toString());
        final snapshot = diagnostics.snapshot();
        if (diagnosticsEnabled) {
          expect(snapshot.rpc['test_rpc']!.calls, 1);
          expect(snapshot.rpc['test_rpc']!.errors, 1);
        } else {
          expect(snapshot.rpc, isEmpty);
        }
      });
    }

    _test('the RPC wrapper also works without diagnostics', (h) {
      final expected = Object();
      final result = _Result<Object>(
        observeSupabaseRpc(
          h.status,
          null,
          'test_rpc',
          () => Future.value(expected),
        ),
      );
      h.flush();
      expect(result.value, same(expected));
    });

    test('the RPC wrapper works without either observer', () async {
      final expected = Object();
      var calls = 0;
      final actual = await observeSupabaseRpc(null, null, 'test_rpc', () {
        calls++;
        return Future.value(expected);
      });
      expect(actual, same(expected));
      expect(calls, 1);
    });

    _test('disabled development mode observes without publishing', (h) {
      final beats = h.watchHeartbeats();
      expect(h.status.capture(), isNull);
      expect(h.status.captureRealtime(), isNull);
      h.status.setForeground(false, suspended: true);
      expect(h.status.captureRealtime(), isNull);
      h.status.setForeground(true);
      h.status.reportNetworkAvailability(false);
      h.status.realtimeConnecting(null);
      h.status.realtimeUnavailable(null);
      h.failApi(_offline);
      final value = h.succeedApi();
      beats.add(RealtimeHeartbeatStatus.timeout);
      h.show();
      expect(value.completed, isTrue);
      expect(h.status.value, isFalse);
      expect(h.notifications, isEmpty);
      expect(h.clock.pendingTimers, isEmpty);
    }, enabled: false);
  });

  group('ownership and disposal', () {
    _test('removing a consumer does not reset retained state', (h) {
      final values = <bool>[];
      void listener() => values.add(h.status.value);
      h.status.addListener(listener);
      h.status.reportNetworkAvailability(false);
      h.show();
      expect(values, [true]);
      h.status.removeListener(listener);
      h.status.reportNetworkAvailability(true);
      h.status.reportNetworkAvailability(false);
      h.show();
      expect(values, [true]);
      expect(h.status.value, isTrue);
      h.status.addListener(listener);
      expect(h.status.value, isTrue);
      h.status.reportNetworkAvailability(true);
      expect(values, [true, false]);
      h.status.removeListener(listener);
    });

    _test('dispose cancels its timer and the heartbeat subscription', (h) {
      var cancellations = 0;
      final beats = h.watchHeartbeats(onCancel: () => cancellations++);
      h.status.realtimeSubscribed(h.ticket);
      h.status.reportNetworkAvailability(false);
      expect(h.clock.nonPeriodicTimerCount, 1);
      h.status.dispose();
      h.flush();
      expect(beats.hasListener, isFalse);
      expect(cancellations, 1);
      expect(h.clock.pendingTimers, isEmpty);
      beats.add(RealtimeHeartbeatStatus.timeout);
      h.clock.elapse(const Duration(days: 1));
      expect(h.notifications, isEmpty);
      h.status.dispose();
      expect(cancellations, 1);
    });

    _test('late request completions after disposal remain transparent', (h) {
      final success = h.start<Object>();
      final failure = h.start<void>();
      final expected = Object();
      final stack = StackTrace.fromString('disposed request original stack');
      h.status.dispose();
      success.source.complete(expected);
      failure.source.completeError(_offline, stack);
      h.flush();
      expect(success.result.value, same(expected));
      expect(failure.result.error, same(_offline));
      expect(failure.result.stack.toString(), stack.toString());
      expect(h.notifications, isEmpty);
      expect(h.clock.pendingTimers, isEmpty);
    });

    _test('all entry points are harmless after disposal', (h) {
      final channel = h.ticket;
      h.status.dispose();
      h.status.synchronizeSession();
      h.status.invalidatePendingRequests();
      h.status.setForeground(false, suspended: true);
      h.status.reportNetworkAvailability(false);
      h.status.realtimeConnecting(channel);
      h.status.realtimeSubscribed(channel);
      h.status.realtimeUnavailable(channel);
      h.status.realtimeRejected(channel);
      h.status.realtimePaused();
      final beats = h.watchHeartbeats();
      h.succeedApi();
      h.failApi(_offline);
      h.show();
      expect(h.status.capture(), isNull);
      expect(beats.hasListener, isFalse);
      expect(h.notifications, isEmpty);
      expect(h.clock.pendingTimers, isEmpty);
    });
  });

  testWidgets('a newly mounted consumer immediately reads retained status', (
    tester,
  ) async {
    final status = AppConnectionStatus(
      accountSessionController: AccountSessionController(initialUserId: 'a'),
    );
    addTearDown(status.dispose);
    status.reportNetworkAvailability(false);
    await tester.pump(_delay);
    expect(status.value, isTrue);

    Widget consumer() => Directionality(
      textDirection: TextDirection.ltr,
      child: ValueListenableBuilder<bool>(
        valueListenable: status.listenable,
        builder: (context, connecting, child) =>
            Text(connecting ? 'connecting' : 'ready'),
      ),
    );

    await tester.pumpWidget(consumer());
    expect(find.text('connecting'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(status.value, isTrue);
    await tester.pumpWidget(consumer());
    expect(find.text('connecting'), findsOneWidget);
    status.reportNetworkAvailability(true);
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

// Each unit test owns a fake clock. Futures are observed before completion so
// intentionally rejected requests cannot leak unhandled asynchronous errors.
void _test(
  String name,
  void Function(_Harness) body, {
  Duration? delay,
  bool enabled = true,
}) {
  test(name, () {
    fakeAsync((clock) {
      final harness = _Harness(clock, delay: delay, enabled: enabled);
      try {
        body(harness);
      } finally {
        harness.dispose();
      }
      expect(clock.pendingTimers, isEmpty);
    });
  });
}

class _Harness {
  _Harness(this.clock, {Duration? delay, bool enabled = true}) {
    status = delay == null
        ? AppConnectionStatus(
            accountSessionController: account,
            enabled: enabled,
          )
        : AppConnectionStatus(
            accountSessionController: account,
            presentationDelay: delay,
            enabled: enabled,
          );
    status.addListener(() => notifications.add(status.value));
  }

  final FakeAsync clock;
  final account = AccountSessionController(initialUserId: 'account-a');
  late final AppConnectionStatus status;
  final notifications = <bool>[];
  final _streams = <StreamController<RealtimeHeartbeatStatus>>[];

  ConnectionObservation get ticket => status.capture()!;

  void flush() => clock.flushMicrotasks();

  void show() {
    flush();
    clock.elapse(_delay);
    flush();
  }

  _Pending<T> start<T>() => _Pending<T>(status);

  _Result<void> failApi(Object error, {StackTrace? stack}) {
    final pending = start<void>();
    pending.source.completeError(error, stack);
    flush();
    expect(pending.result.completed, isTrue);
    expect(pending.result.error, same(error));
    return pending.result;
  }

  _Result<Object> succeedApi() {
    final expected = Object();
    final pending = start<Object>();
    pending.source.complete(expected);
    flush();
    expect(pending.result.value, same(expected));
    return pending.result;
  }

  StreamController<RealtimeHeartbeatStatus> watchHeartbeats({
    void Function()? onCancel,
  }) {
    final stream = StreamController<RealtimeHeartbeatStatus>.broadcast(
      sync: true,
      onCancel: onCancel,
    );
    _streams.add(stream);
    status.watchHeartbeats(stream.stream);
    return stream;
  }

  void dispose() {
    status.dispose();
    for (final stream in _streams) {
      unawaited(stream.close());
    }
    flush();
  }
}

class _Pending<T> {
  _Pending(AppConnectionStatus status) {
    result = _Result<T>(status.observe(() => source.future));
  }

  final source = Completer<T>();
  late final _Result<T> result;

  bool get completed => result.completed;
}

class _Result<T> {
  _Result(Future<T> future) {
    unawaited(
      future.then<void>(
        (result) {
          value = result;
          completed = true;
        },
        onError: (Object failure, StackTrace trace) {
          error = failure;
          stack = trace;
          completed = true;
        },
      ),
    );
  }

  bool completed = false;
  T? value;
  Object? error;
  StackTrace? stack;
}
