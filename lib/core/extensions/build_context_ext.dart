import 'package:flutter/material.dart';
import 'package:yap_chat/l10n/app_localizations.dart';


extension BuildContextExt on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  TextTheme get textTheme => Theme.of(this).textTheme;

  Color get scaffoldBackgroundColor => Theme.of(this).scaffoldBackgroundColor;
}
