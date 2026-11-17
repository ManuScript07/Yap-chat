import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

typedef FeedTextLink = ({int start, int end, GestureRecognizer recognizer});

TextSpan feedPostText(
  FeedPost post,
  TextStyle style, {
  List<FeedTextLink> links = const [],
  Color? linkColor,
}) {
  if (post.formatting.isEmpty && links.isEmpty) {
    return TextSpan(text: post.text, style: style);
  }
  final starts = <int, List<FeedTextStyle>>{};
  final ends = <int, List<FeedTextStyle>>{};
  final offsets = <int>[0];
  var offset = 0;
  for (final rune in post.text.runes) {
    offset += rune > 0xffff ? 2 : 1;
    offsets.add(offset);
  }
  for (final range in post.formatting) {
    (starts[offsets[range.start]] ??= []).add(range.style);
    (ends[offsets[range.end]] ??= []).add(range.style);
  }

  final boundaries = {
    0,
    offset,
    ...starts.keys,
    ...ends.keys,
    for (final link in links) ...[link.start, link.end],
  }.toList()..sort();
  final active = <FeedTextStyle>{};
  final children = <TextSpan>[];
  for (var index = 0; index + 1 < boundaries.length; index++) {
    final start = boundaries[index];
    GestureRecognizer? recognizer;
    for (final link in links) {
      if (start >= link.start && start < link.end) {
        recognizer = link.recognizer;
        break;
      }
    }
    active.removeAll(ends[start] ?? const []);
    active.addAll(starts[start] ?? const []);
    final decorations = [
      if (active.contains(FeedTextStyle.underline)) TextDecoration.underline,
      if (active.contains(FeedTextStyle.strikethrough))
        TextDecoration.lineThrough,
    ];
    children.add(
      TextSpan(
        text: post.text.substring(start, boundaries[index + 1]),
        recognizer: recognizer,
        style: TextStyle(
          color: recognizer == null ? null : linkColor,
          fontWeight: active.contains(FeedTextStyle.bold)
              ? FontWeight.bold
              : null,
          fontStyle: active.contains(FeedTextStyle.italic)
              ? FontStyle.italic
              : null,
          decoration: decorations.isEmpty
              ? null
              : TextDecoration.combine(decorations),
        ),
      ),
    );
  }
  return TextSpan(style: style, children: children);
}
