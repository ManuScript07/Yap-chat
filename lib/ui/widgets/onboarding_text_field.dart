import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';

class OnboardingTextField extends StatefulWidget {
  const OnboardingTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final int maxLength;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<OnboardingTextField> createState() => _OnboardingTextFieldState();
}

class _OnboardingTextFieldState extends State<OnboardingTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _focusNode.requestFocus,
      child: _OnboardingInputFrame(
        isFocused: _focusNode.hasFocus,
        counter: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : Text('${value.text.length}/${widget.maxLength}'),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          maxLength: widget.maxLength,
          minLines: 1,
          maxLines: null,
          autocorrect: true,
          textCapitalization: widget.textCapitalization,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          textAlignVertical: TextAlignVertical.center,
          style: context.textTheme.titleMedium?.copyWith(
            color: context.colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.3,
            letterSpacing: .5,
          ),
          decoration: InputDecoration(
            hintText: widget.label,
            hintStyle: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: .5,
            ),
            counterText: '',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class OnboardingBirthDateFields extends StatelessWidget {
  const OnboardingBirthDateFields({
    super.key,
    required this.dayController,
    required this.monthController,
    required this.yearController,
    required this.dayFocusNode,
    required this.monthFocusNode,
    required this.yearFocusNode,
    required this.dayHint,
    required this.monthHint,
    required this.yearHint,
    required this.onChanged,
  });

  final TextEditingController dayController;
  final TextEditingController monthController;
  final TextEditingController yearController;
  final FocusNode dayFocusNode;
  final FocusNode monthFocusNode;
  final FocusNode yearFocusNode;
  final String dayHint;
  final String monthHint;
  final String yearHint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OnboardingDateField(
            controller: dayController,
            focusNode: dayFocusNode,
            placeholder: dayHint,
            maxLength: 2,
            onChanged: onChanged,
            onCompleted: () => monthFocusNode.requestFocus(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OnboardingDateField(
            controller: monthController,
            focusNode: monthFocusNode,
            placeholder: monthHint,
            maxLength: 2,
            onChanged: onChanged,
            onCompleted: () => yearFocusNode.requestFocus(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _OnboardingDateField(
            controller: yearController,
            focusNode: yearFocusNode,
            placeholder: yearHint,
            maxLength: 4,
            onChanged: onChanged,
            onCompleted: null,
          ),
        ),
      ],
    );
  }
}

class _OnboardingDateField extends StatefulWidget {
  const _OnboardingDateField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.maxLength,
    required this.onChanged,
    this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final int maxLength;
  final VoidCallback onChanged;
  final VoidCallback? onCompleted;

  @override
  State<_OnboardingDateField> createState() => _OnboardingDateFieldState();
}

class _OnboardingDateFieldState extends State<_OnboardingDateField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return _OnboardingInputFrame(
      height: 61,
      isFocused: widget.focusNode.hasFocus,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        maxLength: widget.maxLength,
        expands: true,
        maxLines: null,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onChanged: (value) {
          widget.onChanged();
          if (value.length == widget.maxLength) widget.onCompleted?.call();
        },
        style: context.textTheme.titleMedium?.copyWith(
          color: context.colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: .5,
        ),
        decoration: InputDecoration(
          hintText: widget.placeholder,
          hintStyle: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1,
            letterSpacing: .5,
          ),
          counterText: '',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
      ),
    );
  }
}

class _OnboardingInputFrame extends StatelessWidget {
  const _OnboardingInputFrame({
    required this.child,
    required this.isFocused,
    this.counter,
    this.height,
  });

  final Widget child;
  final bool isFocused;
  final Widget? counter;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: height ?? 61),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: context.colorScheme.onSurface.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFocused
              ? context.colorScheme.onSurface.withValues(alpha: .8)
              : context.colorScheme.outline,
          width: 2,
        ),
      ),
      child: counter == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                child,
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: IgnorePointer(
                      child: DefaultTextStyle(
                        style:
                            context.textTheme.bodyMedium?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                              fontSize: 16,
                              height: 1,
                              letterSpacing: .5,
                            ) ??
                            const TextStyle(),
                        child: counter!,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: content,
    );
  }
}
