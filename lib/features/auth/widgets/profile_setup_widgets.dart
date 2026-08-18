import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

class ProfileSetupStep extends StatelessWidget {
  const ProfileSetupStep({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.errorText,
  });

  final String title;
  final String? subtitle;
  final String? errorText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleSize = math.min(
          42.0,
          math.max(30.0, constraints.maxWidth * .1),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: math.min(448, constraints.maxWidth - 72),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: context.textTheme.displaySmall?.copyWith(
                        color: context.colorScheme.onSurface,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.24,
                        letterSpacing: .42,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1,
                          letterSpacing: .5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 56),
                    child,
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProfileGenderPicker extends StatelessWidget {
  const ProfileGenderPicker({
    super.key,
    required this.selectedGender,
    required this.resetLabel,
    required this.onSelected,
    required this.onReset,
  });

  final ProfileGender? selectedGender;
  final String resetLabel;
  final ValueChanged<ProfileGender> onSelected;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ProfileGenderOption(
              icon: Icons.male_rounded,
              isSelected: selectedGender == ProfileGender.male,
              onTap: () => onSelected(ProfileGender.male),
            ),
            const SizedBox(width: 18),
            _ProfileGenderOption(
              icon: Icons.female_rounded,
              isSelected: selectedGender == ProfileGender.female,
              onTap: () => onSelected(ProfileGender.female),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: selectedGender == null ? 0 : 1,
          child: TextButton(
            onPressed: selectedGender == null ? null : onReset,
            style: TextButton.styleFrom(
              foregroundColor: context.colorScheme.onSurface.withValues(
                alpha: .72,
              ),
              textStyle: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(resetLabel),
          ),
        ),
      ],
    );
  }
}

class _ProfileGenderOption extends StatelessWidget {
  const _ProfileGenderOption({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          width: 135,
          height: 138,
          decoration: BoxDecoration(
            color: context.colorScheme.primary,
            borderRadius: BorderRadius.circular(28),
            border: isSelected
                ? Border.all(color: context.colorScheme.onSurface, width: 4)
                : null,
          ),
          child: Icon(icon, size: 84, color: context.colorScheme.onPrimary),
        ),
      ),
    );
  }
}

class ProfileAvatarPicker extends StatelessWidget {
  const ProfileAvatarPicker({
    super.key,
    required this.avatarUrl,
    required this.localAvatarBytes,
    required this.onPick,
    required this.onRemove,
  });

  final String? avatarUrl;
  final Uint8List? localAvatarBytes;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = localAvatarBytes != null || avatarUrl?.isNotEmpty == true;
    final avatar = hasAvatar
        ? UserAvatar(
            avatarUrl: avatarUrl,
            avatarImage: localAvatarBytes == null
                ? null
                : MemoryImage(localAvatarBytes!),
            size: 220,
            borderRadius: 28,
          )
        : Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: context.colorScheme.primary,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.add_a_photo_rounded,
              size: 48,
              color: context.colorScheme.onPrimary,
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPick,
          child: avatar,
        ),
        if (hasAvatar)
          Positioned(
            top: -12,
            right: -12,
            child: SizedBox.square(
              dimension: 42,
              child: IconButton(
                onPressed: onRemove,
                style: IconButton.styleFrom(
                  backgroundColor: context.colorScheme.surface,
                  foregroundColor: context.colorScheme.onPrimary,
                  shape: const CircleBorder(),
                ),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          )
      ],
    );
  }
}

class ProfileSetupNavigation extends StatelessWidget {
  const ProfileSetupNavigation({
    super.key,
    required this.isFirstStep,
    required this.isLastStep,
    required this.showSkip,
    required this.isSubmitting,
    required this.isNextEnabled,
    required this.skipLabel,
    required this.completeLabel,
    required this.onBack,
    required this.onNext,
  });

  final bool isFirstStep;
  final bool isLastStep;
  final bool showSkip;
  final bool isSubmitting;
  final bool isNextEnabled;
  final String skipLabel;
  final String completeLabel;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final effectiveShowSkip = showSkip && !isLastStep;
    final actionWidth = effectiveShowSkip
        ? 168.0
        : isLastStep
        ? 184.0
        : 95.0;

    return Row(
      mainAxisAlignment: isFirstStep
          ? MainAxisAlignment.end
          : MainAxisAlignment.spaceBetween,
      children: [
        if (!isFirstStep)
          _ProfileSetupButton(
            width: 95,
            isOutlined: true,
            isEnabled: !isSubmitting,
            onPressed: onBack,
            child: const Icon(Icons.chevron_left_rounded, size: 56),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: actionWidth,
          height: 72,
          child: _ProfileSetupButton(
            width: actionWidth,
            isEnabled: !isSubmitting && isNextEnabled,
            onPressed: onNext,
            child: isSubmitting
                ? SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colorScheme.onSurface,
                    ),
                  )
                : Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        height: 56,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (effectiveShowSkip)
                              Text(
                                skipLabel,
                                style: context.textTheme.headlineSmall?.copyWith(
                                  color: context.colorScheme.onSurface,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                  height: 1,
                                  letterSpacing: .32,
                                ),
                              ),
                            if (isLastStep)
                              Text(
                                completeLabel,
                                style: context.textTheme.titleLarge?.copyWith(
                                  color: context.colorScheme.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (effectiveShowSkip || isLastStep)
                              const SizedBox(width: 4),
                            Icon(
                              isLastStep
                                  ? Icons.check_rounded
                                  : Icons.chevron_right_rounded,
                              size: isLastStep ? 36 : 56,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ProfileSetupButton extends StatelessWidget {
  const _ProfileSetupButton({
    required this.width,
    required this.isEnabled,
    required this.onPressed,
    required this.child,
    this.isOutlined = false,
  });

  final double width;
  final bool isEnabled;
  final bool isOutlined;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 72,
      child: isOutlined
          ? OutlinedButton(
              onPressed: isEnabled ? onPressed : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colorScheme.outline,
                side: BorderSide(color: context.colorScheme.outline, width: 2),
                shape: const StadiumBorder(),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: child,
            )
          : FilledButton(
              onPressed: isEnabled ? onPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: context.colorScheme.primary,
                foregroundColor: context.colorScheme.onSurface,
                disabledBackgroundColor: context.colorScheme.outline,
                disabledForegroundColor: context.colorScheme.onSurfaceVariant,
                shape: const StadiumBorder(),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: child,
            ),
    );
  }
}
