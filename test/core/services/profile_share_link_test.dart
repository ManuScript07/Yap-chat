import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/profile_share_link.dart';

void main() {
  group('ProfileShareLink', () {
    test('creates and parses the canonical username-only URL', () {
      final link = ProfileShareLink.tryCreate('Manu_Script07');

      expect(link, Uri.parse('https://links.yapchat.ru/manu_script07'));
      expect(ProfileShareLink.tryParse(link!), 'manu_script07');
    });

    test('rejects routes and URLs that cannot be profile usernames', () {
      expect(ProfileShareLink.tryParse(Uri.parse('https://links.yapchat.ru/')), isNull);
      expect(
        ProfileShareLink.tryParse(
          Uri.parse('https://links.yapchat.ru/.well-known/assetlinks.json'),
        ),
        isNull,
      );
      expect(
        ProfileShareLink.tryParse(Uri.parse('https://example.com/manuscript')),
        isNull,
      );
      expect(
        ProfileShareLink.tryParse(
          Uri.parse('https://links.yapchat.ru/manuscript?source=share'),
        ),
        isNull,
      );
    });
  });
}
