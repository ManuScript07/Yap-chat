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
  String get chatsMessagePrefixYou => 'Ты';

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
  String get chatInputHint => 'Type a message';

  @override
  String get chatOnlineStatus => 'Online';

  @override
  String get chatOfflineStatus => 'Offline';

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
  String get noMessages => 'No messages';

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
}
