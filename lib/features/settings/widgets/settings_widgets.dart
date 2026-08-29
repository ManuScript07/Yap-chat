import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';

class SettingsPageAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const SettingsPageAppBar({
    super.key,
    required this.title,
    this.wrapAfterFirstWord = false,
  });

  final String title;
  final bool wrapAfterFirstWord;

  @override
  Widget build(BuildContext context) {
    final titleText = title.toLowerCase();
    final shouldWrap =
        wrapAfterFirstWord &&
        MediaQuery.orientationOf(context) != Orientation.landscape;
    final displayedTitle = shouldWrap
        ? titleText.replaceFirst(' ', '\n')
        : titleText;

    return PrimaryAppBar(
      title: '',
      titleWidget: Text(
        displayedTitle,
        maxLines: shouldWrap ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.titleLargeFlex.copyWith(fontSize: 32),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(130);
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Material(
      color: colorScheme.surface.withValues(alpha: 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16 + MediaQuery.paddingOf(context).left,
            10,
            16 + MediaQuery.paddingOf(context).right,
            10,
          ),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.onSurface, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title.toLowerCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: .5,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 32,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.isLoading = false,
    this.isSaving = false,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isLoading;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Material(
      color: colorScheme.surface.withValues(alpha: 0),
      child: InkWell(
        onTap: isLoading || isSaving || onChanged == null
            ? null
            : () => onChanged!(!value),
        borderRadius: BorderRadius.zero,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16 + MediaQuery.paddingOf(context).left,
            6,
            16 + MediaQuery.paddingOf(context).right,
            6,
          ),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.onSurface, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title.toLowerCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: .5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IgnorePointer(
                ignoring: isLoading || isSaving || onChanged == null,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: colorScheme.primary,
                  activeThumbColor: colorScheme.onPrimary,
                  inactiveTrackColor: colorScheme.surface.withValues(alpha: .18),
                  inactiveThumbColor: colorScheme.onSurfaceVariant,
                  trackOutlineColor: WidgetStatePropertyAll(
                    colorScheme.surface.withValues(alpha: 0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle settingsValueStyle(BuildContext context) => TextStyle(
  color: context.colorScheme.onSurfaceVariant,
  fontSize: 20,
  fontWeight: FontWeight.w700,
  height: 1.2,
  letterSpacing: .5,
);

class SettingsFriendRow extends StatelessWidget {
  const SettingsFriendRow({
    super.key,
    required this.avatar,
    required this.name,
    required this.username,
    required this.isVisible,
    required this.onToggle,
    this.trailingIcon = Icons.visibility_rounded,
    this.horizontalPadding = 16,
  });

  final Widget avatar;
  final String name;
  final String username;
  final bool isVisible;
  final VoidCallback onToggle;
  final IconData trailingIcon;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding + MediaQuery.paddingOf(context).left,
        8,
        horizontalPadding + MediaQuery.paddingOf(context).right,
        8,
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.chatName.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  '@$username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.messagePreview.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onToggle,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(
              trailingIcon == Icons.visibility_rounded && !isVisible
                  ? Icons.visibility_off_rounded
                  : trailingIcon,
              color: colorScheme.onSurface,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}
