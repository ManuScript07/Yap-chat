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

  /// No description provided for @chatsNoSearchResults.
  ///
  /// In ru, this message translates to:
  /// **'ничего не нашли'**
  String get chatsNoSearchResults;

  /// No description provided for @chatsDeleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =1{Удалить чат?} other{Удалить чаты?}}'**
  String chatsDeleteTitle(int count);

  /// No description provided for @chatsDeleteConfirmation.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, =1{История удалится только у вас.} other{История выбранных чатов удалится только у вас.}}'**
  String chatsDeleteConfirmation(int count);

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

  /// No description provided for @chatLastSeenToday.
  ///
  /// In ru, this message translates to:
  /// **'Был(а) в {time}'**
  String chatLastSeenToday(Object time);

  /// No description provided for @chatLastSeenYesterday.
  ///
  /// In ru, this message translates to:
  /// **'Был(а) вчера в {time}'**
  String chatLastSeenYesterday(Object time);

  /// No description provided for @chatLastSeenDate.
  ///
  /// In ru, this message translates to:
  /// **'Был(а) {date} в {time}'**
  String chatLastSeenDate(Object date, Object time);

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
  /// **'тут пока ничего нет'**
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

  /// No description provided for @locationConfirmation.
  ///
  /// In ru, this message translates to:
  /// **'Вы точно хотите отправить своё местоположение пользователю {name}?'**
  String locationConfirmation(Object name);

  /// No description provided for @locationConfirmationDescription.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться местоположением?'**
  String get locationConfirmationDescription;

  /// No description provided for @locationShare.
  ///
  /// In ru, this message translates to:
  /// **'Отправить'**
  String get locationShare;

  /// No description provided for @locationDisabled.
  ///
  /// In ru, this message translates to:
  /// **'Геолокация выключена'**
  String get locationDisabled;

  /// No description provided for @locationEnableDescription.
  ///
  /// In ru, this message translates to:
  /// **'Включите геолокацию в настройках устройства, чтобы отправить местоположение.'**
  String get locationEnableDescription;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к геолокации'**
  String get locationPermissionDenied;

  /// No description provided for @locationPermissionSettingsDescription.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите доступ к геолокации в настройках приложения.'**
  String get locationPermissionSettingsDescription;

  /// No description provided for @notificationsPermissionReminderTitle.
  ///
  /// In ru, this message translates to:
  /// **'Включите уведомления'**
  String get notificationsPermissionReminderTitle;

  /// No description provided for @notificationsPermissionReminderContent.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите уведомления в настройках, чтобы не пропускать сообщения и заявки в друны.'**
  String get notificationsPermissionReminderContent;

  /// No description provided for @locationPermissionReminderTitle.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите геолокацию'**
  String get locationPermissionReminderTitle;

  /// No description provided for @locationPermissionReminderContent.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите доступ к геолокации, чтобы друны могли видеть ваше последнее местоположение.'**
  String get locationPermissionReminderContent;

  /// No description provided for @locationServiceReminderContent.
  ///
  /// In ru, this message translates to:
  /// **'Включите геолокацию на устройстве, чтобы друны могли видеть ваше последнее местоположение.'**
  String get locationServiceReminderContent;

  /// No description provided for @locationMessageYou.
  ///
  /// In ru, this message translates to:
  /// **'Вы поделились местоположением'**
  String get locationMessageYou;

  /// No description provided for @locationMessageIncoming.
  ///
  /// In ru, this message translates to:
  /// **'Вам отправили местоположение'**
  String get locationMessageIncoming;

  /// No description provided for @locationOpenError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть приложение с картой'**
  String get locationOpenError;

  /// No description provided for @microphonePermissionDenied.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к микрофону'**
  String get microphonePermissionDenied;

  /// No description provided for @microphonePermissionSettingsDescription.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите доступ к микрофону в настройках приложения, чтобы записывать голосовые сообщения.'**
  String get microphonePermissionSettingsDescription;

  /// No description provided for @voiceRecordingExitTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить голосовое сообщение?'**
  String get voiceRecordingExitTitle;

  /// No description provided for @voiceRecordingExitDescription.
  ///
  /// In ru, this message translates to:
  /// **'Запись будет удалена без возможности восстановления.'**
  String get voiceRecordingExitDescription;

  /// No description provided for @chatActionCopy.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get chatActionCopy;

  /// No description provided for @chatActionDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get chatActionDelete;

  /// No description provided for @chatActionReply.
  ///
  /// In ru, this message translates to:
  /// **'Ответить'**
  String get chatActionReply;

  /// No description provided for @chatReplyingTo.
  ///
  /// In ru, this message translates to:
  /// **'В ответ {name}'**
  String chatReplyingTo(Object name);

  /// No description provided for @chatReplyYou.
  ///
  /// In ru, this message translates to:
  /// **'Вы'**
  String get chatReplyYou;

  /// No description provided for @chatReplyPhoto.
  ///
  /// In ru, this message translates to:
  /// **'Фотография'**
  String get chatReplyPhoto;

  /// No description provided for @chatReplyAudio.
  ///
  /// In ru, this message translates to:
  /// **'Аудиосообщение'**
  String get chatReplyAudio;

  /// No description provided for @chatReplyLocation.
  ///
  /// In ru, this message translates to:
  /// **'Местоположение'**
  String get chatReplyLocation;

  /// No description provided for @readReceiptToday.
  ///
  /// In ru, this message translates to:
  /// **'Прочитано сегодня в {time}'**
  String readReceiptToday(Object time);

  /// No description provided for @readReceiptYesterday.
  ///
  /// In ru, this message translates to:
  /// **'Прочитано вчера в {time}'**
  String readReceiptYesterday(Object time);

  /// No description provided for @readReceiptDate.
  ///
  /// In ru, this message translates to:
  /// **'Прочитано {date} в {time}'**
  String readReceiptDate(Object date, Object time);

  /// No description provided for @voiceRecordingExitStay.
  ///
  /// In ru, this message translates to:
  /// **'Остаться'**
  String get voiceRecordingExitStay;

  /// No description provided for @voiceRecordingExitDiscard.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить'**
  String get voiceRecordingExitDiscard;

  /// No description provided for @authWelcomeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добро пожаловать'**
  String get authWelcomeTitle;

  /// No description provided for @authSignInWith.
  ///
  /// In ru, this message translates to:
  /// **'Войти с помощью'**
  String get authSignInWith;

  /// No description provided for @authWelcomeDescription.
  ///
  /// In ru, this message translates to:
  /// **'Общайтесь, делитесь моментами и оставайтесь на связи с близкими.'**
  String get authWelcomeDescription;

  /// No description provided for @authContinueWithYandex.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить с Яндекс ID'**
  String get authContinueWithYandex;

  /// No description provided for @authConsentHint.
  ///
  /// In ru, this message translates to:
  /// **'При первом входе мы перенесём доступные данные профиля из Яндекс ID.'**
  String get authConsentHint;

  /// No description provided for @authConsentPrefix.
  ///
  /// In ru, this message translates to:
  /// **'При входе и регистрации вы принимаете наши'**
  String get authConsentPrefix;

  /// No description provided for @authSignInFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось войти через Яндекс ID. Попробуйте ещё раз.'**
  String get authSignInFailed;

  /// No description provided for @authProfileSetupTitle.
  ///
  /// In ru, this message translates to:
  /// **'Завершение регистрации'**
  String get authProfileSetupTitle;

  /// No description provided for @authProfileSetupDescription.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте данные из Яндекс ID и заполните недостающие поля.'**
  String get authProfileSetupDescription;

  /// No description provided for @authOnboardingNameTitle.
  ///
  /// In ru, this message translates to:
  /// **'как тебя зовут?'**
  String get authOnboardingNameTitle;

  /// No description provided for @authOnboardingBirthDateTitle.
  ///
  /// In ru, this message translates to:
  /// **'а когда др?'**
  String get authOnboardingBirthDateTitle;

  /// No description provided for @authOnboardingBirthDateHint.
  ///
  /// In ru, this message translates to:
  /// **'покажем только возраст'**
  String get authOnboardingBirthDateHint;

  /// No description provided for @authOnboardingGenderTitle.
  ///
  /// In ru, this message translates to:
  /// **'кто ты?'**
  String get authOnboardingGenderTitle;

  /// No description provided for @authOnboardingAvatarTitle.
  ///
  /// In ru, this message translates to:
  /// **'добавим аву?'**
  String get authOnboardingAvatarTitle;

  /// No description provided for @authOnboardingUsernameTitle.
  ///
  /// In ru, this message translates to:
  /// **'придумай тег.'**
  String get authOnboardingUsernameTitle;

  /// No description provided for @authOnboardingUsernameHint.
  ///
  /// In ru, this message translates to:
  /// **'это уникальное имя пользователя'**
  String get authOnboardingUsernameHint;

  /// No description provided for @authOnboardingBioTitle.
  ///
  /// In ru, this message translates to:
  /// **'напиши о себе'**
  String get authOnboardingBioTitle;

  /// No description provided for @authOnboardingBioLabel.
  ///
  /// In ru, this message translates to:
  /// **'о себе'**
  String get authOnboardingBioLabel;

  /// No description provided for @authOnboardingBioHint.
  ///
  /// In ru, this message translates to:
  /// **'напишите немного о себе'**
  String get authOnboardingBioHint;

  /// No description provided for @authOnboardingSkip.
  ///
  /// In ru, this message translates to:
  /// **'скип'**
  String get authOnboardingSkip;

  /// No description provided for @authOnboardingReset.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить'**
  String get authOnboardingReset;

  /// No description provided for @authAddImage.
  ///
  /// In ru, this message translates to:
  /// **'Добавить изображение'**
  String get authAddImage;

  /// No description provided for @authOnboardingComplete.
  ///
  /// In ru, this message translates to:
  /// **'Завершить'**
  String get authOnboardingComplete;

  /// No description provided for @authBirthDateDay.
  ///
  /// In ru, this message translates to:
  /// **'ДД'**
  String get authBirthDateDay;

  /// No description provided for @authBirthDateMonth.
  ///
  /// In ru, this message translates to:
  /// **'ММ'**
  String get authBirthDateMonth;

  /// No description provided for @authBirthDateYear.
  ///
  /// In ru, this message translates to:
  /// **'ГГГГ'**
  String get authBirthDateYear;

  /// No description provided for @authDisplayNameLabel.
  ///
  /// In ru, this message translates to:
  /// **'имя'**
  String get authDisplayNameLabel;

  /// No description provided for @authDisplayNameHint.
  ///
  /// In ru, this message translates to:
  /// **'как тебя звать?'**
  String get authDisplayNameHint;

  /// No description provided for @authInputTooLong.
  ///
  /// In ru, this message translates to:
  /// **'слишком длинный'**
  String get authInputTooLong;

  /// No description provided for @authUsernameLabel.
  ///
  /// In ru, this message translates to:
  /// **'Username'**
  String get authUsernameLabel;

  /// No description provided for @authUsernameHelper.
  ///
  /// In ru, this message translates to:
  /// **'От 3 до 24 латинских букв, цифр или _. Можно оставить автоматически созданный.'**
  String get authUsernameHelper;

  /// No description provided for @authBirthDateLabel.
  ///
  /// In ru, this message translates to:
  /// **'Дата рождения'**
  String get authBirthDateLabel;

  /// No description provided for @authBirthDatePlaceholder.
  ///
  /// In ru, this message translates to:
  /// **'Выберите дату'**
  String get authBirthDatePlaceholder;

  /// No description provided for @authAcceptDocuments.
  ///
  /// In ru, this message translates to:
  /// **'Я принимаю условия использования сервиса'**
  String get authAcceptDocuments;

  /// No description provided for @authTermsOfService.
  ///
  /// In ru, this message translates to:
  /// **'Условия обслуживания'**
  String get authTermsOfService;

  /// No description provided for @authDocumentsAnd.
  ///
  /// In ru, this message translates to:
  /// **'и'**
  String get authDocumentsAnd;

  /// No description provided for @authPrivacyPolicy.
  ///
  /// In ru, this message translates to:
  /// **'Политику конфиденциальности'**
  String get authPrivacyPolicy;

  /// No description provided for @authCompleteRegistration.
  ///
  /// In ru, this message translates to:
  /// **'Завершить регистрацию'**
  String get authCompleteRegistration;

  /// No description provided for @authNameRequired.
  ///
  /// In ru, this message translates to:
  /// **'Укажите имя'**
  String get authNameRequired;

  /// No description provided for @authNameInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Имя должно содержать от 2 до 30 символов'**
  String get authNameInvalid;

  /// No description provided for @authBirthDateRequired.
  ///
  /// In ru, this message translates to:
  /// **'Укажите дату рождения'**
  String get authBirthDateRequired;

  /// No description provided for @authBirthDateInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Введите корректную дату рождения. Вам должно быть не менее 14 лет.'**
  String get authBirthDateInvalid;

  /// No description provided for @authDocumentsRequired.
  ///
  /// In ru, this message translates to:
  /// **'Необходимо принять соглашение и политику конфиденциальности'**
  String get authDocumentsRequired;

  /// No description provided for @authUsernameTaken.
  ///
  /// In ru, this message translates to:
  /// **'Этот username уже занят'**
  String get authUsernameTaken;

  /// No description provided for @authUsernameInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Username должен содержать от 3 до 24 латинских букв, цифр или _'**
  String get authUsernameInvalid;

  /// No description provided for @authProfileSaveFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить профиль. Попробуйте ещё раз.'**
  String get authProfileSaveFailed;

  /// No description provided for @authLoadFailedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить профиль'**
  String get authLoadFailedTitle;

  /// No description provided for @authLoadFailedDescription.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте подключение и повторите попытку.'**
  String get authLoadFailedDescription;

  /// No description provided for @authSignOut.
  ///
  /// In ru, this message translates to:
  /// **'Выйти'**
  String get authSignOut;

  /// No description provided for @authBack.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get authBack;

  /// No description provided for @notificationsChannelName.
  ///
  /// In ru, this message translates to:
  /// **'Сообщения'**
  String get notificationsChannelName;

  /// No description provided for @notificationsChannelDescription.
  ///
  /// In ru, this message translates to:
  /// **'Новые сообщения в чатах'**
  String get notificationsChannelDescription;

  /// No description provided for @notificationYou.
  ///
  /// In ru, this message translates to:
  /// **'Ты'**
  String get notificationYou;

  /// No description provided for @notificationPhoto.
  ///
  /// In ru, this message translates to:
  /// **'Фотография'**
  String get notificationPhoto;

  /// No description provided for @notificationAudio.
  ///
  /// In ru, this message translates to:
  /// **'Голосовое сообщение'**
  String get notificationAudio;

  /// No description provided for @notificationLocation.
  ///
  /// In ru, this message translates to:
  /// **'Местоположение'**
  String get notificationLocation;

  /// No description provided for @chatsNotificationsEnabled.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления включены'**
  String get chatsNotificationsEnabled;

  /// No description provided for @chatsNotificationsDisabled.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления отключены'**
  String get chatsNotificationsDisabled;

  /// No description provided for @newChatTitle.
  ///
  /// In ru, this message translates to:
  /// **'написать'**
  String get newChatTitle;

  /// No description provided for @newChatFindUser.
  ///
  /// In ru, this message translates to:
  /// **'найти пользователя'**
  String get newChatFindUser;

  /// No description provided for @friendsTabFriends.
  ///
  /// In ru, this message translates to:
  /// **'друны'**
  String get friendsTabFriends;

  /// No description provided for @friendsTabRequests.
  ///
  /// In ru, this message translates to:
  /// **'заявки'**
  String get friendsTabRequests;

  /// No description provided for @friendsAll.
  ///
  /// In ru, this message translates to:
  /// **'все друны'**
  String get friendsAll;

  /// No description provided for @friendsOutgoing.
  ///
  /// In ru, this message translates to:
  /// **'исходящие'**
  String get friendsOutgoing;

  /// No description provided for @friendsIncoming.
  ///
  /// In ru, this message translates to:
  /// **'входящие'**
  String get friendsIncoming;

  /// No description provided for @friendsSearchHint.
  ///
  /// In ru, this message translates to:
  /// **'поиск'**
  String get friendsSearchHint;

  /// No description provided for @friendsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'друзей пока нет. воспользуйтесь поиском или кнопкой сверху'**
  String get friendsEmpty;

  /// No description provided for @friendsRequestsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'заявок пока нет'**
  String get friendsRequestsEmpty;

  /// No description provided for @friendsNoSearchResults.
  ///
  /// In ru, this message translates to:
  /// **'ничего не нашли'**
  String get friendsNoSearchResults;

  /// No description provided for @friendsLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить друнов'**
  String get friendsLoadFailed;

  /// No description provided for @friendsActionFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить действие'**
  String get friendsActionFailed;

  /// No description provided for @friendsCancelRequest.
  ///
  /// In ru, this message translates to:
  /// **'отменить'**
  String get friendsCancelRequest;

  /// No description provided for @friendsCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} друг} few{{count} друга} many{{count} друзей} other{{count} друзей}}'**
  String friendsCount(int count);

  /// No description provided for @friendsAddTitle.
  ///
  /// In ru, this message translates to:
  /// **'добавить'**
  String get friendsAddTitle;

  /// No description provided for @friendsAddContacts.
  ///
  /// In ru, this message translates to:
  /// **'из контактов'**
  String get friendsAddContacts;

  /// No description provided for @friendsAddByUsername.
  ///
  /// In ru, this message translates to:
  /// **'поиск по никнейму'**
  String get friendsAddByUsername;

  /// No description provided for @friendsAddByUsernameTitle.
  ///
  /// In ru, this message translates to:
  /// **'добавить по никнейму'**
  String get friendsAddByUsernameTitle;

  /// No description provided for @friendsUsernameLabel.
  ///
  /// In ru, this message translates to:
  /// **'никнейм'**
  String get friendsUsernameLabel;

  /// No description provided for @friendsUsernameHint.
  ///
  /// In ru, this message translates to:
  /// **'введи никнейм'**
  String get friendsUsernameHint;

  /// No description provided for @friendsUsernameSearch.
  ///
  /// In ru, this message translates to:
  /// **'искать'**
  String get friendsUsernameSearch;

  /// No description provided for @friendsUsernameNotFound.
  ///
  /// In ru, this message translates to:
  /// **'не удалось найти'**
  String get friendsUsernameNotFound;

  /// No description provided for @friendsUsernameTooLong.
  ///
  /// In ru, this message translates to:
  /// **'никнейм слишком длинный'**
  String get friendsUsernameTooLong;

  /// No description provided for @friendsUsernameCharactersOnly.
  ///
  /// In ru, this message translates to:
  /// **'только a-z, 0-9 и _'**
  String get friendsUsernameCharactersOnly;

  /// No description provided for @friendsAddByPhone.
  ///
  /// In ru, this message translates to:
  /// **'по номеру телефона'**
  String get friendsAddByPhone;

  /// No description provided for @friendsAddByPhoneTitle.
  ///
  /// In ru, this message translates to:
  /// **'добавить по номеру телефона'**
  String get friendsAddByPhoneTitle;

  /// No description provided for @friendsPhoneLabel.
  ///
  /// In ru, this message translates to:
  /// **'номер телефона'**
  String get friendsPhoneLabel;

  /// No description provided for @friendsPhoneHint.
  ///
  /// In ru, this message translates to:
  /// **'введи номер телефона'**
  String get friendsPhoneHint;

  /// No description provided for @friendsPhoneTooLong.
  ///
  /// In ru, this message translates to:
  /// **'номер слишком длинный'**
  String get friendsPhoneTooLong;

  /// No description provided for @friendsPhoneInvalid.
  ///
  /// In ru, this message translates to:
  /// **'введите корректный номер'**
  String get friendsPhoneInvalid;

  /// No description provided for @friendsAddInviteMore.
  ///
  /// In ru, this message translates to:
  /// **'позови ещё больше друзей'**
  String get friendsAddInviteMore;

  /// No description provided for @friendsAddSocialNetworks.
  ///
  /// In ru, this message translates to:
  /// **'из соцсетей'**
  String get friendsAddSocialNetworks;

  /// No description provided for @friendsAddComingSoon.
  ///
  /// In ru, this message translates to:
  /// **'скоро'**
  String get friendsAddComingSoon;

  /// No description provided for @friendsContactsTitle.
  ///
  /// In ru, this message translates to:
  /// **'контакты'**
  String get friendsContactsTitle;

  /// No description provided for @friendsContactsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'в адресной книге нет контактов с номерами'**
  String get friendsContactsEmpty;

  /// No description provided for @friendsContactsLoadFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить контакты'**
  String get friendsContactsLoadFailed;

  /// No description provided for @friendsContactsNotRegistered.
  ///
  /// In ru, this message translates to:
  /// **'ещё не в Пуньк'**
  String get friendsContactsNotRegistered;

  /// No description provided for @friendsContactsChecking.
  ///
  /// In ru, this message translates to:
  /// **'проверяем…'**
  String get friendsContactsChecking;

  /// No description provided for @friendsContactsUnableToCheck.
  ///
  /// In ru, this message translates to:
  /// **'не удалось проверить'**
  String get friendsContactsUnableToCheck;

  /// No description provided for @friendsContactsFriendCountHidden.
  ///
  /// In ru, this message translates to:
  /// **'количество друзей скрыто'**
  String get friendsContactsFriendCountHidden;

  /// No description provided for @friendsContactsInvite.
  ///
  /// In ru, this message translates to:
  /// **'пригласить'**
  String get friendsContactsInvite;

  /// No description provided for @friendsContactsPermissionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Нет доступа к контактам'**
  String get friendsContactsPermissionTitle;

  /// No description provided for @friendsContactsPermissionDescription.
  ///
  /// In ru, this message translates to:
  /// **'Разрешите доступ к контактам в настройках приложения.'**
  String get friendsContactsPermissionDescription;

  /// No description provided for @friendsContactsInviteText.
  ///
  /// In ru, this message translates to:
  /// **'Я в Пуньк как @{username}. Присоединяйся!'**
  String friendsContactsInviteText(String username);

  /// No description provided for @friendsContactsInviteTextWithoutUsername.
  ///
  /// In ru, this message translates to:
  /// **'Присоединяйся ко мне в Пуньк!'**
  String get friendsContactsInviteTextWithoutUsername;

  /// No description provided for @friendsSocialTelegram.
  ///
  /// In ru, this message translates to:
  /// **'Telegram'**
  String get friendsSocialTelegram;

  /// No description provided for @friendsSocialVk.
  ///
  /// In ru, this message translates to:
  /// **'VK'**
  String get friendsSocialVk;

  /// No description provided for @friendsSocialWhatsapp.
  ///
  /// In ru, this message translates to:
  /// **'WhatsApp'**
  String get friendsSocialWhatsapp;

  /// No description provided for @friendsUserSearchHint.
  ///
  /// In ru, this message translates to:
  /// **'поиск по username'**
  String get friendsUserSearchHint;

  /// No description provided for @friendsSearchPrompt.
  ///
  /// In ru, this message translates to:
  /// **'найдите друна по username или имени'**
  String get friendsSearchPrompt;

  /// No description provided for @friendsUserSearchFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить поиск'**
  String get friendsUserSearchFailed;

  /// No description provided for @friendsAlreadyAdded.
  ///
  /// In ru, this message translates to:
  /// **'уже в друнах'**
  String get friendsAlreadyAdded;

  /// No description provided for @friendsRequestSent.
  ///
  /// In ru, this message translates to:
  /// **'заявка отправлена'**
  String get friendsRequestSent;

  /// No description provided for @friendsRequestIncoming.
  ///
  /// In ru, this message translates to:
  /// **'ответьте в заявках'**
  String get friendsRequestIncoming;

  /// No description provided for @friendsGlobalSearch.
  ///
  /// In ru, this message translates to:
  /// **'глобальный поиск'**
  String get friendsGlobalSearch;

  /// No description provided for @friendsAddTemporarilyUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Поиск на этой странице временно недоступен'**
  String get friendsAddTemporarilyUnavailable;

  /// No description provided for @friendsLocationUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Друг ещё не делился геопозицией'**
  String get friendsLocationUnavailable;

  /// No description provided for @friendsChatOpenFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть чат'**
  String get friendsChatOpenFailed;

  /// No description provided for @notificationFriendRequest.
  ///
  /// In ru, this message translates to:
  /// **'отправил(а) вам заявку в друны'**
  String get notificationFriendRequest;
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
