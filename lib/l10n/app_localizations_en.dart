// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navChats => 'Chats';

  @override
  String get navFriends => 'Friends';

  @override
  String get navProfile => 'Profile';

  @override
  String get searchHintChats => 'search chats';

  @override
  String get chatsMessagePrefixYou => 'You';

  @override
  String get timeJustNow => 'Just now';

  @override
  String get today => 'Today';

  @override
  String get timeYesterday => 'Yesterday';

  @override
  String timeMinutesAgo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mins ago',
      one: '$count min ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '$count hour ago',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '$count day ago',
    );
    return '$_temp0';
  }

  @override
  String get failedToLoadChats => 'Failed to load chats';

  @override
  String get noChats => 'You have no chats';

  @override
  String get chatsNoSearchResults => 'Nothing found';

  @override
  String chatsDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete chats?',
      one: 'Delete chat?',
    );
    return '$_temp0';
  }

  @override
  String chatsDeleteConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The selected histories will be deleted only for you.',
      one: 'The history will be deleted only for you.',
    );
    return '$_temp0';
  }

  @override
  String get chatInputHint => 'Type a message';

  @override
  String get chatOnlineStatus => 'Online';

  @override
  String get chatOfflineStatus => 'Offline';

  @override
  String chatLastSeenToday(Object time) {
    return 'Last seen at $time';
  }

  @override
  String chatLastSeenYesterday(Object time) {
    return 'Last seen yesterday at $time';
  }

  @override
  String chatLastSeenDate(Object date, Object time) {
    return 'Last seen $date at $time';
  }

  @override
  String get chatAddPhoto => 'Add photo';

  @override
  String get chatActionCamera => 'Camera';

  @override
  String get chatActionGallery => 'Gallery';

  @override
  String get chatActionLocation => 'Location';

  @override
  String chatSendFiles(Object count) {
    return 'Send ($count)';
  }

  @override
  String get chatSelectFiles => 'Select files';

  @override
  String get noMessages => 'nothing here yet';

  @override
  String get permissionDenied => 'Permission denied';

  @override
  String get youMustAllowCameraPermission =>
      'To take a photo, you must allow access to the camera in the app settings.';

  @override
  String get cancel => 'Cancel';

  @override
  String get settings => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsVisibility => 'Visibility settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsAbout => 'About the app';

  @override
  String get settingsSocial => 'We are on social media';

  @override
  String get settingsLogout => 'Log out';

  @override
  String get settingsLogoutConfirmationTitle => 'Log out?';

  @override
  String get settingsLogoutConfirmationContent =>
      'Are you sure you want to log out of your account?';

  @override
  String get settingsLogoutConfirm => 'Log out';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsBlacklist => 'Blocked users';

  @override
  String get settingsSearchByUsername => 'Find by username';

  @override
  String get settingsSearchByPhone => 'Find by phone number';

  @override
  String get settingsSearchByName => 'Find by name';

  @override
  String get settingsLastSeenVisibility => 'last seen visibility';

  @override
  String get settingsLastSeenAll => 'Everyone';

  @override
  String get settingsLastSeenFriends => 'Friends only';

  @override
  String get settingsLastSeenNobody => 'Nobody';

  @override
  String get settingsPrivacyChangeTitle => 'Change search visibility?';

  @override
  String get settingsPrivacyChangeContent =>
      'This changes whether other users can find you using this method. Your current friends will still see you.';

  @override
  String get settingsPrivacyChangeConfirm => 'Change';

  @override
  String get settingsPrivacySaved => 'Privacy setting saved';

  @override
  String get settingsPrivacySaveFailed => 'Could not save privacy setting';

  @override
  String get settingsPrivacyLoadFailed => 'Could not load privacy settings';

  @override
  String get settingsShareLocation => 'Share my location';

  @override
  String get settingsShareDistance => 'Show distance';

  @override
  String get settingsFriendsSeeGeo => 'see your exact location';

  @override
  String get settingsLanguageRussian => 'русский';

  @override
  String get settingsLanguageEnglish => 'english';

  @override
  String get settingsLanguageSaved => 'Language saved';

  @override
  String get settingsLanguageSaveFailed => 'Could not save language';

  @override
  String get settingsSearchBlacklist => 'search';

  @override
  String get settingsNobodyHere => 'nobody here';

  @override
  String get settingsComingSoon => 'coming soon';

  @override
  String get settingsTerms => 'Terms of service';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get photoHasBeenSavedToGallery => 'Photo has been saved to gallery';

  @override
  String get failedToSavePhoto => 'Failed to save photo';

  @override
  String get repeat => 'Repeat';

  @override
  String locationConfirmation(Object name) {
    return 'Are you sure you want to send your location to $name?';
  }

  @override
  String get locationConfirmationDescription => 'Share location?';

  @override
  String get locationShare => 'Send';

  @override
  String get locationDisabled => 'Location is disabled';

  @override
  String get locationEnableDescription =>
      'Enable location in device settings to share your position.';

  @override
  String get locationPermissionDenied => 'Location access denied';

  @override
  String get locationPermissionSettingsDescription =>
      'Allow location access in the app settings.';

  @override
  String get notificationsPermissionReminderTitle => 'Enable notifications';

  @override
  String get notificationsPermissionReminderContent =>
      'Allow notifications in Settings so you don\'t miss messages and friend requests.';

  @override
  String get locationPermissionReminderTitle => 'Allow location access';

  @override
  String get locationPermissionReminderContent =>
      'Allow location access so friends can see your latest location.';

  @override
  String get locationServiceReminderContent =>
      'Enable location services so friends can see your latest location.';

  @override
  String get locationMessageYou => 'You shared your location';

  @override
  String get locationMessageIncoming => 'You received a location';

  @override
  String get locationOpenError => 'Unable to open a map application';

  @override
  String get microphonePermissionDenied => 'Microphone access denied';

  @override
  String get microphonePermissionSettingsDescription =>
      'Allow microphone access in the app settings to record voice messages.';

  @override
  String get voiceRecordingExitTitle => 'Discard voice message?';

  @override
  String get voiceRecordingExitDescription =>
      'The recording will be deleted and cannot be restored.';

  @override
  String get chatActionCopy => 'Copy';

  @override
  String get chatActionDelete => 'Delete';

  @override
  String get chatActionReply => 'Reply';

  @override
  String chatReplyingTo(Object name) {
    return 'Replying to $name';
  }

  @override
  String get chatReplyYou => 'You';

  @override
  String get chatReplyPhoto => 'Photo';

  @override
  String get chatReplyAudio => 'Audio message';

  @override
  String get chatReplyLocation => 'Location';

  @override
  String readReceiptToday(Object time) {
    return 'Read today at $time';
  }

  @override
  String readReceiptYesterday(Object time) {
    return 'Read yesterday at $time';
  }

  @override
  String readReceiptDate(Object date, Object time) {
    return 'Read $date at $time';
  }

  @override
  String get voiceRecordingExitStay => 'Stay';

  @override
  String get voiceRecordingExitDiscard => 'Discard';

  @override
  String get authWelcomeTitle => 'Welcome';

  @override
  String get authSignInWith => 'Sign in with';

  @override
  String get authWelcomeDescription =>
      'Chat, share moments, and stay connected with the people who matter.';

  @override
  String get authContinueWithYandex => 'Continue with Yandex ID';

  @override
  String get authConsentHint =>
      'On your first sign-in, we will import available profile data from Yandex ID.';

  @override
  String get authConsentPrefix =>
      'By signing in and registering, you accept our';

  @override
  String get authSignInFailed =>
      'Could not sign in with Yandex ID. Please try again.';

  @override
  String get authProfileSetupTitle => 'Complete registration';

  @override
  String get authProfileSetupDescription =>
      'Review the data from Yandex ID and fill in the missing fields.';

  @override
  String get authOnboardingNameTitle => 'what\'s your name?';

  @override
  String get authOnboardingBirthDateTitle => 'when is your birthday?';

  @override
  String get authOnboardingBirthDateHint => 'we\'ll only show your age';

  @override
  String get authOnboardingGenderTitle => 'who are you?';

  @override
  String get authOnboardingAvatarTitle => 'add an avatar?';

  @override
  String get authOnboardingUsernameTitle => 'choose a username.';

  @override
  String get authOnboardingUsernameHint => 'this is your unique username';

  @override
  String get authOnboardingBioTitle => 'tell us about yourself';

  @override
  String get authOnboardingBioLabel => 'about me';

  @override
  String get authOnboardingBioHint => 'tell us a little about yourself';

  @override
  String get authOnboardingSkip => 'Skip';

  @override
  String get authOnboardingReset => 'Reset';

  @override
  String get authAddImage => 'Add image';

  @override
  String get authOnboardingComplete => 'Finish';

  @override
  String get authBirthDateDay => 'dd';

  @override
  String get authBirthDateMonth => 'mm';

  @override
  String get authBirthDateYear => 'yyyy';

  @override
  String get authDisplayNameLabel => 'name';

  @override
  String get authDisplayNameHint => 'enter your name';

  @override
  String get authInputTooLong => 'too long';

  @override
  String get authUsernameLabel => 'Username';

  @override
  String get authUsernameHelper =>
      'Use 3–24 Latin letters, digits, or _. You may keep the generated username.';

  @override
  String get authBirthDateLabel => 'Date of birth';

  @override
  String get authBirthDatePlaceholder => 'Select a date';

  @override
  String get authAcceptDocuments => 'I accept the terms of service';

  @override
  String get authTermsOfService => 'Terms of Service';

  @override
  String get authDocumentsAnd => 'and';

  @override
  String get authPrivacyPolicy => 'Privacy Policy';

  @override
  String get authCompleteRegistration => 'Complete registration';

  @override
  String get authNameRequired => 'Enter your name';

  @override
  String get authNameInvalid => 'Name must contain 2–30 characters';

  @override
  String get authBirthDateRequired => 'Enter your date of birth';

  @override
  String get authBirthDateInvalid =>
      'Enter a valid date of birth. You must be at least 14 years old.';

  @override
  String get authDocumentsRequired =>
      'You must accept the Terms of Service and Privacy Policy';

  @override
  String get authUsernameTaken => 'This username is already taken';

  @override
  String get authUsernameInvalid =>
      'Username must contain 3–24 Latin letters, digits, or _';

  @override
  String get authUsernameCharactersOnly => 'only a-z, 0-9, and _';

  @override
  String get authUsernameTooShort => 'at least 3 characters';

  @override
  String get authProfileSaveFailed =>
      'Could not save your profile. Please try again.';

  @override
  String get authLoadFailedTitle => 'Could not load your profile';

  @override
  String get authLoadFailedDescription =>
      'Check your connection and try again.';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authBack => 'Back';

  @override
  String get notificationsChannelName => 'Messages';

  @override
  String get notificationsChannelDescription => 'New chat messages';

  @override
  String get notificationYou => 'You';

  @override
  String get notificationAppTitle => 'Yap chat';

  @override
  String get notificationNewMessage => 'New message';

  @override
  String get notificationNewFriendRequest => 'New friend request';

  @override
  String get notificationPhoto => 'Photo';

  @override
  String get notificationAudio => 'Voice message';

  @override
  String get notificationLocation => 'Location';

  @override
  String get chatsNotificationsEnabled => 'Notifications enabled';

  @override
  String get chatsNotificationsDisabled => 'Notifications disabled';

  @override
  String get chatsActionCompleted => 'Action completed';

  @override
  String get chatsActionFailed =>
      'Could not complete the action. Check your internet connection';

  @override
  String get newChatTitle => 'write';

  @override
  String get newChatFindUser => 'find a user';

  @override
  String get friendsTabFriends => 'friends';

  @override
  String get friendsTabRequests => 'requests';

  @override
  String get friendsAll => 'all friends';

  @override
  String get friendsOutgoing => 'outgoing';

  @override
  String get friendsIncoming => 'incoming';

  @override
  String get friendsSearchHint => 'search';

  @override
  String get friendsEmpty =>
      'you don\'t have any friends yet, use the button above';

  @override
  String get friendsRequestsEmpty => 'no requests yet';

  @override
  String get friendsNoSearchResults => 'nothing found';

  @override
  String get friendsLoadFailed => 'Unable to load friends';

  @override
  String get friendsActionFailed => 'Unable to complete the action';

  @override
  String get friendsCancelRequest => 'cancel';

  @override
  String friendsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count friends',
      one: '$count friend',
    );
    return '$_temp0';
  }

  @override
  String get friendsAddTitle => 'add friends';

  @override
  String get friendsAddContacts => 'from contacts';

  @override
  String get friendsAddByUsername => 'search by username';

  @override
  String get friendsAddByUsernameTitle => 'add by username';

  @override
  String get friendsUsernameLabel => 'username';

  @override
  String get friendsUsernameHint => 'enter a username';

  @override
  String get friendsUsernameSearch => 'search';

  @override
  String get friendsUsernameNotFound => 'couldn\'t find a user';

  @override
  String get friendsUsernameTooLong => 'username is too long';

  @override
  String get friendsUsernameCharactersOnly => 'only a-z, 0-9, and _';

  @override
  String get friendsAddByPhone => 'by phone number';

  @override
  String get friendsAddByPhoneTitle => 'add by phone number';

  @override
  String get friendsPhoneLabel => 'phone number';

  @override
  String get friendsPhoneHint => 'enter a phone number';

  @override
  String get friendsPhoneTooLong => 'phone number is too long';

  @override
  String get friendsPhoneInvalid => 'enter a valid phone number';

  @override
  String get friendsAddInviteMore => 'invite even more friends';

  @override
  String get friendsAddSocialNetworks => 'from social networks';

  @override
  String get friendsAddComingSoon => 'coming soon';

  @override
  String get friendsContactsTitle => 'contacts';

  @override
  String get friendsContactsEmpty => 'there are no contacts with phone numbers';

  @override
  String get friendsContactsLoadFailed => 'Unable to load contacts';

  @override
  String get friendsContactsNotRegistered => 'not yet in Yapchat';

  @override
  String get friendsContactsChecking => 'checking…';

  @override
  String get friendsContactsUnableToCheck => 'unable to check';

  @override
  String get friendsContactsFriendCountHidden => 'friend count is hidden';

  @override
  String get friendsContactsInvite => 'invite';

  @override
  String get friendsContactsPermissionTitle => 'Contacts access denied';

  @override
  String get friendsContactsPermissionDescription =>
      'Allow contacts access in the app settings.';

  @override
  String friendsContactsInviteText(String username) {
    return 'I\'m on Yapchat as @$username. Join me!';
  }

  @override
  String get friendsContactsInviteTextWithoutUsername => 'Join me on Yapchat!';

  @override
  String get friendsSocialTelegram => 'Telegram';

  @override
  String get friendsSocialVk => 'VK';

  @override
  String get friendsSocialWhatsapp => 'WhatsApp';

  @override
  String get friendsUserSearchHint => 'search by username';

  @override
  String get friendsSearchPrompt => 'find a friend by username or name';

  @override
  String get friendsUserSearchFailed => 'Unable to search';

  @override
  String get friendsAlreadyAdded => 'already a friend';

  @override
  String get friendsRequestSent => 'request sent';

  @override
  String get friendsRequestIncoming => 'respond in requests';

  @override
  String get friendsGlobalSearch => 'global search';

  @override
  String get friendsAddTemporarilyUnavailable =>
      'Search on this page is temporarily unavailable';

  @override
  String get friendsLocationUnavailable =>
      'This friend hasn\'t shared a location yet';

  @override
  String get friendsChatOpenFailed => 'Unable to open chat';

  @override
  String get notificationFriendRequest => 'sent you a friend request';

  @override
  String get profileEditTitle => 'Edit profile';

  @override
  String get profileSave => 'Save';

  @override
  String get profileUsernameLabel => 'username';

  @override
  String get profileUsernameHint => 'enter a username';

  @override
  String get profileNameLabel => 'name';

  @override
  String get profileNameHint => 'what should we call you?';

  @override
  String get profileBioLabel => 'bio';

  @override
  String get profileBioHint => 'tell us a little about yourself';

  @override
  String get profileGenderLabel => 'Gender';

  @override
  String get profileBirthDateLabel => 'Date of birth';

  @override
  String get profileGenderTitle => 'Who are you?';

  @override
  String get profileGenderMale => 'male';

  @override
  String get profileGenderFemale => 'female';

  @override
  String get profileGenderUnspecified => 'not specified';

  @override
  String get profileBirthDateTitle => 'You were born…';

  @override
  String get profileMainPhoto => 'main';

  @override
  String get profileCropTitle => 'Crop photo';

  @override
  String get profileCropApply => 'confirm';

  @override
  String get profileUnsavedTitle => 'Save changes?';

  @override
  String get profileUnsavedDescription => 'Your profile has unsaved changes.';

  @override
  String get profileStay => 'Stay';

  @override
  String get profileDiscard => 'Exit';

  @override
  String profilePhotoCounter(int current, int total) {
    return '$current of $total';
  }

  @override
  String profileDaysWithUs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days with us',
      one: '$count day with us',
    );
    return '$_temp0';
  }
}
