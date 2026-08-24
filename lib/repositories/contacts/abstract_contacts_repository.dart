import 'package:yap_chat/features/friends/data/data.dart';

enum ContactsPermissionStatus { granted, denied, permanentlyDenied }

abstract interface class IContactsRepository {
  Future<ContactsPermissionStatus> requestPermission();
  Future<List<DeviceContactPhone>> readPhoneContacts();
  Future<void> openAppSettings();
  Future<void> shareInvitation(String text);
}
