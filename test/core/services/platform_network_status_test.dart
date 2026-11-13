import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const methods = MethodChannel('com.yapchat.app/network_status');
  const codec = StandardMethodCodec();
  final calls = <String>[];
  final errors = <FlutterErrorDetails>[];
  FlutterExceptionHandler? previousHandler;

  void emit(Object? data) => binding.channelBuffers.push(
    methods.name,
    codec.encodeSuccessEnvelope(data),
    (_) {},
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    errors.clear();
    previousHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    debugDefaultTargetPlatformOverride = null;
    FlutterError.onError = previousHandler;
  });

  test(
    'one subscription accepts bool snapshots and unregisters once',
    () async {
      final result = <bool>[];
      final subscription = const PlatformNetworkStatus().watch().listen(
        result.add,
      );
      await Future<void>.delayed(Duration.zero);
      emit({'available': true});
      emit({'available': false});
      emit({'available': null});
      emit({'available': 'invalid'});
      emit('invalid');
      await Future<void>.delayed(Duration.zero);
      expect(result, [true, false]);
      expect(calls, ['listen']);
      await subscription.cancel();
      await subscription.cancel();
      expect(calls, ['listen', 'cancel']);
    },
  );

  test('non-Android platform makes no platform calls', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(await const PlatformNetworkStatus().watch().toList(), isEmpty);
    expect(calls, isEmpty);
  });

  test(
    'opaque route generations preserve available-to-available handoffs',
    () async {
      final result = <PlatformNetworkSnapshot>[];
      final subscription = const PlatformNetworkStatus()
          .watchSnapshots()
          .listen(result.add);
      await Future<void>.delayed(Duration.zero);
      emit({'available': true, 'generation': 1});
      emit({'available': true, 'generation': 2});
      emit({'available': false, 'generation': 3});
      await Future<void>.delayed(Duration.zero);
      expect(result.map((event) => event.available), [true, true, false]);
      expect(result.map((event) => event.generation), [1, 2, 3]);
      await subscription.cancel();
    },
  );

  test('missing native host does not produce a global Flutter error', () async {
    messenger.setMockMethodCallHandler(methods, null);
    final subscription = const PlatformNetworkStatus().watch().listen(
      (_) => fail('No native events'),
    );
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(errors, isEmpty);
  });

  test('native setup error falls back without reporting offline', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      if (call.method == 'listen') throw PlatformException(code: 'unsupported');
      return null;
    });
    expect(await const PlatformNetworkStatus().watch().toList(), isEmpty);
    expect(calls, ['listen', 'cancel']);
    expect(errors, isEmpty);
  });

  test('native event error does not mean network unavailable', () async {
    final result = <bool>[];
    final subscription = const PlatformNetworkStatus().watch().listen(
      result.add,
    );
    await Future<void>.delayed(Duration.zero);
    binding.channelBuffers.push(
      methods.name,
      codec.encodeErrorEnvelope(code: 'failed'),
      (_) {},
    );
    emit({'available': true});
    await Future<void>.delayed(Duration.zero);
    expect(result, [true]);
    await subscription.cancel();
  });

  test('cancel waits for native listen to finish before teardown', () async {
    final gate = Completer<void>();
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      if (call.method == 'listen') await gate.future;
      return null;
    });
    final subscription = const PlatformNetworkStatus().watch().listen((_) {});
    final done = subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['listen']);
    gate.complete();
    await done;
    expect(calls, ['listen', 'cancel']);
  });
}
