import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/settings/widgets/settings_bottom_sheets.dart';
import 'package:yap_chat/features/settings/widgets/settings_widgets.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _searchByUsername = true;
  bool _searchByPhone = true;
  bool _searchByName = true;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: SettingsPageAppBar(title: context.l10n.settingsPrivacy),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, 130, 0, mediaQuery.padding.bottom + 24),
        children: [
          SettingsRow(
            icon: Icons.block_outlined,
            title: context.l10n.settingsBlacklist,
            onTap: () => showBlacklistSheet(context),
          ),
          const SizedBox(height: 22),
          SettingsToggleRow(
            icon: Icons.alternate_email_rounded,
            title: context.l10n.settingsSearchByUsername,
            value: _searchByUsername,
            onChanged: (value) => setState(() => _searchByUsername = value),
          ),
          SettingsToggleRow(
            icon: Icons.phone_outlined,
            title: context.l10n.settingsSearchByPhone,
            value: _searchByPhone,
            onChanged: (value) => setState(() => _searchByPhone = value),
          ),
          SettingsToggleRow(
            icon: Icons.person_outline_rounded,
            title: context.l10n.settingsSearchByName,
            value: _searchByName,
            onChanged: (value) => setState(() => _searchByName = value),
          ),
        ],
      ),
    );
  }
}
