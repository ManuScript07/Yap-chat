import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/settings/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/branding');
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'startup seed accepts only supported saved languages and survives read failure',
    () async {
      final preferences = _Preferences();
      for (final value in [null, 'en', 'ru', 'invalid']) {
        preferences.value = value;
        expect(
          await NativeAppBranding.readStartupLanguage(preferences: preferences),
          value == 'ru' || value == 'en' ? value : null,
        );
      }
      preferences.read = () async => throw StateError('storage unavailable');
      expect(
        await NativeAppBranding.readStartupLanguage(preferences: preferences),
        isNull,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await NativeAppBranding.readStartupLanguage(preferences: preferences),
        isNull,
      );
    },
  );

  test(
    'keeps saved branding at startup and suppresses repeated resume calls',
    () async {
      final prefs = _Preferences()..value = 'en';
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.arguments as String);
            return null;
          });
      final service = NativeAppBranding(channel: channel, preferences: prefs);
      await service.initialize('ru');
      for (var i = 0; i < 20; i++) {
        await service.applyLanguage('en');
      }
      expect(calls, ['en']);
      expect(prefs.writes, ['en']);
    },
  );
  test(
    'reuses the preloaded startup language without another storage read',
    () async {
      final preferences = _Preferences()
        ..read = () async => throw StateError('must not read twice');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.arguments as String);
            return null;
          });
      await NativeAppBranding(
        channel: channel,
        preferences: preferences,
      ).initialize('ru', cachedLanguage: 'en');
      expect(calls, ['en']);
    },
  );
  test('serializes changes and ends in the latest language', () async {
    final prefs = _Preferences();
    final gate = Completer<void>();
    final entered = Completer<void>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.arguments as String);
          if (calls.length == 1) {
            entered.complete();
            await gate.future;
          }
          return null;
        });
    final service = NativeAppBranding(channel: channel, preferences: prefs);
    final first = service.applyLanguage('ru');
    await entered.future;
    service.applyLanguage('en');
    gate.complete();
    await first;
    expect(calls, ['ru', 'en']);
    expect(prefs.value, 'en');
  });
  test(
    'retries a failed native call on the next event, without a timer',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            if (++calls == 1) {
              throw PlatformException(code: 'temporarily_unavailable');
            }
            return null;
          });
      final prefs = _Preferences();
      final service = NativeAppBranding(channel: channel, preferences: prefs);
      await service.applyLanguage('en');
      await service.applyLanguage('en');
      await service.applyLanguage('en');
      expect(calls, 2);
    },
  );
  test('late startup read cannot undo a confirmed language event', () async {
    final gate = Completer<String?>();
    final prefs = _Preferences()..read = () => gate.future;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.arguments as String);
          return null;
        });
    final service = NativeAppBranding(channel: channel, preferences: prefs);
    final starting = service.initialize('en');
    await service.applyLanguage('ru');
    gate.complete('en');
    await starting;
    expect(calls, ['ru']);
    expect(prefs.value, 'ru');
  });
  test(
    'a burst coalesces and still accepts a change after completion',
    () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.arguments as String);
            if (calls.length == 1) {
              entered.complete();
              await gate.future;
            }
            return null;
          });
      final service = NativeAppBranding(
        channel: channel,
        preferences: _Preferences(),
      );
      final initial = service.applyLanguage('ru');
      await entered.future;
      for (var i = 0; i < 100; i++) {
        unawaited(service.applyLanguage(i.isEven ? 'ru' : 'en'));
      }
      gate.complete();
      await initial;
      expect(calls, ['ru', 'en']);
      await service.applyLanguage('ru');
      expect(calls, ['ru', 'en', 'ru']);
    },
  );
  test(
    'storage failure does not call native and permits a later retry',
    () async {
      final prefs = _Preferences()..failWrite = true;
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls++;
            return null;
          });
      final service = NativeAppBranding(channel: channel, preferences: prefs);
      await service.applyLanguage('en');
      expect(calls, 0);
      prefs.failWrite = false;
      await service.applyLanguage('en');
      expect(calls, 1);
      expect(prefs.value, 'en');
    },
  );
  test('does not access native/storage on other platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final prefs = _Preferences();
    final service = NativeAppBranding(channel: channel, preferences: prefs);
    await service.initialize('en');
    await service.applyLanguage('ru');
    expect(prefs.writes, isEmpty);
  });
  for (final locale in ['en', 'de', 'fr', 'tr', 'zh']) {
    test('non-Russian device $locale defaults to English', () {
      expect(AppLanguage.fromSystemLocale(Locale(locale)), AppLanguage.english);
    });
  }
  test('Russian device defaults to Russian', () {
    expect(
      AppLanguage.fromSystemLocale(const Locale('ru', 'RU')),
      AppLanguage.russian,
    );
  });
}

// Mutable in-memory storage fake; the production implementation is immutable.
// ignore: must_be_immutable
class _Preferences implements SharedPreferencesAsync {
  String? value;
  Future<String?> Function()? read;
  bool failWrite = false;
  final writes = <String>[];
  @override
  Future<String?> getString(String key) async =>
      read == null ? value : await read!();
  @override
  Future<void> setString(String key, String next) async {
    if (failWrite) throw StateError('storage unavailable');
    value = next;
    writes.add(next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
