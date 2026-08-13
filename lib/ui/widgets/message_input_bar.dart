import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/glass_icon_button.dart';

class MessageInputBar extends StatefulWidget {
  const MessageInputBar({
    super.key,
    required this.onSend,
    this.onAddPhoto,
    this.onVoiceRecord,
  });

  final ValueChanged<String> onSend;
  final VoidCallback? onAddPhoto;
  final VoidCallback? onVoiceRecord;

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _hasText = false;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController();
    _focusNode = FocusNode();

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
  void dispose() {
    _controller.removeListener(_handleTextChange);
    _controller.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final backgroundColor = context.scaffoldBackgroundColor;

    final mainColor = colorScheme.onSurface;
    final primaryColor = colorScheme.primary;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _AttachmentButton(visible: !_hasText, onTap: widget.onAddPhoto),

            const SizedBox(width: 8),

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
      ),
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  const _AttachmentButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.centerRight,
      child: visible
          ? GlassIconButton(
              icon: Icons.add,
              onTap: onTap ?? () {},
              width: 50,
              height: 50,
              borderRadius: 20,
              iconSize: 32,
            )
          : const SizedBox(width: 0),
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
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: mainColor.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              color: mainColor.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
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
