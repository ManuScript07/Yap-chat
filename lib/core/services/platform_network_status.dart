import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Passive Android default-route events. Other platforms use SDK/API evidence.
class PlatformNetworkSnapshot {
  const PlatformNetworkSnapshot({required this.available, this.generation});

  final bool available;
  final int? generation;
}

class PlatformNetworkStatus {
  const PlatformNetworkStatus();

  static const channel = EventChannel('com.yapchat.app/network_status');

  Stream<bool> watch() => watchSnapshots().map((event) => event.available);

  Stream<PlatformNetworkSnapshot> watchSnapshots() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Stream.empty();
    }
    // Use the EventChannel wire protocol with an optional native host. The
    // standard receiveBroadcastStream reports a missing listen handler as a
    // global FlutterError, which must not turn connectivity observation into
    // an application error on older hosts or in standalone tests.
    const codec = StandardMethodCodec();
    final messenger = ServicesBinding.instance.defaultBinaryMessenger;
    final methods = OptionalMethodChannel(channel.name);
    late final StreamController<PlatformNetworkSnapshot> events;
    Future<void>? listening;
    var cancelled = false;

    Future<void> start() async {
      messenger.setMessageHandler(channel.name, (message) async {
        if (cancelled || message == null) return null;
        try {
          final event = codec.decodeEnvelope(message);
          if (event is Map && event['available'] is bool) {
            events.add(
              PlatformNetworkSnapshot(
                available: event['available'] as bool,
                generation: event['generation'] is int
                    ? event['generation'] as int
                    : null,
              ),
            );
          }
        } on PlatformException {
          // A bridge failure supplies no evidence of network loss.
        } on FormatException {
          // Ignore an incompatible native envelope, retaining SDK evidence.
        }
        return null;
      });
      try {
        await methods.invokeMethod<void>('listen');
      } on PlatformException {
        unawaited(events.close());
      }
    }

    events = StreamController<PlatformNetworkSnapshot>(
      onListen: () => listening = start(),
      onCancel: () async {
        cancelled = true;
        messenger.setMessageHandler(channel.name, null);
        await listening;
        try {
          await methods.invokeMethod<void>('cancel');
        } on PlatformException {
          // Idempotent teardown, including an already detached native engine.
        }
      },
    );
    return events.stream;
  }
}
