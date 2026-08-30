import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';
import 'settings_widgets.dart';

Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: context.scaffoldBackgroundColor,
    barrierColor: context.colorScheme.primary.withValues(alpha: .22),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => BlocBuilder<AppLanguageCubit, AppLanguageState>(
      builder: (context, state) => _SettingsBottomSheet(
        title: context.l10n.settingsLanguage,
        child: _LanguageSheet(
          selected: state.language,
          isSaving: state.isSaving,
          onChanged: context.read<AppLanguageCubit>().select,
        ),
      ),
    ),
  );
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({
    required this.selected,
    required this.isSaving,
    required this.onChanged,
  });

  final AppLanguage selected;
  final bool isSaving;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final language in AppLanguage.values)
          _LanguageChoice(
            label: switch (language) {
              AppLanguage.russian => context.l10n.settingsLanguageRussian,
              AppLanguage.english => context.l10n.settingsLanguageEnglish,
            },
            value: language,
            selected: selected,
            onSelected: isSaving ? null : onChanged,
          ),
      ],
    );
  }
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final AppLanguage value;
  final AppLanguage selected;
  final ValueChanged<AppLanguage>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return InkWell(
      onTap: onSelected == null ? null : () => onSelected!(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: settingsValueStyle(context))),
            Checkbox(
              value: selected == value,
              activeColor: colorScheme.primary,
              checkColor: colorScheme.onPrimary,
              side: BorderSide(color: colorScheme.outline, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              onChanged: onSelected == null ? null : (_) => onSelected!(value),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: context.scaffoldBackgroundColor,
    barrierColor: context.colorScheme.primary.withValues(alpha: .22),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => _SettingsBottomSheet(
      title: context.l10n.settingsHelp,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Center(
          child: Text(
            context.l10n.settingsComingSoon,
            textAlign: TextAlign.center,
            style: settingsValueStyle(context),
          ),
        ),
      ),
    ),
  );
}

Future<void> showAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: context.scaffoldBackgroundColor,
    barrierColor: context.colorScheme.primary.withValues(alpha: .22),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => _SettingsBottomSheet(
      title: context.l10n.settingsAbout,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetTextRow(
              text: context.l10n.settingsTerms,
              onTap: () => _openLegalDocument(context, 'TERMS_OF_SERVICE_URL'),
            ),
            _SheetTextRow(
              text: context.l10n.settingsPrivacyPolicy,
              onTap: () => _openLegalDocument(context, 'PRIVACY_POLICY_URL'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showBlacklistSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: context.scaffoldBackgroundColor,
    barrierColor: context.colorScheme.primary.withValues(alpha: .22),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => const _BlacklistSheet(),
  );
}

class _BlacklistSheet extends StatefulWidget {
  const _BlacklistSheet();

  @override
  State<_BlacklistSheet> createState() => _BlacklistSheetState();
}

class _BlacklistSheetState extends State<_BlacklistSheet> {
  final _searchController = TextEditingController();
  final List<Friend> _blockedFriends = const [];
  String _query = '';
  final bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final searchBottom = keyboardInset > 0
        ? keyboardInset + 12
        : mediaQuery.viewPadding.bottom + 12;
    const headerHeight = 106.0;
    final contentBottomPadding = searchBottom + 62;
    final heightFactor = mediaQuery.orientation == Orientation.landscape
        ? .86
        : .80;
    final double sheetHeight = mediaQuery.size.height * heightFactor;
    final filteredFriends = _blockedFriends
        .where((friend) {
          final query = _query.trim().toLowerCase();
          return query.isEmpty ||
              friend.displayName.toLowerCase().contains(query) ||
              friend.username.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return SizedBox(
      width: double.infinity,
      height: sheetHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: _BlacklistBody(
              friends: filteredFriends,
              isLoading: _isLoading,
              topPadding: headerHeight,
              bottomPadding: contentBottomPadding,
            ),
          ),
          GradientOverlay(
            height: headerHeight + 24,
            isTop: true,
            backgroundColor: context.scaffoldBackgroundColor,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colorScheme.onSurfaceVariant.withValues(
                      alpha: .7,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.l10n.settingsBlacklist.toLowerCase(),
                      style: AppTextStyles.titleLargeFlex.copyWith(
                        color: context.colorScheme.onSurface,
                        fontSize: 32,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutQuad,
            left: 0,
            right: 0,
            bottom: searchBottom,
            child: GlassSearchBar(
              controller: _searchController,
              hintText: context.l10n.settingsSearchBlacklist,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlacklistBody extends StatelessWidget {
  const _BlacklistBody({
    required this.friends,
    required this.isLoading,
    required this.topPadding,
    required this.bottomPadding,
  });

  final List<Friend> friends;
  final bool isLoading;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Padding(
        padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
        child: Center(
          child: CircularProgressIndicator(color: context.colorScheme.primary),
        ),
      );
    }
    if (friends.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: topPadding + 64, left: 24, right: 24),
          child: Text(
            context.l10n.settingsNobodyHere,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colorScheme.onSurfaceVariant,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
        return SettingsFriendRow(
          avatar: UserAvatar(
            avatarUrl: friend.avatarUrl,
            avatarLoader: () =>
                context.read<IFriendsRepository>().resolveFriendAvatar(friend),
            avatarRevision: friend.avatarStoragePath ?? friend.avatarUrl,
            size: 54,
            borderRadius: 12,
          ),
          name: friend.displayName,
          username: friend.username,
          isVisible: true,
          onToggle: () {},
          trailingIcon: Icons.settings_rounded,
          horizontalPadding: 16,
        );
      },
    );
  }
}

class _SettingsBottomSheet extends StatelessWidget {
  const _SettingsBottomSheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.min(screen.width, 720),
        maxHeight: screen.height * .72,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colorScheme.onSurfaceVariant.withValues(
                    alpha: .7,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title.toLowerCase(),
                    style: AppTextStyles.titleLargeFlex.copyWith(
                      color: context.colorScheme.onSurface,
                      fontSize: 32,
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openLegalDocument(BuildContext context, String envKey) async {
  final rawUrl = context.read<AppConfig>().env[envKey];
  final url = rawUrl == null ? null : Uri.tryParse(rawUrl);
  if (url != null) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

class _SheetTextRow extends StatelessWidget {
  const _SheetTextRow({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(text.toLowerCase(), style: settingsValueStyle(context)),
        ),
      ),
    );
  }
}
