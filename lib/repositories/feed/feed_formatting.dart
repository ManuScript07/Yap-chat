enum FeedTextStyle { bold, italic, underline, strikethrough }

typedef FeedTextRange = ({int start, int end, FeedTextStyle style});

/// Offsets count Unicode code points in the exact text received from the API.
List<FeedTextRange> decodeFeedFormatting(String text, Object? value) {
  if (value is! Map || value['version'] != 1) return const [];
  final spans = value['spans'];
  if (spans is! List || spans.isEmpty || spans.length > 128) return const [];
  final length = text.runes.length;
  final ranges = <FeedTextRange>[];
  final lastEnd = <FeedTextStyle, int>{};
  final styles = FeedTextStyle.values.asNameMap();
  for (final span in spans) {
    if (span is! Map ||
        span['start'] is! int ||
        span['end'] is! int ||
        span['style'] is! String) {
      return const [];
    }
    final start = span['start'] as int;
    final end = span['end'] as int;
    final style = styles[span['style']];
    if (style == null ||
        start < (lastEnd[style] ?? 0) ||
        end <= start ||
        end > length) {
      return const [];
    }
    lastEnd[style] = end;
    ranges.add((start: start, end: end, style: style));
  }
  return List.unmodifiable(ranges);
}
