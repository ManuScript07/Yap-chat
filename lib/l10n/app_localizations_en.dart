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
  String get notificationPhoto => 'Photo';

  @override
  String get notificationAudio => 'Voice message';

  @override
  String get notificationLocation => 'Location';

  @override
  String get chatsNotificationsEnabled => 'Notifications enabled';

  @override
  String get chatsNotificationsDisabled => 'Notifications disabled';
}
