import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yap_chat/core/core.dart';

abstract class TimeFormatter {
  /// Форматирование времени для списка чатов (относительное время)
  static String format(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    final localeName = Localizations.localeOf(context).languageCode;

    final nowDate = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    final calendarDaysAgo = nowDate.difference(targetDate).inDays;

    if (difference.inMinutes < 1) {
      return context.l10n.timeJustNow;
    } else if (difference.inMinutes < 60) {
      return context.l10n.timeMinutesAgo(difference.inMinutes);
    } else if (difference.inHours < 24 && calendarDaysAgo == 0) {
      return context.l10n.timeHoursAgo(difference.inHours);
    } else if (calendarDaysAgo == 1) {
      return context.l10n.timeYesterday;
    } else if (calendarDaysAgo >= 2 && calendarDaysAgo <= 7) {
      return context.l10n.timeDaysAgo(calendarDaysAgo);
    } else if (date.year == now.year) {
      return DateFormat('d MMMM', localeName).format(date);
    } else {
      return DateFormat('dd.MM.yy').format(date);
    }
  }

  /// Форматирование для разделителя дней в ленте сообщений
  static String formatDateSeparator(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final localeName = Localizations.localeOf(context).languageCode;

    final nowDate = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    final calendarDaysAgo = nowDate.difference(targetDate).inDays;

    if (calendarDaysAgo == 0) {
      return context.l10n.today;
    } else if (calendarDaysAgo == 1) {
      return context.l10n.timeYesterday;
    } else if (date.year == now.year) {
      return DateFormat('d MMMM', localeName).format(date);
    } else {
      return DateFormat('d MMMM yyyy', localeName).format(date);
    }
  }
}
