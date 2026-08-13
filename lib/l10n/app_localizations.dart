import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @navChats.
  ///
  /// In ru, this message translates to:
  /// **'Чатикс'**
  String get navChats;

  /// No description provided for @navFriends.
  ///
  /// In ru, this message translates to:
  /// **'Друны'**
  String get navFriends;

  /// No description provided for @navProfile.
  ///
  /// In ru, this message translates to:
  /// **'Акк'**
  String get navProfile;

  /// No description provided for @searchHintChats.
  ///
  /// In ru, this message translates to:
  /// **'поиск по чатам'**
  String get searchHintChats;

  /// No description provided for @chatsMessagePrefixYou.
  ///
  /// In ru, this message translates to:
  /// **'Ты'**
  String get chatsMessagePrefixYou;

  /// No description provided for @timeJustNow.
  ///
  /// In ru, this message translates to:
  /// **'Только что'**
  String get timeJustNow;

  /// No description provided for @today.
  ///
  /// In ru, this message translates to:
  /// **'Сегодня'**
  String get today;

  /// No description provided for @timeYesterday.
  ///
  /// In ru, this message translates to:
  /// **'Вчера'**
  String get timeYesterday;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} мин. назад} few{{count} мин. назад} many{{count} мин. назад} other{{count} мин. назад}}'**
  String timeMinutesAgo(num count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} ч. назад} few{{count} ч. назад} many{{count} ч. назад} other{{count} ч. назад}}'**
  String timeHoursAgo(num count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} дн. назад} few{{count} дня назад} many{{count} дней назад} other{{count} дней назад}}'**
  String timeDaysAgo(num count);

  /// No description provided for @failedToLoadChats.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить чаты'**
  String get failedToLoadChats;

  /// No description provided for @noChats.
  ///
  /// In ru, this message translates to:
  /// **'У вас нет чатов'**
  String get noChats;

  /// No description provided for @chatInputHint.
  ///
  /// In ru, this message translates to:
  /// **'Введите сообщение'**
  String get chatInputHint;

  /// No description provided for @chatOnlineStatus.
  ///
  /// In ru, this message translates to:
  /// **'В сети'**
  String get chatOnlineStatus;

  /// No description provided for @chatOfflineStatus.
  ///
  /// In ru, this message translates to:
  /// **'Не в сети'**
  String get chatOfflineStatus;

  /// No description provided for @chatAddPhoto.
  ///
  /// In ru, this message translates to:
  /// **'Добавить фото'**
  String get chatAddPhoto;

  /// No description provided for @chatActionCamera.
  ///
  /// In ru, this message translates to:
  /// **'Камера'**
  String get chatActionCamera;

  /// No description provided for @chatActionGallery.
  ///
  /// In ru, this message translates to:
  /// **'Галерея'**
  String get chatActionGallery;

  /// No description provided for @chatActionLocation.
  ///
  /// In ru, this message translates to:
  /// **'Локация'**
  String get chatActionLocation;

  /// No description provided for @chatSendFiles.
  ///
  /// In ru, this message translates to:
  /// **'Отправить ({count})'**
  String chatSendFiles(Object count);

  /// No description provided for @chatSelectFiles.
  ///
  /// In ru, this message translates to:
  /// **'Выберите файлы'**
  String get chatSelectFiles;

  /// No description provided for @noMessages.
  ///
  /// In ru, this message translates to:
  /// **'Нет сообщений'**
  String get noMessages;

  /// No description provided for @permissionDenied.
  ///
  /// In ru, this message translates to:
  /// **'Разрешение отклонено'**
  String get permissionDenied;

  /// No description provided for @youMustAllowCameraPermission.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы сделать фото, необходимо разрешить доступ к камере в настройках приложения.'**
  String get youMustAllowCameraPermission;

  /// No description provided for @cancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// No description provided for @settings.
  ///
  /// In ru, this message translates to:
  /// **'Настроки'**
  String get settings;

  /// No description provided for @photoHasBeenSavedToGallery.
  ///
  /// In ru, this message translates to:
  /// **'Фото сохранено в галерею'**
  String get photoHasBeenSavedToGallery;

  /// No description provided for @failedToSavePhoto.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить фото'**
  String get failedToSavePhoto;

  /// No description provided for @repeat.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get repeat;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
