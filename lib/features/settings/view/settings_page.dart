import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/settings/view/privacy_settings_page.dart';
import 'package:yap_chat/features/settings/view/app_diagnostics_page.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/features/settings/view/settings_routes.dart';
import 'package:yap_chat/features/settings/view/visibility_settings_page.dart';
import 'package:yap_chat/features/settings/widgets/settings_bottom_sheets.dart';
import 'package:yap_chat/features/settings/widgets/settings_widgets.dart';
import 'package:yap_chat/ui/ui.dart';

Future<void> showSettingsPage(BuildContext context) {
  return Navigator.of(
    context,
  ).push<void>(settingsSlideUpRoute<void>(const _SettingsPage()));
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return BlocListener<AppLanguageCubit, AppLanguageState>(
      listenWhen: (previous, current) =>
          previous.feedbackId != current.feedbackId &&
          current.feedback == AppLanguageFeedback.failure,
      listener: (context, state) {
        showAppSnackBar(
          context,
          message: context.l10n.settingsLanguageSaveFailed,
          type: SnackBarType.error,
        );
      },
      child: BlocListener<AuthBloc, AuthState>(
        listenWhen: (previous, current) =>
            previous.failure != current.failure &&
            current.failure == AuthFailure.accountDeletion,
        listener: (context, state) {
          showAppSnackBar(
            context,
            message: context.l10n.accountDeletionRequestFailed,
            type: SnackBarType.error,
          );
        },
        child: BlocBuilder<AppLanguageCubit, AppLanguageState>(
          builder: (context, languageState) => Scaffold(
            backgroundColor: context.scaffoldBackgroundColor,
            extendBodyBehindAppBar: true,
            appBar: SettingsPageAppBar(title: context.l10n.settingsTitle),
            body: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.only(top: 130),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      SettingsRow(
                        icon: Icons.privacy_tip_outlined,
                        title: context.l10n.settingsPrivacy,
                        onTap: () => Navigator.of(context).push<void>(
                          settingsSlideRightRoute<void>(
                            const PrivacySettingsPage(),
                          ),
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.visibility_outlined,
                        title: context.l10n.settingsVisibility,
                        onTap: () => Navigator.of(context).push<void>(
                          settingsSlideRightRoute<void>(
                            const VisibilitySettingsPage(),
                          ),
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.language_rounded,
                        title: context.l10n.settingsLanguage,
                        onTap: () async {
                          final saved = await showLanguageSheet(context);
                          if (!context.mounted || saved != true) return;
                          showAppSnackBar(
                            context,
                            message: context.l10n.settingsLanguageSaved,
                            type: SnackBarType.success,
                          );
                        },
                        trailing: Text(
                          _languageLabel(context, languageState.language),
                          style: settingsValueStyle(context),
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.help_outline_rounded,
                        title: context.l10n.settingsHelp,
                        onTap: () => showHelpSheet(context),
                      ),
                      SettingsRow(
                        icon: Icons.info_outline_rounded,
                        title: context.l10n.settingsAbout,
                        onTap: () => showAboutSheet(context),
                        onLongPress:
                            kDebugMode &&
                                (context
                                        .read<AppConfig>()
                                        .diagnostics
                                        ?.enabled ??
                                    false)
                            ? () => Navigator.of(context).push<void>(
                                settingsSlideRightRoute<void>(
                                  const AppDiagnosticsPage(),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 34),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          16 + mediaQuery.padding.left,
                          0,
                          16 + mediaQuery.padding.right,
                          0,
                        ),
                        child: Text(
                          context.l10n.settingsSocial.toLowerCase(),
                          style: settingsValueStyle(context),
                        ),
                      ),
                      const SizedBox(height: 14),
                      BlocBuilder<AppPublicContentCubit, AppPublicContentState>(
                        builder: (context, contentState) {
                          final telegramUrl = contentState.content?.telegramUrl;
                          final githubUrl = contentState.content?.githubUrl;
                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                              16 + mediaQuery.padding.left,
                              0,
                              16 + mediaQuery.padding.right,
                              0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _SocialLinkIcon(
                                  label: 'Telegram',
                                  assetPath: 'assets/logo/telegram_logo.svg',
                                  url: telegramUrl,
                                  onOpen: _openExternalUrl,
                                ),
                                const SizedBox(width: 10),
                                _SocialLinkIcon(
                                  label: 'GitHub',
                                  assetPath: 'assets/logo/github.svg',
                                  url: githubUrl,
                                  onOpen: _openExternalUrl,
                                  size: 40,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 44),
                    ]),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      _SettingsTextAction(
                        title: context.l10n.settingsLogout,
                        onTap: () => _confirmLogout(context),
                      ),
                      BlocBuilder<AuthBloc, AuthState>(
                        buildWhen: (previous, current) =>
                            previous.isSubmitting != current.isSubmitting,
                        builder: (context, authState) => _SettingsTextAction(
                          title: context.l10n.settingsDeleteAccount,
                          isBusy: authState.isSubmitting,
                          onTap: () => _confirmAccountDeletion(context),
                        ),
                      ),
                      SizedBox(height: mediaQuery.padding.bottom + 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _languageLabel(BuildContext context, AppLanguage language) {
    return switch (language) {
      AppLanguage.russian => context.l10n.settingsLanguageRussian,
      AppLanguage.english => context.l10n.settingsLanguageEnglish,
    };
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final url = Uri.tryParse(rawUrl);
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The link is optional and unavailable platform handlers are harmless.
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: context.l10n.settingsLogoutConfirmationTitle,
      content: context.l10n.settingsLogoutConfirmationContent,
      confirmLabel: context.l10n.settingsLogoutConfirm,
    );
    if (!context.mounted || confirmed != true) return;
    context.read<AuthBloc>().add(const AuthSignOutRequested());
  }

  Future<void> _confirmAccountDeletion(BuildContext context) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: context.l10n.settingsDeleteAccountConfirmationTitle,
      content: context.l10n.settingsDeleteAccountConfirmationContent,
      confirmLabel: context.l10n.settingsDeleteAccountConfirm,
    );
    if (!context.mounted || confirmed != true) return;
    context.read<AuthBloc>().add(const AuthAccountDeletionRequested());
  }
}

class _SocialLinkIcon extends StatelessWidget {
  const _SocialLinkIcon({
    required this.label,
    required this.assetPath,
    required this.url,
    required this.onOpen,
    this.size = 34,
  });

  final String label;
  final String assetPath;
  final String? url;
  final Future<void> Function(String url) onOpen;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: url != null,
    label: label,
    child: GestureDetector(
      onTap: url == null ? null : () => onOpen(url!),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: SvgPicture.asset(
          assetPath,
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(
            context.colorScheme.onSurfaceVariant,
            BlendMode.srcIn,
          ),
        ),
      ),
    ),
  );
}

class _SettingsTextAction extends StatelessWidget {
  const _SettingsTextAction({
    required this.title,
    required this.onTap,
    this.isBusy = false,
  });

  final String title;
  final VoidCallback onTap;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isBusy ? null : onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16 + MediaQuery.paddingOf(context).left,
          10,
          16 + MediaQuery.paddingOf(context).right,
          10,
        ),
        child: isBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(title.toLowerCase(), style: settingsValueStyle(context)),
      ),
    );
  }
}
