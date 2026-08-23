import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';

class OnboardingTextField extends StatefulWidget {
  const OnboardingTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.maxLength,
    required this.maxLines,
    required this.tooLongText,
    this.errorText,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLength;
  final int maxLines;
  final String tooLongText;
  final String? errorText;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
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
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final errorText = value.text.length > widget.maxLength
            ? widget.tooLongText
            : widget.errorText;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _focusNode.requestFocus,
          child: _OnboardingTextInputFrame(
            isFocused: _focusNode.hasFocus,
            label: widget.label,
            errorText: errorText,
            counter: Text('${value.text.length}/${widget.maxLength}'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Align(
                alignment: widget.maxLines == 1
                    ? Alignment.center
                    : Alignment.topCenter,
                child: SizedBox(
                  width: double.infinity,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    maxLength: widget.maxLength,
                    maxLengthEnforcement: MaxLengthEnforcement.none,
                    minLines: 1,
                    maxLines: widget.maxLines,
                    autocorrect: true,
                    textCapitalization: widget.textCapitalization,
                    textInputAction: widget.textInputAction,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    textAlignVertical: TextAlignVertical.center,
                    strutStyle: const StrutStyle(
                      fontSize: 18,
                      height: 1.15,
                      forceStrutHeight: true,
                    ),
                    style: context.textTheme.titleMedium?.copyWith(
                      color: context.colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      letterSpacing: .5,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurfaceVariant.withValues(
                          alpha: .72,
                        ),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        letterSpacing: 0,
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
                ),
              ),
            ),
          ),
        );
      },
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.focusNode.requestFocus,
      child: _OnboardingInputFrame(
        height: 61,
        isFocused: widget.focusNode.hasFocus,
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: double.infinity,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              maxLength: widget.maxLength,
              minLines: 1,
              maxLines: 1,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              strutStyle: const StrutStyle(
                fontSize: 18,
                height: 1.15,
                forceStrutHeight: true,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onChanged: (value) {
                widget.onChanged();
                if (value.length == widget.maxLength) {
                  widget.onCompleted?.call();
                }
              },
              style: context.textTheme.titleMedium?.copyWith(
                color: context.colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.15,
                letterSpacing: .5,
              ),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant.withValues(
                    alpha: .78,
                  ),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
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
          ),
        ),
      ),
    );
  }
}

class _OnboardingTextInputFrame extends StatelessWidget {
  const _OnboardingTextInputFrame({
    required this.child,
    required this.isFocused,
    required this.label,
    required this.errorText,
    required this.counter,
  });

  final Widget child;
  final bool isFocused;
  final String label;
  final String? errorText;
  final Widget counter;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final titleColor = errorText == null
        ? colorScheme.onSurface
        : Color.lerp(colorScheme.error, Colors.red, 1)!;
    final titleStyle = context.textTheme.labelLarge?.copyWith(
      color: titleColor,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.15,
      letterSpacing: .35,
    );
    final borderColor = isFocused
        ? colorScheme.onSurface.withValues(alpha: .8)
        : colorScheme.outline;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: colorScheme.onSurface.withValues(alpha: .2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    errorText ?? label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                if (isFocused) ...[
                  const SizedBox(width: 8),
                  DefaultTextStyle(
                    style:
                        context.textTheme.bodySmall?.copyWith(
                          color: errorText == null
                              ? colorScheme.onSurfaceVariant.withValues(
                                  alpha: .82,
                                )
                              : titleColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                          letterSpacing: .2,
                        ) ??
                        const TextStyle(),
                    child: IgnorePointer(child: counter),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            child,
          ],
        ),
      ),
    );
  }
}

class _OnboardingInputFrame extends StatelessWidget {
  const _OnboardingInputFrame({
    required this.child,
    required this.isFocused,
    this.height,
  });

  final Widget child;
  final bool isFocused;
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
      child: child,
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
