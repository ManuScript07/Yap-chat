import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/data/message_text_entity.dart';
import 'package:yap_chat/features/chat/view/message_text_actions.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/repositories.dart';

import 'feed_post_text.dart';

class FeedPostBody extends StatefulWidget {
  const FeedPostBody({
    super.key,
    required this.post,
    required this.timeline,
    required this.details,
    required this.onOpen,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool details;
  final VoidCallback onOpen;

  @override
  State<FeedPostBody> createState() => _FeedPostBodyState();
}

class _FeedPostBodyState extends State<FeedPostBody> {
  static const _lines = 5;
  final _recognizers = <TapGestureRecognizer>[];
  late List<FeedTextLink> _links;
  late final _more = TapGestureRecognizer()..onTap = _expand;
  MessageTextActions? _actions;
  (TextSpan, double, TextDirection, TextScaler, String)? _layout;
  TextSpan? _collapsed;
  TextSpan? _body;
  TextStyle? _style;
  Color? _linkColor;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(FeedPostBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.text != widget.post.text) _parse();
    if (!identical(oldWidget.post, widget.post)) _body = null;
  }

  void _parse() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _links = [
      for (final entity in MessageTextParser.parse(widget.post.text))
        if (entity.type != MessageTextEntityType.phone)
          (
            start: entity.start,
            end: entity.end,
            recognizer: TapGestureRecognizer()
              ..onTap = () => unawaited(_open(entity)),
          ),
    ];
    _recognizers.addAll(
      _links.map((link) => link.recognizer as TapGestureRecognizer),
    );
  }

  Future<void> _open(MessageTextEntity entity) async {
    final timeline = widget.timeline;
    bool active() => mounted && timeline.isCurrentAccount();
    if (!active()) return;
    final friends = context.read<IFriendsRepository?>();
    final profiles = context.read<IProfileRepository?>();
    if (friends == null || profiles == null) return;
    _actions ??= MessageTextActions(
      friends: friends,
      profiles: profiles,
      openLink: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
      openProfile: (id) => openViewedProfile(context, userId: id),
      isActive: active,
      currentUserId: timeline.account.userId,
      onError: (_, _) {},
    );
    final result = await _actions!.activate(entity);
    if (mounted &&
        timeline.isCurrentAccount() &&
        (result == MessageTextActionResult.failed ||
            result == MessageTextActionResult.unavailable)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.feedActionFailed)));
    }
  }

  void _expand() => widget.timeline.toggleExpanded(widget.post.id);

  @override
  Widget build(BuildContext context) {
    final style = (context.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      height: 1.3,
    );
    final color = context.colorScheme.primary;
    if (_body == null || _style != style || _linkColor != color) {
      _style = style;
      _linkColor = color;
      _body = feedPostText(widget.post, style, links: _links, linkColor: color);
    }
    final text = _body!;
    if (widget.details) return Text.rich(text);
    return BlocSelector<FeedCubit, FeedState, bool>(
      bloc: widget.timeline,
      selector: (state) => state.expandedIds.contains(widget.post.id),
      builder: (context, expanded) => LayoutBuilder(
        builder: (context, constraints) {
          final more = TextSpan(
            text: ' ${context.l10n.feedInlineMore}',
            style: TextStyle(color: color),
            recognizer: _more,
          );
          final layout = (
            text,
            constraints.maxWidth,
            Directionality.of(context),
            MediaQuery.textScalerOf(context),
            more.text!,
          );
          if (!expanded && _layout != layout) {
            _layout = layout;
            _collapsed = _collapse(text, more, layout.$2, layout.$3, layout.$4);
          }
          final collapsed = expanded ? null : _collapsed;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: collapsed != null ? _expand : widget.onOpen,
            child:
                collapsed == null &&
                    _links.isEmpty &&
                    widget.post.formatting.isEmpty
                ? Text(widget.post.text, style: style)
                : Text.rich(
                    collapsed ?? text,
                    maxLines: collapsed == null ? null : _lines,
                    overflow: collapsed == null ? null : TextOverflow.clip,
                  ),
          );
        },
      ),
    );
  }

  TextSpan? _collapse(
    TextSpan text,
    TextSpan more,
    double width,
    TextDirection direction,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: text,
      textDirection: direction,
      textScaler: scaler,
      maxLines: _lines,
    );
    try {
      painter.layout(maxWidth: width);
      if (!painter.didExceedMaxLines) return null;
      final spans =
          text.children?.cast<TextSpan>() ?? [TextSpan(text: text.text)];
      final boundaries = <int>[0];
      for (final character in widget.post.text.characters) {
        boundaries.add(boundaries.last + character.length);
      }
      TextSpan candidate(int end) {
        final prefix = <TextSpan>[];
        var remaining = end;
        for (final span in spans) {
          if (remaining <= 0) break;
          final value = span.text!;
          final length = remaining.clamp(0, value.length);
          prefix.add(
            TextSpan(
              text: value.substring(0, length),
              style: span.style,
              recognizer: span.recognizer,
            ),
          );
          remaining -= length;
        }
        return TextSpan(style: text.style, children: [...prefix, more]);
      }

      var low = 0;
      var high = boundaries.length - 1;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        painter.text = candidate(boundaries[mid]);
        painter.layout(maxWidth: width);
        if (painter.didExceedMaxLines) {
          high = mid - 1;
        } else {
          low = mid;
        }
      }
      return candidate(boundaries[low]);
    } finally {
      painter.dispose();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _more.dispose();
    super.dispose();
  }
}
