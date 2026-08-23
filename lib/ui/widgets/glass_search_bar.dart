import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class GlassSearchBar extends StatefulWidget {
  const GlassSearchBar({
    super.key,
    required this.hintText,
    this.onChanged,
    this.controller,
    this.focusNode,
  });

  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<GlassSearchBar> createState() => _GlassSearchBarState();
}

class _GlassSearchBarState extends State<GlassSearchBar>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _showClearButton = false;
  double _lastKeyboardInset = 0;
  bool _hasKeyboardInset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();

    _controller.addListener(_handleTextChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasKeyboardInset) {
      _lastKeyboardInset = MediaQuery.viewInsetsOf(context).bottom;
      _hasKeyboardInset = true;
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;

    final view = View.maybeOf(context);
    if (view == null) return;

    final keyboardInset = MediaQueryData.fromView(view).viewInsets.bottom;
    _handleKeyboardInsetChanged(keyboardInset);
  }

  void _handleKeyboardInsetChanged(double keyboardInset) {
    final wasKeyboardOpen = _lastKeyboardInset > 0;
    _lastKeyboardInset = keyboardInset;

    if (wasKeyboardOpen && keyboardInset <= 0) {
      _clearFocus();
    }
  }

  void _clearFocus() {
    _focusNode.unfocus();
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_handleTextChange);
    }

    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleTextChange() {
    final show = _controller.text.isNotEmpty;
    if (show != _showClearButton) {
      setState(() => _showClearButton = show);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainColor = context.colorScheme.onSurface;
    final systemPadding = MediaQuery.paddingOf(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    // Some Android versions update MediaQuery one frame after the platform
    // metrics callback. Keep the same transition guard here as a fallback.
    if (_hasKeyboardInset &&
        _lastKeyboardInset > 0 &&
        keyboardInset <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearFocus();
      });
    }
    _lastKeyboardInset = keyboardInset;
    _hasKeyboardInset = true;

    return Padding(
      padding: EdgeInsets.only(
        left: 16 + systemPadding.left,
        right: 16 + systemPadding.right,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mainColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.5),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                color: mainColor.withValues(alpha: 0.15),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: widget.onChanged,
                  onTapOutside: (_) => _focusNode.unfocus(),
                  cursorColor: mainColor,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.50,
                    color: mainColor,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 32,
                      color: mainColor.withValues(alpha: 0.6),
                    ),
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.50,
                      color: mainColor.withValues(alpha: 0.6),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 50,
                    ),
                    suffixIcon: _showClearButton
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: mainColor,
                              size: 26,
                            ),
                            onPressed: () {
                              _controller.clear();
                              widget.onChanged?.call('');
                            },
                          )
                        : null,
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
