import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/features/chat/data/message_text_entity.dart';

/// Inline spans preserve the message's metrics, wrapping and footer space.
class MessageTextContent extends StatefulWidget {
  const MessageTextContent({
    super.key,
    required this.text,
    required this.style,
    required this.footerWidth,
    required this.onEntityTap,
  });

  final String text;
  final TextStyle style;
  final double footerWidth;
  final ValueChanged<MessageTextEntity> onEntityTap;

  @override
  State<MessageTextContent> createState() => _MessageTextContentState();
}

class _MessageTextContentState extends State<MessageTextContent> {
  List<MessageTextEntity> _entities = const [];
  final List<_InlineTextRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(MessageTextContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _parse();
  }

  void _parse() {
    _disposeRecognizers();
    _entities = MessageTextParser.parse(widget.text);
    for (final entity in _entities) {
      _recognizers.add(
        _InlineTextRecognizer(
          onTap: () => widget.onEntityTap(entity),
          onLongPress: () {
            unawaited(HapticFeedback.mediumImpact());
            unawaited(Clipboard.setData(ClipboardData(text: entity.text)));
          },
        ),
      );
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var offset = 0;
    for (var i = 0; i < _entities.length; i++) {
      final entity = _entities[i];
      if (offset < entity.start) {
        spans.add(TextSpan(text: widget.text.substring(offset, entity.start)));
      }
      _recognizers[i].gestureSettings = MediaQuery.gestureSettingsOf(context);
      spans.add(
        TextSpan(
          text: entity.text,
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: widget.style.color,
          ),
          recognizer: _recognizers[i],
        ),
      );
      offset = entity.end;
    }
    if (offset < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(offset)));
    }
    spans.add(
      WidgetSpan(child: SizedBox(width: widget.footerWidth, height: 1)),
    );
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

/// A tap recognizer (also supported by RichText accessibility) with a competing
/// long press for the same substring. It claims a completed short tap without
/// waiting for the bubble's double-tap recognizer; scroll/slop/cancel still use
/// Flutter's normal recognizer machinery.
class _InlineTextRecognizer extends TapGestureRecognizer {
  _InlineTextRecognizer({
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) : _longPress = LongPressGestureRecognizer()..onLongPress = onLongPress {
    this.onTap = onTap;
  }

  final LongPressGestureRecognizer _longPress;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _longPress.gestureSettings = gestureSettings;
    _longPress.addPointer(event);
    super.addAllowedPointer(event);
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    if (event is PointerUpEvent) resolve(GestureDisposition.accepted);
    super.handlePrimaryPointer(event);
  }

  @override
  void dispose() {
    _longPress.dispose();
    super.dispose();
  }
}
