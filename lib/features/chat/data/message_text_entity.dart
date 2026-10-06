import 'package:yap_chat/core/services/phone_number_normalizer.dart';

enum MessageTextEntityType { link, phone, username }

/// Offsets refer to the original UTF-16 message, never to normalized text.
class MessageTextEntity {
  const MessageTextEntity({
    required this.start,
    required this.end,
    required this.text,
    required this.type,
    required this.target,
  });

  final int start;
  final int end;
  final String text;
  final MessageTextEntityType type;
  final String target;
}

/// Local linkification only: no HTML, Markdown, network calls or database writes.
class MessageTextParser {
  static final _urls = RegExp(
    r'''(?:https?://|www\.)[^\s<>"\x00-\x1f]+|(?:[a-z0-9а-яё](?:[a-z0-9а-яё-]*[a-z0-9а-яё])?\.)+[a-zа-яё]{2,63}(?::[0-9]{1,5})?(?:[/?#][^\s<>"\x00-\x1f]*)?''',
    caseSensitive: false,
  );
  static final _emails = RegExp(
    r'''[a-z0-9а-яё._%+-]+@(?:[a-z0-9а-яё-]+\.)+[a-zа-яё]{2,63}''',
    caseSensitive: false,
  );
  static final _phones = RegExp(r'\+[0-9](?:[0-9 ()\u00a0.-]*[0-9])?');
  static final _unsupportedUris = RegExp(
    r'''\b(?:javascript|data|file|ftp|mailto|tel):[^\s<>"]*''',
    caseSensitive: false,
  );
  static final _usernames = RegExp(r'@[a-z0-9_]+', caseSensitive: false);
  static final _word = RegExp(r'[\p{L}\p{N}_@]', unicode: true);
  static final _normalizer = PhoneNumberNormalizer();

  static List<MessageTextEntity> parse(String text) {
    final entities = <MessageTextEntity>[];
    final emails = _emails.allMatches(text).toList(growable: false);
    final unsupported = _unsupportedUris
        .allMatches(text)
        .toList(growable: false);
    final urls = _urls.allMatches(text).toList(growable: false);
    bool occupied(int start, int end) =>
        entities.any((e) => start < e.end && end > e.start) ||
        emails.any((e) => start < e.end && end > e.start) ||
        unsupported.any((e) => start < e.end && end > e.start) ||
        urls.any((e) => start < e.end && end > e.start);
    bool hasBoundary(int start) =>
        start == 0 || !_word.hasMatch(text.substring(start - 1, start));

    void add(int start, int end, MessageTextEntityType type, String target) {
      entities.add(
        MessageTextEntity(
          start: start,
          end: end,
          text: text.substring(start, end),
          type: type,
          target: target,
        ),
      );
    }

    for (final match in urls) {
      if (!hasBoundary(match.start) ||
          unsupported.any(
            (e) => match.start >= e.start && match.start < e.end,
          ) ||
          emails.any((e) => match.start >= e.start && match.start < e.end)) {
        continue;
      }
      final value = _trimUrl(match.group(0)!);
      final uri = Uri.tryParse(
        RegExp(r'^https?://', caseSensitive: false).hasMatch(value)
            ? value
            : 'https://$value',
      );
      if (uri == null ||
          !{'https', 'http'}.contains(uri.scheme.toLowerCase()) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          !uri.hasAuthority) {
        continue;
      }
      // Validate ports here; Uri.tryParse can defer an invalid-port error.
      try {
        if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) continue;
      } on FormatException {
        continue;
      }
      add(
        match.start,
        match.start + value.length,
        MessageTextEntityType.link,
        uri.toString(),
      );
    }
    for (final match in _phones.allMatches(text)) {
      if (!hasBoundary(match.start) || occupied(match.start, match.end)) {
        continue;
      }
      final value = _normalizer.normalize(match.group(0)!);
      if (value != null) {
        add(match.start, match.end, MessageTextEntityType.phone, value);
      }
    }
    for (final match in _usernames.allMatches(text)) {
      if (!hasBoundary(match.start) || occupied(match.start, match.end)) {
        continue;
      }
      if (match.end < text.length &&
          _word.hasMatch(text.substring(match.end, match.end + 1))) {
        continue;
      }
      final value = match.group(0)!.substring(1).toLowerCase();
      if (value.length >= 3 && value.length <= 24) {
        add(match.start, match.end, MessageTextEntityType.username, value);
      }
    }
    entities.sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(entities);
  }

  static String _trimUrl(String value) {
    var end = value.length;
    while (end > 0) {
      final last = value[end - 1];
      if ('. ,!?:;\'»'.contains(last)) {
        end--;
        continue;
      }
      final opening = {')': '(', ']': '[', '}': '{'}[last];
      if (opening != null) {
        final part = value.substring(0, end);
        if (last.allMatches(part).length > opening.allMatches(part).length) {
          end--;
          continue;
        }
      }
      break;
    }
    return value.substring(0, end);
  }
}
