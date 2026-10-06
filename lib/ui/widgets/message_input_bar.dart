import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/chat_glass_surface.dart';
import 'package:yap_chat/ui/widgets/glass_icon_button.dart';
import 'package:yap_chat/ui/theme/theme.dart';

class MessageInputBar extends StatefulWidget {
  const MessageInputBar({
    super.key,
    required this.onSend,
    this.onAddPhoto,
    this.onVoiceRecord,
    this.replyToMessageId,
    this.focusNode,
  });

  final ValueChanged<String> onSend;
  final VoidCallback? onAddPhoto;
  final VoidCallback? onVoiceRecord;
  final String? replyToMessageId;

  /// An optional, externally owned node for coordinating route and menu focus.
  final FocusNode? focusNode;

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  late final TextEditingController _controller;
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  bool _hasText = false;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController();

    _controller.addListener(_handleTextChange);
  }

  void _handleTextChange() {
    final hasText = _controller.text.trim().isNotEmpty;

    if (hasText == _hasText) {
      return;
    }

    setState(() {
      _hasText = hasText;
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      return;
    }

    widget.onSend(text);
    _controller.clear();
  }

  void _handleAction() {
    if (_hasText) {
      _handleSend();
      return;
    }

    widget.onVoiceRecord?.call();
  }

  @override
  void didUpdateWidget(covariant MessageInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replyToMessageId == null && widget.replyToMessageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChange);
    _controller.dispose();
    _ownedFocusNode?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final backgroundColor = context.scaffoldBackgroundColor;

    final mainColor = colorScheme.onSurface;
    final primaryColor = colorScheme.primary;
    final systemPadding = MediaQuery.viewPaddingOf(context);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      // Keep the navigation-bar inset while the IME is animating.  The chat
      // page converts the keyboard inset into a matching outer offset.
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          systemPadding.left + 16,
          8,
          systemPadding.right + 16,
          8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.centerLeft,
                  child: _hasText
                      ? const SizedBox.shrink()
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AttachmentButton(onTap: widget.onAddPhoto),
                            const SizedBox(width: 8),
                          ],
                        ),
                ),
                Expanded(
                  child: _MessageTextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    mainColor: mainColor,
                  ),
                ),
                const SizedBox(width: 8),
                _SendButton(
                  hasText: _hasText,
                  primaryColor: primaryColor,
                  iconColor: backgroundColor,
                  onTap: _handleAction,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  const _AttachmentButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: Icons.add,
      chatStyle: true,
      onTap: onTap ?? () {},
      width: 50,
      height: 50,
      borderRadius: 20,
      iconSize: 32,
    );
  }
}

class _MessageTextField extends StatelessWidget {
  const _MessageTextField({
    required this.controller,
    required this.focusNode,
    required this.mainColor,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Color mainColor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50, maxHeight: 150),
      child: ChatGlassSurface(
        borderRadius: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            contextMenuBuilder: buildAppTextSelectionToolbar,
            minLines: 1,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            cursorColor: mainColor,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.15,
              color: mainColor,
            ),
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: context.l10n.chatInputHint,
              hintStyle: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.15,
                color: mainColor.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.hasText,
    required this.primaryColor,
    required this.iconColor,
    required this.onTap,
  });

  final bool hasText;
  final Color primaryColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Material(
        color: primaryColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Icon(
                hasText ? Icons.send_rounded : Icons.mic_rounded,
                key: ValueKey<bool>(hasText),
                color: iconColor,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
