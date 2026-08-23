import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';

/// Тип уведомления для смены цвета иконки/акцента
enum SnackBarType { success, error, info }

/// Универсальная функция для показа кастомных SnackBar
void showAppSnackBar(
  BuildContext context, {
  required String message,
  SnackBarType type = SnackBarType.info,
  Duration duration = const Duration(seconds: 3),
  double bottomMargin = 12,
  String? actionLabel,
  VoidCallback? onActionPressed,
}) {
  final colorScheme = context.colorScheme;
  final systemPadding = MediaQuery.paddingOf(context);

  ScaffoldMessenger.of(context).hideCurrentSnackBar();

  final (IconData icon, Color iconColor) = switch (type) {
    SnackBarType.success => (Icons.check_circle_rounded, colorScheme.primary),
    SnackBarType.error => (Icons.error_rounded, colorScheme.error),
    SnackBarType.info => (Icons.info_rounded, colorScheme.primary),
  };

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: duration,
      elevation: 6,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left: systemPadding.left + 16,
        top: 12,
        right: systemPadding.right + 16,
        bottom: bottomMargin,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      content: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      action: actionLabel != null && onActionPressed != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: colorScheme.primary,
              onPressed: onActionPressed,
            )
          : null,
    ),
  );
}
