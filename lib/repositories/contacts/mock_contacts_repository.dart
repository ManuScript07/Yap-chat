import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/contacts/abstract_contacts_repository.dart';

class MockContactsRepository implements IContactsRepository {
  const MockContactsRepository();

  @override
  Future<ContactsPermissionStatus> requestPermission() async =>
      ContactsPermissionStatus.granted;

  @override
  Future<List<DeviceContactPhone>> readPhoneContacts() async => const [
    DeviceContactPhone(
      id: 'mock-contact-1:0',
      displayName: 'Максим',
      normalizedPhone: '+79990000001',
    ),
    DeviceContactPhone(
      id: 'mock-contact-2:0',
      displayName: 'Анна',
      normalizedPhone: '+79990000002',
    ),
  ];

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> shareInvitation(String text) async {}
}
