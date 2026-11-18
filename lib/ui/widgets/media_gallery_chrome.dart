import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

import 'glass_icon_button.dart';

/// Keep the controls mounted out of sight until the moving photo has landed.
class MediaGalleryChromeVisibility extends StatelessWidget {
  const MediaGalleryChromeVisibility({
    super.key,
    required this.settled,
    required this.visible,
    required this.child,
  });

  final bool settled;
  final bool visible;
  final Widget child;
  static const animationDuration = Duration(milliseconds: 140);

  @override
  Widget build(BuildContext context) {
    final shown = settled && visible;
    return IgnorePointer(
      ignoring: !shown,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: settled ? animationDuration : Duration.zero,
        curve: Curves.easeInOut,
        child: child,
      ),
    );
  }
}

class MediaGalleryHeader extends StatelessWidget {
  const MediaGalleryHeader({
    super.key,
    required this.name,
    required this.date,
    required this.avatar,
    required this.onBack,
    required this.onSave,
    this.backLabel,
    this.saveLabel,
  });

  static const buttonSize = 44.0;
  final String name;
  final String date;
  final Widget avatar;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final String? backLabel;
  final String? saveLabel;

  static Widget backButton(VoidCallback onTap) => GlassIconButton(
    icon: Icons.arrow_back_rounded,
    onTap: onTap,
    width: buttonSize,
    height: buttonSize,
    borderRadius: 16,
    iconSize: 26,
  );

  static Widget saveButton(VoidCallback onTap) => GlassIconButton(
    icon: Icons.download_rounded,
    onTap: onTap,
    width: buttonSize,
    height: buttonSize,
    borderRadius: 16,
    iconSize: 24,
  );

  @override
  Widget build(BuildContext context) {
    final save = saveButton(onSave);
    final back = backButton(onBack);
    return Row(
      children: [
        if (backLabel case final label?)
          Tooltip(message: label, child: back)
        else
          back,
        const SizedBox(width: 12),
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .68),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: .2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (saveLabel case final label?)
          Tooltip(message: label, child: save)
        else
          save,
      ],
    );
  }
}

class MediaGalleryCounter extends StatelessWidget {
  const MediaGalleryCounter({
    super.key,
    required this.index,
    required this.total,
  });

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) => Center(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.scrim.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          context.l10n.profilePhotoCounter(index + 1, total),
          style: TextStyle(
            color: context.colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: .3,
          ),
        ),
      ),
    ),
  );
}
