import 'dart:ui';

import 'package:flutter_contacts/flutter_contacts.dart' as native_contacts;
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  test('maps permanent native denial to app permission status', () async {
    final repository = ContactsRepository(
      requestPermission: () async =>
          native_contacts.PermissionStatus.permanentlyDenied,
    );

    expect(
      await repository.requestPermission(),
      ContactsPermissionStatus.permanentlyDenied,
    );
  });

  test('creates a separate normalized entry for every valid phone', () async {
    final repository = ContactsRepository(
      localeProvider: () => const Locale('en', 'US'),
      loadContacts: () async => const [
        native_contacts.Contact(
          id: 'contact-1',
          displayName: 'Alice',
          phones: [
            native_contacts.Phone(number: '(202) 555-0119'),
            native_contacts.Phone(number: '+44 20 7946 0018'),
            native_contacts.Phone(number: 'invalid'),
          ],
        ),
      ],
    );

    final contacts = await repository.readPhoneContacts();

    expect(contacts, hasLength(2));
    expect(
      contacts.map((contact) => contact.normalizedPhone),
      containsAll(['+12025550119', '+442079460018']),
    );
    expect(contacts.map((contact) => contact.id), [
      'contact-1:0',
      'contact-1:1',
    ]);
  });

  test('does not guess a local phone without a device country', () async {
    final repository = ContactsRepository(
      localeProvider: () => const Locale('en'),
      loadContacts: () async => const [
        native_contacts.Contact(
          id: 'contact-1',
          displayName: 'Alice',
          phones: [native_contacts.Phone(number: '2025550119')],
        ),
      ],
    );

    expect(await repository.readPhoneContacts(), isEmpty);
  });

  test(
    'falls back to the raw phone when platform normalization is empty',
    () async {
      final repository = ContactsRepository(
        localeProvider: () => const Locale('en', 'US'),
        loadContacts: () async => const [
          native_contacts.Contact(
            id: 'contact-1',
            displayName: 'Alice',
            phones: [
              native_contacts.Phone(
                number: '(202) 555-0119',
                normalizedNumber: '',
              ),
            ],
          ),
        ],
      );

      expect(
        (await repository.readPhoneContacts()).single.normalizedPhone,
        '+12025550119',
      );
    },
  );

  test('forwards invitation text to the platform share sheet', () async {
    String? sharedText;
    final repository = ContactsRepository(
      shareText: (text) async => sharedText = text,
    );

    await repository.shareInvitation('Join me');

    expect(sharedText, 'Join me');
  });
}
