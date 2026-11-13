import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local Android branding only; no network calls or periodic retries.
class NativeAppBranding {
  NativeAppBranding({
    MethodChannel? channel,
    SharedPreferencesAsync? preferences,
  }) : _channel = channel ?? const MethodChannel('com.yapchat.app/branding'),
       _preferences = preferences ?? SharedPreferencesAsync();

  static const languagePreferenceKey = 'native_branding_language';

  /// Read before runApp, so the first Flutter splash matches the native one.
  static Future<String?> readStartupLanguage({
    SharedPreferencesAsync? preferences,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final language = await (preferences ?? SharedPreferencesAsync())
          .getString(languagePreferenceKey);
      return language == 'ru' || language == 'en' ? language : null;
    } catch (_) {
      return null;
    }
  }

  final MethodChannel _channel;
  final SharedPreferencesAsync _preferences;
  String? _desired;
  String? _applied;
  Future<void>? _running;

  Future<void> initialize(
    String fallbackLanguage, {
    String? cachedLanguage,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    String? stored = cachedLanguage;
    if (stored == null) {
      try {
        stored = await _preferences.getString(languagePreferenceKey);
      } catch (_) {}
    }
    // A confirmed account event may have arrived while preferences were read.
    if (_desired != null) return;
    await applyLanguage(
      stored == 'ru' || stored == 'en' ? stored! : fallbackLanguage,
    );
  }

  Future<void> applyLanguage(String language) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value();
    }
    assert(language == 'ru' || language == 'en');
    _desired = language;
    if (_running case final running?) {
      return running;
    }
    final completion = Completer<void>();
    _running = completion.future;
    unawaited(_drain(completion));
    return completion.future;
  }

  Future<void> _drain(Completer<void> completion) async {
    try {
      while (_desired != _applied) {
        final language = _desired!;
        try {
          // Async preferences avoid stale values in the background isolate.
          await _preferences.setString(languagePreferenceKey, language);
          await _channel.invokeMethod<void>('setLanguage', language);
          _applied = language;
        } catch (error) {
          debugPrint('Native branding update failed: $error');
          if (_desired != language) continue;
          // Retry on the next confirmed event/resume, without a timer.
          return;
        }
      }
    } finally {
      // Release ownership before notifying callers; a new event cannot be lost
      // between finishing the drain and completing its returned future.
      _running = null;
      completion.complete();
    }
  }
}
