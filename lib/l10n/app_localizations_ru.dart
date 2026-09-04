// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get navChats => 'чатикс';

  @override
  String get navFriends => 'друны';

  @override
  String get navNearby => 'рядом';

  @override
  String get navProfile => 'акк';

  @override
  String get searchHintChats => 'поиск по чатам';

  @override
  String get chatsMessagePrefixYou => 'Ты';

  @override
  String get timeJustNow => 'только что';

  @override
  String get today => 'сегодня';

  @override
  String get timeYesterday => 'вчера';

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
  String get failedToLoadChats => 'не удалось загрузить чаты';

  @override
  String get noChats => 'у вас нет чатов';

  @override
  String get chatsNoSearchResults => 'ничего не нашли';

  @override
  String chatsDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Удалить чаты?',
      one: 'Удалить чат?',
    );
    return '$_temp0';
  }

  @override
  String chatsDeleteConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'История выбранных чатов удалится только у вас.',
      one: 'История удалится только у вас.',
    );
    return '$_temp0';
  }

  @override
  String get chatInputHint => 'введите сообщение';

  @override
  String get chatUserBlocked => 'пользователь заблокирован';

  @override
  String get chatOnlineStatus => 'в сети';

  @override
  String get chatOfflineStatus => 'не в сети';

  @override
  String chatLastSeenToday(Object time) {
    return 'был(а) в $time';
  }

  @override
  String chatLastSeenYesterday(Object time) {
    return 'был(а) вчера в $time';
  }

  @override
  String chatLastSeenDate(Object date, Object time) {
    return 'был(а) $date в $time';
  }

  @override
  String get chatAddPhoto => 'добавить фото';

  @override
  String get chatActionCamera => 'камера';

  @override
  String get chatActionGallery => 'галерея';

  @override
  String get chatActionLocation => 'локация';

  @override
  String chatSendFiles(Object count) {
    return 'отправить ($count)';
  }

  @override
  String get chatSelectFiles => 'выберите файлы';

  @override
  String get noMessages => 'тут пока ничего нет';

  @override
  String get permissionDenied => 'разрешение отклонено';

  @override
  String get youMustAllowCameraPermission =>
      'чтобы сделать фото, необходимо разрешить доступ к камере в настройках приложения.';

  @override
  String get cancel => 'отмена';

  @override
  String get settings => 'настроки';

  @override
  String get settingsTitle => 'настройки';

  @override
  String get settingsPrivacy => 'приватность';

  @override
  String get settingsVisibility => 'настройки видимости';

  @override
  String get settingsLanguage => 'язык';

  @override
  String get settingsHelp => 'помощь';

  @override
  String get settingsAbout => 'о приложении';

  @override
  String get settingsSocial => 'мы в соцсетях';

  @override
  String get settingsLogout => 'выход';

  @override
  String get settingsLogoutConfirmationTitle => 'выйти из аккаунта?';

  @override
  String get settingsLogoutConfirmationContent =>
      'вы уверены, что хотите выйти из аккаунта?';

  @override
  String get settingsLogoutConfirm => 'выйти';

  @override
  String get settingsDeleteAccount => 'удалить аккаунт';

  @override
  String get settingsBlacklist => 'чёрный список';

  @override
  String get settingsSearchByUsername => 'искать по никнейму';

  @override
  String get settingsSearchByPhone => 'искать по номеру';

  @override
  String get settingsSearchByName => 'искать по имени';

  @override
  String get settingsLastSeenVisibility => 'отображение времени захода';

  @override
  String get settingsLastSeenAll => 'все';

  @override
  String get settingsLastSeenFriends => 'только друзья';

  @override
  String get settingsLastSeenNobody => 'никто';

  @override
  String get settingsPrivacyChangeTitle => 'изменить видимость поиска?';

  @override
  String get settingsPrivacyChangeContent =>
      'Это изменит, смогут ли другие пользователи найти вас этим способом. Текущие друзья по-прежнему будут вас видеть.';

  @override
  String get settingsPrivacyChangeConfirm => 'изменить';

  @override
  String get settingsPrivacySaved => 'настройка приватности сохранена';

  @override
  String get settingsPrivacySaveFailed =>
      'не удалось сохранить настройку приватности';

  @override
  String get settingsPrivacyLoadFailed =>
      'не удалось загрузить настройки приватности';

  @override
  String get settingsShareLocation => 'делиться гео';

  @override
  String get settingsShareDistance => 'показывать расстояние';

  @override
  String get settingsFriendsSeeGeo => 'видят твоё точное гео';

  @override
  String get settingsLanguageRussian => 'русский';

  @override
  String get settingsLanguageEnglish => 'english';

  @override
  String get settingsLanguageSaved => 'язык сохранён';

  @override
  String get settingsLanguageSaveFailed => 'не удалось сохранить язык';

  @override
  String get settingsSupportEmail => 'написать на почту';

  @override
  String get settingsCopyEmail => 'скопировать почту';

  @override
  String get settingsEmailCopied => 'почта скопирована';

  @override
  String get settingsPublicContentUnavailable => 'информация пока недоступна';

  @override
  String get settingsSearchBlacklist => 'поиск';

  @override
  String get settingsNobodyHere => 'тут никого нет';

  @override
  String get settingsBlacklistLoadFailed =>
      'не удалось загрузить черный список';

  @override
  String get settingsComingSoon => 'скоро';

  @override
  String get settingsTerms => 'условия обслуживания';

  @override
  String get settingsPrivacyPolicy => 'политика конфиденциальности';

  @override
  String get photoHasBeenSavedToGallery => 'фото сохранено в галерею';

  @override
  String get failedToSavePhoto => 'Не удалось сохранить фото';

  @override
  String get repeat => 'Пповторить';

  @override
  String locationConfirmation(Object name) {
    return 'Вы точно хотите отправить своё местоположение пользователю $name?';
  }

  @override
  String get locationConfirmationDescription => 'Поделиться местоположением?';

  @override
  String get locationShare => 'Отправить';

  @override
  String get locationDisabled => 'Геолокация выключена';

  @override
  String get locationEnableDescription =>
      'Включите геолокацию в настройках устройства, чтобы отправить местоположение.';

  @override
  String get locationPermissionDenied => 'Нет доступа к геолокации';

  @override
  String get locationPermissionSettingsDescription =>
      'Разрешите доступ к геолокации в настройках приложения.';

  @override
  String get notificationsPermissionReminderTitle => 'Включите уведомления';

  @override
  String get notificationsPermissionReminderContent =>
      'Разрешите уведомления в настройках, чтобы не пропускать сообщения и заявки в друны.';

  @override
  String get locationPermissionReminderTitle => 'Разрешите геолокацию';

  @override
  String get locationPermissionReminderContent =>
      'Разрешите доступ к геолокации, чтобы друны могли видеть ваше последнее местоположение.';

  @override
  String get locationServiceReminderContent =>
      'Включите геолокацию на устройстве, чтобы друны могли видеть ваше последнее местоположение.';

  @override
  String get locationMessageYou => 'Вы поделились местоположением';

  @override
  String get locationMessageIncoming => 'Вам отправили местоположение';

  @override
  String get locationOpenError => 'Не удалось открыть приложение с картой';

  @override
  String get microphonePermissionDenied => 'Нет доступа к микрофону';

  @override
  String get microphonePermissionSettingsDescription =>
      'Разрешите доступ к микрофону в настройках приложения, чтобы записывать голосовые сообщения.';

  @override
  String get voiceRecordingExitTitle => 'Сбросить голосовое сообщение?';

  @override
  String get voiceRecordingExitDescription =>
      'Запись будет удалена без возможности восстановления.';

  @override
  String get chatActionCopy => 'Копировать';

  @override
  String get chatActionDelete => 'Удалить';

  @override
  String get chatActionReply => 'Ответить';

  @override
  String chatReplyingTo(Object name) {
    return 'В ответ $name';
  }

  @override
  String get chatReplyYou => 'Вы';

  @override
  String get chatReplyPhoto => 'Фотография';

  @override
  String get chatReplyAudio => 'Аудиосообщение';

  @override
  String get chatReplyLocation => 'Местоположение';

  @override
  String readReceiptToday(Object time) {
    return 'Прочитано сегодня в $time';
  }

  @override
  String readReceiptYesterday(Object time) {
    return 'Прочитано вчера в $time';
  }

  @override
  String readReceiptDate(Object date, Object time) {
    return 'Прочитано $date в $time';
  }

  @override
  String get voiceRecordingExitStay => 'Остаться';

  @override
  String get voiceRecordingExitDiscard => 'Сбросить';

  @override
  String get authWelcomeTitle => 'Добро пожаловать';

  @override
  String get authSignInWith => 'Войти с помощью';

  @override
  String get authWelcomeDescription =>
      'Общайтесь, делитесь моментами и оставайтесь на связи с близкими.';

  @override
  String get authContinueWithYandex => 'Продолжить с Яндекс ID';

  @override
  String get authConsentHint =>
      'При первом входе мы перенесём доступные данные профиля из Яндекс ID.';

  @override
  String get authConsentPrefix => 'При входе и регистрации вы принимаете наши';

  @override
  String get authSignInFailed =>
      'Не удалось войти через Яндекс ID. Попробуйте ещё раз.';

  @override
  String get authProfileSetupTitle => 'Завершение регистрации';

  @override
  String get authProfileSetupDescription =>
      'Проверьте данные из Яндекс ID и заполните недостающие поля.';

  @override
  String get authOnboardingNameTitle => 'как тебя зовут?';

  @override
  String get authOnboardingBirthDateTitle => 'а когда др?';

  @override
  String get authOnboardingBirthDateHint => 'покажем только возраст';

  @override
  String get authOnboardingGenderTitle => 'кто ты?';

  @override
  String get authOnboardingAvatarTitle => 'добавим аву?';

  @override
  String get authOnboardingUsernameTitle => 'придумай тег.';

  @override
  String get authOnboardingUsernameHint => 'это уникальное имя пользователя';

  @override
  String get authOnboardingBioTitle => 'напиши о себе';

  @override
  String get authOnboardingBioLabel => 'о себе';

  @override
  String get authOnboardingBioHint => 'напишите немного о себе';

  @override
  String get authOnboardingSkip => 'скип';

  @override
  String get authOnboardingReset => 'Сбросить';

  @override
  String get authAddImage => 'Добавить изображение';

  @override
  String get authOnboardingComplete => 'Завершить';

  @override
  String get authBirthDateDay => 'ДД';

  @override
  String get authBirthDateMonth => 'ММ';

  @override
  String get authBirthDateYear => 'ГГГГ';

  @override
  String get authDisplayNameLabel => 'имя';

  @override
  String get authDisplayNameHint => 'как тебя звать?';

  @override
  String get authInputTooLong => 'слишком длинный';

  @override
  String get authUsernameLabel => 'Username';

  @override
  String get authUsernameHelper =>
      'От 3 до 24 латинских букв, цифр или _. Можно оставить автоматически созданный.';

  @override
  String get authBirthDateLabel => 'Дата рождения';

  @override
  String get authBirthDatePlaceholder => 'Выберите дату';

  @override
  String get authAcceptDocuments => 'Я принимаю условия использования сервиса';

  @override
  String get authTermsOfService => 'Условия обслуживания';

  @override
  String get authDocumentsAnd => 'и';

  @override
  String get authPrivacyPolicy => 'Политику конфиденциальности';

  @override
  String get authCompleteRegistration => 'Завершить регистрацию';

  @override
  String get authNameRequired => 'Укажите имя';

  @override
  String get authNameInvalid => 'Имя должно содержать от 2 до 30 символов';

  @override
  String get authBirthDateRequired => 'Укажите дату рождения';

  @override
  String get authBirthDateInvalid =>
      'Введите корректную дату рождения. Вам должно быть не менее 14 лет.';

  @override
  String get authDocumentsRequired =>
      'Необходимо принять соглашение и политику конфиденциальности';

  @override
  String get authUsernameTaken => 'Этот username уже занят';

  @override
  String get authUsernameInvalid =>
      'Username должен содержать от 3 до 24 латинских букв, цифр или _';

  @override
  String get authUsernameCharactersOnly => 'только a-z, 0-9 и _';

  @override
  String get authUsernameTooShort => 'минимум 3 символа';

  @override
  String get authProfileSaveFailed =>
      'Не удалось сохранить профиль. Попробуйте ещё раз.';

  @override
  String get authLoadFailedTitle => 'Не удалось загрузить профиль';

  @override
  String get authLoadFailedDescription =>
      'Проверьте подключение и повторите попытку.';

  @override
  String get authSignOut => 'Выйти';

  @override
  String get authBannedTitle => 'Пользователь забанен';

  @override
  String get authBannedDescription => 'Доступ к приложению ограничен.';

  @override
  String authBannedSupport(String email) {
    return 'Если вы считаете это ошибкой, напишите в поддержку: $email';
  }

  @override
  String get authBack => 'Назад';

  @override
  String get notificationsChannelName => 'Сообщения';

  @override
  String get notificationsChannelDescription => 'Новые сообщения в чатах';

  @override
  String get notificationYou => 'Ты';

  @override
  String get notificationAppTitle => 'Yap chat';

  @override
  String get notificationNewMessage => 'Новое сообщение';

  @override
  String get notificationNewFriendRequest => 'Новая заявка в друны';

  @override
  String get notificationPhoto => 'Фотография';

  @override
  String get notificationAudio => 'Голосовое сообщение';

  @override
  String get notificationLocation => 'Местоположение';

  @override
  String get chatsNotificationsEnabled => 'Уведомления включены';

  @override
  String get chatsNotificationsDisabled => 'Уведомления отключены';

  @override
  String get chatsActionCompleted => 'Действие выполнено';

  @override
  String get chatsActionFailed =>
      'Не удалось выполнить действие. Проверьте подключение к интернету';

  @override
  String get newChatTitle => 'написать';

  @override
  String get newChatFindUser => 'найти пользователя';

  @override
  String get friendsTabFriends => 'друны';

  @override
  String get friendsTabRequests => 'заявки';

  @override
  String get friendsAll => 'все друны';

  @override
  String get friendsOutgoing => 'исходящие';

  @override
  String get friendsIncoming => 'входящие';

  @override
  String get friendsSearchHint => 'поиск';

  @override
  String get friendsEmpty => 'друзей пока нет, воспользуйтесь кнопкой сверху';

  @override
  String get friendsRequestsEmpty => 'заявок пока нет';

  @override
  String get friendsNoSearchResults => 'ничего не нашли';

  @override
  String get friendsLoadFailed => 'Не удалось загрузить друнов';

  @override
  String get friendsActionFailed => 'Не удалось выполнить действие';

  @override
  String get friendsCancelRequest => 'отменить';

  @override
  String friendsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count друзей',
      many: '$count друзей',
      few: '$count друга',
      one: '$count друг',
    );
    return '$_temp0';
  }

  @override
  String get friendsAddTitle => 'добавить';

  @override
  String get friendsAddContacts => 'из контактов';

  @override
  String get friendsAddByUsername => 'поиск по никнейму';

  @override
  String get friendsAddByUsernameTitle => 'добавить по никнейму';

  @override
  String get friendsUsernameLabel => 'никнейм';

  @override
  String get friendsUsernameHint => 'введи никнейм';

  @override
  String get friendsUsernameSearch => 'искать';

  @override
  String get friendsUsernameNotFound => 'не удалось найти';

  @override
  String get friendsUsernameTooLong => 'никнейм слишком длинный';

  @override
  String get friendsUsernameCharactersOnly => 'только a-z, 0-9 и _';

  @override
  String get friendsAddByPhone => 'по номеру телефона';

  @override
  String get friendsAddByPhoneTitle => 'добавить по номеру телефона';

  @override
  String get friendsPhoneLabel => 'номер телефона';

  @override
  String get friendsPhoneHint => 'введи номер телефона';

  @override
  String get friendsPhoneTooLong => 'номер слишком длинный';

  @override
  String get friendsPhoneInvalid => 'введите корректный номер';

  @override
  String get friendsAddInviteMore => 'позови ещё больше друзей';

  @override
  String get friendsAddSocialNetworks => 'из соцсетей';

  @override
  String get friendsAddComingSoon => 'скоро';

  @override
  String get friendsContactsTitle => 'контакты';

  @override
  String get friendsContactsEmpty =>
      'в адресной книге нет контактов с номерами';

  @override
  String get friendsContactsLoadFailed => 'Не удалось загрузить контакты';

  @override
  String get friendsContactsNotRegistered => 'ещё не в Пуньк';

  @override
  String get friendsContactsChecking => 'проверяем…';

  @override
  String get friendsContactsUnableToCheck => 'не удалось проверить';

  @override
  String get friendsContactsFriendCountHidden => 'количество друзей скрыто';

  @override
  String get friendsContactsInvite => 'пригласить';

  @override
  String get friendsContactsPermissionTitle => 'Нет доступа к контактам';

  @override
  String get friendsContactsPermissionDescription =>
      'Разрешите доступ к контактам в настройках приложения.';

  @override
  String friendsContactsInviteText(String username) {
    return 'Я в Пуньк как @$username. Присоединяйся!';
  }

  @override
  String get friendsContactsInviteTextWithoutUsername =>
      'Присоединяйся ко мне в Пуньк!';

  @override
  String get friendsSocialTelegram => 'Telegram';

  @override
  String get friendsSocialVk => 'VK';

  @override
  String get friendsSocialWhatsapp => 'WhatsApp';

  @override
  String get friendsUserSearchHint => 'поиск по username';

  @override
  String get friendsSearchPrompt => 'найдите друна по username или имени';

  @override
  String get friendsUserSearchFailed => 'Не удалось выполнить поиск';

  @override
  String get friendsAlreadyAdded => 'уже в друнах';

  @override
  String get friendsRequestSent => 'заявка отправлена';

  @override
  String get friendsRequestIncoming => 'ответьте в заявках';

  @override
  String get friendsGlobalSearch => 'глобальный поиск';

  @override
  String get friendsAddTemporarilyUnavailable =>
      'Поиск на этой странице временно недоступен';

  @override
  String get friendsLocationUnavailable => 'Друг ещё не делился геопозицией';

  @override
  String get friendsChatOpenFailed => 'Не удалось открыть чат';

  @override
  String get notificationFriendRequest => 'отправил(а) вам заявку в друны';

  @override
  String get profileEditTitle => 'Редактирование';

  @override
  String get profileSave => 'Сохранить';

  @override
  String get profileUsernameLabel => 'никнейм';

  @override
  String get profileUsernameHint => 'введите никнейм';

  @override
  String get profileNameLabel => 'имя';

  @override
  String get profileNameHint => 'как тебя звать?';

  @override
  String get profileBioLabel => 'био';

  @override
  String get profileBioHint => 'напишите немного о себе';

  @override
  String get profileGenderLabel => 'Пол';

  @override
  String get profileBirthDateLabel => 'Дата рождения';

  @override
  String get profileGenderTitle => 'Кто ты?';

  @override
  String get profileGenderMale => 'мужской';

  @override
  String get profileGenderFemale => 'женский';

  @override
  String get profileGenderUnspecified => 'не указан';

  @override
  String get profileBirthDateTitle => 'Ты родился…';

  @override
  String get profileMainPhoto => 'главное';

  @override
  String get profileCropTitle => 'Обрезать фото';

  @override
  String get profileCropApply => 'подтвердить';

  @override
  String get profileUnsavedTitle => 'Сохранить изменения?';

  @override
  String get profileUnsavedDescription =>
      'В профиле есть несохранённые изменения.';

  @override
  String get profileStay => 'Остаться';

  @override
  String get profileDiscard => 'Выйти';

  @override
  String profilePhotoCounter(int current, int total) {
    return '$current из $total';
  }

  @override
  String profileDaysWithUs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дня с нами',
      many: '$count дней с нами',
      few: '$count дня с нами',
      one: '$count день с нами',
    );
    return '$_temp0';
  }

  @override
  String get viewedProfileLoadFailed => 'Не удалось загрузить профиль';

  @override
  String get viewedProfileOpenChat => 'открыть чат';

  @override
  String get viewedProfileWrite => 'написать';

  @override
  String get viewedProfileAddFriend => 'добавить';

  @override
  String get viewedProfileRequestSent => 'отправлено';

  @override
  String get viewedProfileCancelRequestTitle => 'Отменить заявку?';

  @override
  String get viewedProfileCancelRequestContent =>
      'Пользователь больше не увидит эту заявку в друны.';

  @override
  String get viewedProfileRemoveFriend => 'Удалить из друнов';

  @override
  String get viewedProfileRemoveFriendTitle => 'Удалить из друнов?';

  @override
  String viewedProfileRemoveFriendContent(String name) {
    return 'Удалить $name из друнов?';
  }

  @override
  String get viewedProfileMute => 'Убрать звук';

  @override
  String get viewedProfileUnmute => 'Включить звук';

  @override
  String get viewedProfileBlock => 'Заблокировать';

  @override
  String get viewedProfileBlockTitle => 'Заблокировать пользователя?';

  @override
  String viewedProfileBlockContent(Object name) {
    return '$name не сможет просматривать ваш профиль, видеть статус и местоположение или писать вам.';
  }

  @override
  String get unblockUser => 'Разблокировать';

  @override
  String get unblockUserTitle => 'Разблокировать пользователя?';

  @override
  String unblockUserContent(Object name) {
    return '$name снова сможет найти ваш профиль и отправлять новые сообщения.';
  }

  @override
  String get viewedProfileReport => 'Пожаловаться';

  @override
  String get viewedProfileReportSpam => 'Спам';

  @override
  String get viewedProfileReportScam => 'Мошенничество';

  @override
  String get viewedProfileReportPornography => 'Порнография';

  @override
  String get viewedProfileReportOther => 'Другое';

  @override
  String get viewedProfileReportAccepted => 'Жалоба принята';

  @override
  String get viewedProfileReportRateLimited =>
      'Сейчас нельзя отправить ещё одну жалобу на этого пользователя';

  @override
  String get viewedProfileReportSending => 'Жалоба уже отправляется';

  @override
  String get viewedProfileReportBlockTitle => 'Заблокировать пользователя?';

  @override
  String viewedProfileReportBlockContent(Object name) {
    return '$name не сможет просматривать ваш профиль, видеть статус и местоположение или писать вам.';
  }

  @override
  String viewedProfileDistanceMeters(int value) {
    return '$value м';
  }

  @override
  String viewedProfileDistanceKilometers(int value) {
    return '$value км';
  }

  @override
  String get viewedProfileUsernameCopied => 'Никнейм скопирован';

  @override
  String viewedProfileUserFriends(String name) {
    return 'Друны $name';
  }

  @override
  String get viewedProfileNoFriends => 'нет друзей';

  @override
  String get viewedProfileFriendIsYou => 'друг это я';

  @override
  String get nearbyTitle => 'люди рядом';

  @override
  String get nearbyFilters => 'фильтры';

  @override
  String get nearbyAge => 'возраст';

  @override
  String get nearbyAgeFrom => 'от';

  @override
  String get nearbyAgeTo => 'до';

  @override
  String get nearbyAgeInvalid =>
      'Введите возраст от 18 до 99 лет: значение «от» не должно быть больше «до».';

  @override
  String get nearbyAgeInvalidShort => 'от 18 до 99';

  @override
  String get nearbyApply => 'применить';

  @override
  String get nearbyEmpty => 'рядом пока никого нет';

  @override
  String get nearbyLoadFailed => 'не удалось загрузить людей рядом';

  @override
  String get nearbyLocationRequiredTitle => 'Нужна геолокация';

  @override
  String get nearbyLocationRequiredContent =>
      'Поделитесь актуальной геопозицией, чтобы увидеть людей рядом.';

  @override
  String get nearbyLocationUpdate => 'обновить геолокацию';

  @override
  String get nearbyLocationUpdateShort => 'обновить';

  @override
  String get nearbyLocationUnavailable =>
      'Не удалось получить геолокацию. Попробуйте ещё раз.';

  @override
  String get nearbyRateLimited =>
      'Слишком много обновлений. Попробуйте через минуту.';
}
