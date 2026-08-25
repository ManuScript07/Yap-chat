import 'dart:ui';

import 'package:flutter_contacts/flutter_contacts.dart' as native_contacts;
import 'package:share_plus/share_plus.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/contacts/abstract_contacts_repository.dart';

typedef NativeContactsLoader = Future<List<native_contacts.Contact>> Function();

class ContactsRepository implements IContactsRepository {
  ContactsRepository({
    Future<native_contacts.PermissionStatus> Function()? requestPermission,
    NativeContactsLoader? loadContacts,
    Future<void> Function()? openSettings,
    Future<void> Function(String text)? shareText,
    Locale Function()? localeProvider,
  }) : _requestPermission =
           requestPermission ??
           (() => native_contacts.FlutterContacts.permissions.request(
             native_contacts.PermissionType.read,
           )),
       _loadContacts =
           loadContacts ??
           (() => native_contacts.FlutterContacts.getAll(
             properties: const {native_contacts.ContactProperty.phone},
           )),
       _openSettings =
           openSettings ??
           native_contacts.FlutterContacts.permissions.openSettings,
       _shareText =
           shareText ??
           ((text) async {
             await SharePlus.instance.share(ShareParams(text: text));
           }),
       _phoneNormalizer = PhoneNumberNormalizer(localeProvider: localeProvider);

  final Future<native_contacts.PermissionStatus> Function() _requestPermission;
  final NativeContactsLoader _loadContacts;
  final Future<void> Function() _openSettings;
  final Future<void> Function(String text) _shareText;
  final PhoneNumberNormalizer _phoneNormalizer;

  @override
  Future<ContactsPermissionStatus> requestPermission() async {
    final status = await _requestPermission();
    return switch (status) {
      native_contacts.PermissionStatus.granted ||
      native_contacts.PermissionStatus.limited =>
        ContactsPermissionStatus.granted,
      native_contacts.PermissionStatus.permanentlyDenied ||
      native_contacts.PermissionStatus.restricted =>
        ContactsPermissionStatus.permanentlyDenied,
      native_contacts.PermissionStatus.denied ||
      native_contacts.PermissionStatus.notDetermined =>
        ContactsPermissionStatus.denied,
    };
  }

  @override
  Future<List<DeviceContactPhone>> readPhoneContacts() async {
    final contacts = await _loadContacts();
    final entries = <DeviceContactPhone>[];
    for (final contact in contacts) {
      for (var index = 0; index < contact.phones.length; index++) {
        final phone = contact.phones[index];
        final platformNormalized = phone.normalizedNumber?.trim();
        final normalized = _phoneNormalizer.normalize(
          platformNormalized == null || platformNormalized.isEmpty
              ? phone.number
              : platformNormalized,
        );
        if (normalized == null) continue;
        final contactId = contact.id ?? contact.displayName ?? 'contact';
        final name = contact.displayName?.trim();
        entries.add(
          DeviceContactPhone(
            id: '$contactId:$index',
            displayName: name == null || name.isEmpty ? normalized : name,
            normalizedPhone: normalized,
          ),
        );
      }
    }
    entries.sort((left, right) {
      final byName = left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      );
      return byName != 0 ? byName : left.id.compareTo(right.id);
    });
    return List.unmodifiable(entries);
  }

  @override
  Future<void> openAppSettings() => _openSettings();

  @override
  Future<void> shareInvitation(String text) => _shareText(text);
}
