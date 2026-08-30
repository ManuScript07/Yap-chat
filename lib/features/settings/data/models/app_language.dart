import 'package:flutter/material.dart';

/// Supported language selected by an account for the app interface.
///
/// The value is deliberately kept separate from privacy preferences: it is an
/// account preference, can be reused by future settings, and is also used for
/// notification language on the server.
enum AppLanguage {
  russian('ru'),
  english('en');

  const AppLanguage(this.code);

  final String code;

  Locale get locale => Locale(code);

  static AppLanguage? tryParse(Object? value) => AppLanguage.values
      .where((language) => language.code == value)
      .firstOrNull;

  static AppLanguage fromSystemLocale(Locale locale) =>
      locale.languageCode == english.code ? english : russian;
}
