// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get navChats => 'Чатикс';

  @override
  String get navFriends => 'Друны';

  @override
  String get navProfile => 'Акк';

  @override
  String get searchHintChats => 'поиск по чатам';

  @override
  String get chatsMessagePrefixYou => 'Ты: ';

  @override
  String get timeJustNow => 'Только что';

  @override
  String get timeYesterday => 'Вчера';

  @override
  String timeMinutesAgo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count мин. назад',
      many: '$count мин. назад',
      few: '$count мин. назад',
      one: '$count мин. назад',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ч. назад',
      many: '$count ч. назад',
      few: '$count ч. назад',
      one: '$count ч. назад',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дней назад',
      many: '$count дней назад',
      few: '$count дня назад',
      one: '$count дн. назад',
    );
    return '$_temp0';
  }
}
