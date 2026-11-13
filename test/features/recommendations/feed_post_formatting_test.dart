import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/recommendations/view/feed_post_text.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

void main() {
  const text = 'a🚀e\u0301z';

  Map<String, Object> span(int start, int end, String style) => {
    'start': start,
    'end': end,
    'style': style,
  };

  test('renders overlapping styles at Unicode code-point offsets', () {
    final formatting = decodeFeedFormatting(text, {
      'version': 1,
      'spans': [
        span(0, 2, 'bold'),
        span(1, 2, 'underline'),
        span(1, 2, 'strikethrough'),
        span(1, 4, 'italic'),
      ],
    });
    final rich = feedPostText(
      FeedPost(
        id: 'post',
        authorId: 'author',
        authorName: null,
        text: text,
        createdAt: DateTime.utc(2026),
        formatting: formatting,
      ),
      const TextStyle(),
    );
    expect(rich.toPlainText(), text);
    final [a, rocket, accent, z] = rich.children!.cast<TextSpan>();
    expect(a.style!.fontWeight, FontWeight.bold);
    expect(rocket.text, '🚀');
    expect(rocket.style!.fontWeight, FontWeight.bold);
    expect(rocket.style!.fontStyle, FontStyle.italic);
    expect(
      rocket.style!.decoration!.contains(TextDecoration.underline),
      isTrue,
    );
    expect(
      rocket.style!.decoration!.contains(TextDecoration.lineThrough),
      isTrue,
    );
    expect(accent.text, 'e\u0301');
    expect(accent.style!.fontWeight, isNull);
    expect(accent.style!.fontStyle, FontStyle.italic);
    expect(z.text, 'z');
    expect(z.style!.fontStyle, isNull);
  });

  test('missing, unknown or invalid formatting falls back to plain text', () {
    for (final value in [
      null,
      {
        'version': 2,
        'spans': [span(0, 1, 'bold')],
      },
      {
        'version': 1,
        'spans': [span(0, 6, 'bold')],
      },
      {
        'version': 1,
        'spans': [span(0, 3, 'bold'), span(2, 4, 'bold')],
      },
      {
        'version': 1,
        'spans': [span(0, 1, 'html')],
      },
    ]) {
      expect(decodeFeedFormatting(text, value), isEmpty);
    }
  });
}
