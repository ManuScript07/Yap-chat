import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/settings/view/privacy_settings_page.dart';
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
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            16 + mediaQuery.padding.left,
                            0,
                            16 + mediaQuery.padding.right,
                            0,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Semantics(
                              button: telegramUrl != null,
                              label: 'Telegram',
                              child: GestureDetector(
                                onTap: telegramUrl == null
                                    ? null
                                    : () => _openTelegram(telegramUrl),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: SvgPicture.asset(
                                    'assets/logo/telegram_logo.svg',
                                    width: 34,
                                    height: 34,
                                    colorFilter: ColorFilter.mode(
                                      context.colorScheme.onSurfaceVariant,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
                    _SettingsTextAction(
                      title: context.l10n.settingsDeleteAccount,
                      onTap: () => _showComingSoon(context),
                    ),
                    SizedBox(height: mediaQuery.padding.bottom + 24),
                  ],
                ),
              ),
            ],
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

  Future<void> _openTelegram(String rawUrl) async {
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

  void _showComingSoon(BuildContext context) {
    showAppSnackBar(
      context,
      message: context.l10n.settingsComingSoon,
      type: SnackBarType.info,
    );
  }
}

class _SettingsTextAction extends StatelessWidget {
  const _SettingsTextAction({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16 + MediaQuery.paddingOf(context).left,
          10,
          16 + MediaQuery.paddingOf(context).right,
          10,
        ),
        child: Text(title.toLowerCase(), style: settingsValueStyle(context)),
      ),
    );
  }
}
