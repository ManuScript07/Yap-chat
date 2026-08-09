import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class GlassSearchBar extends StatefulWidget {
  const GlassSearchBar({
    super.key,
    required this.hintText,
    this.onChanged,
    this.controller,
  });

  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  @override
  State<GlassSearchBar> createState() => _GlassSearchBarState();
}

class _GlassSearchBarState extends State<GlassSearchBar> {
  late final TextEditingController _controller;
  bool _showClearButton = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_handleTextChange);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_handleTextChange);
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                  onChanged: widget.onChanged,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
