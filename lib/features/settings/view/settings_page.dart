import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/settings/view/privacy_settings_page.dart';
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

class _SettingsPage extends StatefulWidget {
  const _SettingsPage();

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  SettingsLanguage? _selectedLanguage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLanguage ??= Localizations.localeOf(context).languageCode == 'en'
        ? SettingsLanguage.english
        : SettingsLanguage.russian;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final selectedLanguage = _selectedLanguage!;
    return Scaffold(
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
                    settingsSlideRightRoute<void>(const PrivacySettingsPage()),
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
                    final value = await showLanguageSheet(
                      context,
                      selected: selectedLanguage,
                      onChanged: (value) {
                        if (mounted) setState(() => _selectedLanguage = value);
                      },
                    );
                    if (mounted && value != null) {
                      setState(() => _selectedLanguage = value);
                    }
                  },
                  trailing: Text(
                    _languageLabel(context, selectedLanguage),
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
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16 + mediaQuery.padding.left,
                    0,
                    16 + mediaQuery.padding.right,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      button: true,
                      label: 'Telegram',
                      child: GestureDetector(
                        onTap: _openTelegram,
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
                  onTap: _confirmLogout,
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
    );
  }

  String _languageLabel(BuildContext context, SettingsLanguage language) {
    return switch (language) {
      SettingsLanguage.russian => context.l10n.settingsLanguageRussian,
      SettingsLanguage.english => context.l10n.settingsLanguageEnglish,
    };
  }

  Future<void> _openTelegram() async {
    await launchUrl(
      Uri.parse('https://t.me/heyitsyap'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showConfirmationDialog(
      context,
      title: context.l10n.settingsLogoutConfirmationTitle,
      content: context.l10n.settingsLogoutConfirmationContent,
      confirmLabel: context.l10n.settingsLogoutConfirm,
    );
    if (!mounted || confirmed != true) return;
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
