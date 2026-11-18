import 'package:flutter/material.dart';

class RetryPillButton extends StatelessWidget {
  const RetryPillButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  static TextStyle labelStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelLarge!
      .copyWith(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: .5);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        textStyle: labelStyle(context),
        minimumSize: const Size(64, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: const StadiumBorder(),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
