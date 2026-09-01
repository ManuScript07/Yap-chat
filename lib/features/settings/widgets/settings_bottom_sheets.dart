import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';
import 'settings_widgets.dart';

Future<bool?> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: context.scaffoldBackgroundColor,
    barrierColor: context.colorScheme.primary.withValues(alpha: .22),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => BlocListener<AppLanguageCubit, AppLanguageState>(
      listenWhen: (previous, current) =>
          previous.feedbackId != current.feedbackId &&
          current.feedback == AppLanguageFeedback.success,
      listener: (context, _) => Navigator.of(context).pop(true),
      child: BlocBuilder<AppLanguageCubit, AppLanguageState>(
        builder: (context, state) => _SettingsBottomSheet(
          title: context.l10n.settingsLanguage,
          child: _LanguageSheet(
            selected: state.language,
            isSaving: state.isSaving,
            onChanged: context.read<AppLanguageCubit>().select,
          ),
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
    builder: (_) => BlocBuilder<AppPublicContentCubit, AppPublicContentState>(
      builder: (context, state) => _SettingsBottomSheet(
        title: context.l10n.settingsHelp,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: _SupportEmailRow(email: state.content?.supportEmail),
        ),
      ),
    ),
  );
}

class _SupportEmailRow extends StatelessWidget {
  const _SupportEmailRow({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final value = email;
    if (value == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          context.l10n.settingsPublicContentUnavailable,
          style: settingsValueStyle(context),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: _SheetTextRow(
            text: value,
            onTap: () => _openMailClient(value),
          ),
        ),
        IconButton(
          tooltip: context.l10n.settingsCopyEmail,
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!context.mounted) return;
            showAppSnackBar(
              context,
              message: context.l10n.settingsEmailCopied,
              type: SnackBarType.success,
            );
          },
        ),
      ],
    );
  }
}

Future<void> _openMailClient(String email) async {
  final uri = Uri(scheme: 'mailto', path: email);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // The platform may not have a mail handler; copying remains available.
  }
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
    builder: (_) => BlocBuilder<AppPublicContentCubit, AppPublicContentState>(
      builder: (context, state) {
        final content = state.content;
        final languageCode = Localizations.localeOf(context).languageCode;
        return _SettingsBottomSheet(
          title: context.l10n.settingsAbout,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetTextRow(
                  text: context.l10n.settingsTerms,
                  onTap: _legalTap(
                    context,
                    content?.legalUrl(LegalDocument.terms, languageCode),
                  ),
                ),
                _SheetTextRow(
                  text: context.l10n.settingsPrivacyPolicy,
                  onTap: _legalTap(
                    context,
                    content?.legalUrl(
                      LegalDocument.privacyPolicy,
                      languageCode,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

VoidCallback? _legalTap(BuildContext context, String? url) {
  return () {
    if (url == null) {
      showAppSnackBar(
        context,
        message: context.l10n.settingsPublicContentUnavailable,
        type: SnackBarType.error,
      );
      return;
    }
    _openPublicDocument(context, url);
  };
}

Future<void> _openPublicDocument(BuildContext context, String rawUrl) async {
  final url = Uri.tryParse(rawUrl);
  if (url == null || url.scheme != 'https' || url.host.isEmpty) {
    showAppSnackBar(
      context,
      message: context.l10n.settingsPublicContentUnavailable,
      type: SnackBarType.error,
    );
    return;
  }
  bool opened;
  try {
    opened = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
  } catch (_) {
    opened = false;
  }
  if (!context.mounted || opened) return;
  showAppSnackBar(
    context,
    message: context.l10n.settingsPublicContentUnavailable,
    type: SnackBarType.error,
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
  List<BlockedUser> _blockedUsers = const [];
  String _query = '';
  bool _isLoading = true;
  StreamSubscription<List<BlockedUser>>? _subscription;

  @override
  void initState() {
    super.initState();
    final repository = context.read<IBlocklistRepository>();
    _subscription = repository.watchBlockedUsers().listen((users) {
      if (mounted) setState(() => _blockedUsers = users);
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await context.read<BlocklistCubit>().refreshIfStale();
    } catch (_) {
      if (mounted && !context.read<BlocklistCubit>().state.isLoaded) {
        showAppSnackBar(
          context,
          message: context.l10n.settingsBlacklistLoadFailed,
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final heightFactor = isLandscape ? .88 : .84;
    final referenceHeightFactor = isLandscape ? .86 : .80;
    final heightScale = heightFactor / referenceHeightFactor;
    final sheetHeight = mediaQuery.size.height * heightFactor;
    final headerHeight = 106.0 * heightScale;
    final emptyStateTopPadding = headerHeight + 64 * heightScale;
    final contentBottomPadding = searchBottom + 62;
    final filteredUsers = _blockedUsers
        .where((user) {
          final query = _query.trim().toLowerCase();
          return query.isEmpty ||
              user.displayName.toLowerCase().contains(query) ||
              user.username.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return SizedBox(
      width: double.infinity,
      height: sheetHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              removeRight: true,
              child: BlocBuilder<BlocklistCubit, BlocklistState>(
                builder: (context, blocklistState) => _BlacklistBody(
                  users: filteredUsers,
                  isLoading: _isLoading && !blocklistState.isLoaded,
                  topPadding: headerHeight,
                  emptyStateTopPadding: emptyStateTopPadding,
                  bottomPadding: contentBottomPadding,
                ),
              ),
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
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              removeRight: true,
              child: GlassSearchBar(
                controller: _searchController,
                hintText: context.l10n.settingsSearchBlacklist,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlacklistBody extends StatelessWidget {
  const _BlacklistBody({
    required this.users,
    required this.isLoading,
    required this.topPadding,
    required this.emptyStateTopPadding,
    required this.bottomPadding,
  });

  final List<BlockedUser> users;
  final bool isLoading;
  final double topPadding;
  final double emptyStateTopPadding;
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
    if (users.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
            top: emptyStateTopPadding,
            left: 24,
            right: 24,
          ),
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
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return InkWell(
          onTap: () => openViewedProfile(context, userId: user.id),
          child: BlocBuilder<BlocklistCubit, BlocklistState>(
            builder: (context, state) => SettingsFriendRow(
              avatar: UserAvatar(
                avatarUrl: user.avatarUrl,
                avatarRevision: user.avatarStoragePath ?? user.avatarUrl,
                size: 54,
                borderRadius: 12,
              ),
              name: user.displayName,
              username: user.username,
              isVisible: true,
              isBusy: state.isPending(user.id),
              onToggle: () => _confirmUnblock(context, user),
              trailingIcon: Icons.lock_open_rounded,
              horizontalPadding: 16,
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmUnblock(BuildContext context, BlockedUser user) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: context.l10n.unblockUserTitle,
      content: context.l10n.unblockUserContent(user.displayName),
      confirmLabel: context.l10n.unblockUser,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<IBlocklistRepository>().unblockUser(user.id);
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsActionFailed,
          type: SnackBarType.error,
        );
      }
    }
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
