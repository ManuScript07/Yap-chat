import 'package:flutter/material.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/core/core.dart';

/// Утвержденная универсальная функция для показа диалога при отказе в разрешениях.
///
/// Принимает кастомный [title] и [content], если стандартные тексты для камеры не подходят.
Future<void> showPermissionDeniedDialog(
  BuildContext context, {
  String? title,
  String? content,
  VoidCallback? onOpenSettings,
}) async {
  final l10n = context.l10n;

  final colorScheme = context.colorScheme;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),

      title: Text(
        title ?? l10n.permissionDenied,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Описание
      content: Text(
        content ?? l10n.youMustAllowCameraPermission,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 16,
          height: 1.4,
        ),
      ),

      actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: Text(l10n.cancel),
        ),

        FilledButton(
          onPressed: () {
            onOpenSettings?.call();
            MediaService.openSettings();
            Navigator.of(dialogContext).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: AppColors.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(l10n.settings),
        ),
      ],
    ),
  );
}
