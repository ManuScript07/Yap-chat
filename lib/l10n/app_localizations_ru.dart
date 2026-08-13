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
  String get chatsMessagePrefixYou => 'Ты';

  @override
  String get timeJustNow => 'Только что';

  @override
  String get today => 'Сегодня';

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

  @override
  String get failedToLoadChats => 'Не удалось загрузить чаты';

  @override
  String get noChats => 'У вас нет чатов';

  @override
  String get chatInputHint => 'Введите сообщение';

  @override
  String get chatOnlineStatus => 'В сети';

  @override
  String get chatOfflineStatus => 'Не в сети';

  @override
  String get chatAddPhoto => 'Добавить фото';

  @override
  String get chatActionCamera => 'Камера';

  @override
  String get chatActionGallery => 'Галерея';

  @override
  String get chatActionLocation => 'Локация';

  @override
  String chatSendFiles(Object count) {
    return 'Отправить ($count)';
  }

  @override
  String get chatSelectFiles => 'Выберите файлы';

  @override
  String get noMessages => 'Нет сообщений';

  @override
  String get permissionDenied => 'Разрешение отклонено';

  @override
  String get youMustAllowCameraPermission =>
      'Чтобы сделать фото, необходимо разрешить доступ к камере в настройках приложения.';

  @override
  String get cancel => 'Отмена';

  @override
  String get settings => 'Настроки';

  @override
  String get photoHasBeenSavedToGallery => 'Фото сохранено в галерею';

  @override
  String get failedToSavePhoto => 'Не удалось сохранить фото';

  @override
  String get repeat => 'Повторить';
}
