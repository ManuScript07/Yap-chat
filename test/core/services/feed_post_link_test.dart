import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/services.dart';

void main() {
  test('publication link accepts one uuid on the verified host', () {
    const id = '07d220f5-ae02-4a69-b52f-0452f1637e1b';
    expect(FeedPostLink.tryParse(FeedPostLink.create(id)), id);
    for (final link in [
      'http://links.yapchat.ru/post/$id',
      'https://links.yapchat.ru:444/post/$id',
      'https://links.yapchat.ru.example.com/post/$id',
      'https://user@links.yapchat.ru/post/$id',
      'https://links.yapchat.ru/post/$id/another',
      'https://links.yapchat.ru/post/$id?other=1',
      'https://links.yapchat.ru/post/invalid',
    ]) {
      expect(FeedPostLink.tryParse(Uri.parse(link)), isNull, reason: link);
    }
    expect(ProfileShareLink.tryParse(FeedPostLink.create(id)), isNull);
  });
}
