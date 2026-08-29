import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/features/settings/widgets/settings_bottom_sheets.dart';
import 'package:yap_chat/features/settings/widgets/settings_widgets.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

class PrivacySettingsPage extends StatelessWidget {
  const PrivacySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          PrivacySettingsCubit(repository: context.read<ISettingsRepository>())
            ..load(),
      child: const _PrivacySettingsView(),
    );
  }
}

class _PrivacySettingsView extends StatelessWidget {
  const _PrivacySettingsView();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return BlocListener<PrivacySettingsCubit, PrivacySettingsState>(
      listenWhen: (previous, current) =>
          previous.feedbackId != current.feedbackId && current.feedback != null,
      listener: (context, state) {
        final feedback = state.feedback;
        if (feedback == PrivacySettingsFeedback.success) {
          showAppSnackBar(
            context,
            message: context.l10n.settingsPrivacySaved,
            type: SnackBarType.success,
          );
        } else if (feedback == PrivacySettingsFeedback.failure) {
          showAppSnackBar(
            context,
            message: context.l10n.settingsPrivacySaveFailed,
            type: SnackBarType.error,
          );
        }
      },
      child: Scaffold(
        backgroundColor: context.scaffoldBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: SettingsPageAppBar(title: context.l10n.settingsPrivacy),
        body: BlocBuilder<PrivacySettingsCubit, PrivacySettingsState>(
          builder: (context, state) {
            final isLoading =
                state.status == PrivacySettingsStatus.initial ||
                state.status == PrivacySettingsStatus.loading;
            final settings = state.settings;
            if (settings == null) {
              return Center(
                child: state.status == PrivacySettingsStatus.failure
                    ? Text(
                        context.l10n.settingsPrivacyLoadFailed,
                        style: settingsValueStyle(context),
                      )
                    : const CircularProgressIndicator(),
              );
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(
                0,
                130,
                0,
                mediaQuery.padding.bottom + 24,
              ),
              children: [
                SettingsRow(
                  icon: Icons.block_outlined,
                  title: context.l10n.settingsBlacklist,
                  onTap: isLoading ? null : () => showBlacklistSheet(context),
                ),
                const SizedBox(height: 22),
                SettingsToggleRow(
                  icon: Icons.alternate_email_rounded,
                  title: context.l10n.settingsSearchByUsername,
                  value: settings.searchByUsername,
                  isLoading: isLoading,
                  isSaving: state.isSaving,
                  onChanged: isLoading
                      ? null
                      : (value) => context
                          .read<PrivacySettingsCubit>()
                          .setValue(SearchPrivacySettingKey.username, value),
                ),
                SettingsToggleRow(
                  icon: Icons.phone_outlined,
                  title: context.l10n.settingsSearchByPhone,
                  value: settings.searchByPhone,
                  isLoading: isLoading,
                  isSaving: state.isSaving,
                  onChanged: isLoading
                      ? null
                      : (value) => context
                          .read<PrivacySettingsCubit>()
                          .setValue(SearchPrivacySettingKey.phone, value),
                ),
                SettingsToggleRow(
                  icon: Icons.person_outline_rounded,
                  title: context.l10n.settingsSearchByName,
                  value: settings.searchByName,
                  isLoading: isLoading,
                  isSaving: state.isSaving,
                  onChanged: isLoading
                      ? null
                      : (value) => context
                          .read<PrivacySettingsCubit>()
                          .setValue(SearchPrivacySettingKey.name, value),
                ),
                if (state.status == PrivacySettingsStatus.failure)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Text(
                      context.l10n.settingsPrivacyLoadFailed,
                      style: settingsValueStyle(context),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
