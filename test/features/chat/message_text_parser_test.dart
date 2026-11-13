import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/message_text_entity.dart';

void main() {
  test(
    'recognizes links, formatted international phones and exact usernames',
    () {
      const text =
          'Привет @Alice_123: example.com, https://example.org/a?q=1 '
          'www.example.net +7 (999) 123-45-67';
      final entities = MessageTextParser.parse(text);
      expect(entities.map((e) => e.type), [
        MessageTextEntityType.username,
        MessageTextEntityType.link,
        MessageTextEntityType.link,
        MessageTextEntityType.link,
        MessageTextEntityType.phone,
      ]);
      expect(entities.map((e) => e.target), [
        'alice_123',
        'https://example.com',
        'https://example.org/a?q=1',
        'https://www.example.net',
        '+79991234567',
      ]);
      for (final entity in entities) {
        expect(text.substring(entity.start, entity.end), entity.text);
      }
    },
  );

  for (final text in [
    'first.last@example.com',
    'name+tag@EXAMPLE.COM',
    '@ab @abcdefghijklmnopqrstuvwxyz @юзер @validюзер',
    'hello@username',
    '123 8 (999) 123-45-67 2026-10-06',
    'javascript:alert(1) data:text/plain,hello file:///photo.jpg',
    'https://user:secret@example.com',
    'https://example.com:99999',
    '+12345',
  ]) {
    test('does not linkify: $text', () {
      expect(MessageTextParser.parse(text), isEmpty);
    });
  }

  test(
    'URLs take precedence over usernames, phones and email in their path',
    () {
      final entities = MessageTextParser.parse(
        'https://example.com/@alice/+79991234567?email=a@example.org',
      );
      expect(entities, hasLength(1));
      expect(entities.single.type, MessageTextEntityType.link);
    },
  );
  test('trims sentence punctuation but preserves balanced URL parentheses', () {
    final entities = MessageTextParser.parse(
      '(https://example.com/wiki/A_(B)). example.org/test! @alice.',
    );
    expect(entities.map((e) => e.text), [
      'https://example.com/wiki/A_(B)',
      'example.org/test',
      '@alice',
    ]);
  });
  test(
    'supports multiple international numbers and preserves original spacing',
    () {
      final entities = MessageTextParser.parse(
        '+1 (202) 555-0123 или +44 7911 123456',
      );
      expect(entities.map((e) => e.target), ['+12025550123', '+447911123456']);
      expect(entities.first.text, '+1 (202) 555-0123');
    },
  );
  test('handles emoji before an entity without corrupting UTF-16 offsets', () {
    const text = '❤️ 😀 @alice example.com';
    for (final entity in MessageTextParser.parse(text)) {
      expect(text.substring(entity.start, entity.end), entity.text);
    }
  });
  test('plain text and empty text have no entities', () {
    expect(MessageTextParser.parse(''), isEmpty);
    expect(MessageTextParser.parse('Обычное сообщение <b>текст</b>'), isEmpty);
  });
}
