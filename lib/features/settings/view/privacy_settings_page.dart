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
                const SizedBox(height: 28),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16 + mediaQuery.padding.left,
                  ),
                  child: Text(
                    context.l10n.settingsLastSeenVisibility,
                    style: TextStyle(
                      color: context.colorScheme.onSurfaceVariant,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final visibility in LastSeenVisibility.values)
                  _LastSeenVisibilityChoice(
                    visibility: visibility,
                    selected: settings.lastSeenVisibility,
                    isSaving: state.isSaving,
                    onSelected: (value) => context
                        .read<PrivacySettingsCubit>()
                        .setLastSeenVisibility(value),
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

class _LastSeenVisibilityChoice extends StatelessWidget {
  const _LastSeenVisibilityChoice({
    required this.visibility,
    required this.selected,
    required this.isSaving,
    required this.onSelected,
  });

  final LastSeenVisibility visibility;
  final LastSeenVisibility selected;
  final bool isSaving;
  final ValueChanged<LastSeenVisibility> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = switch (visibility) {
      LastSeenVisibility.all => context.l10n.settingsLastSeenAll,
      LastSeenVisibility.friends => context.l10n.settingsLastSeenFriends,
      LastSeenVisibility.nobody => context.l10n.settingsLastSeenNobody,
    };
    return Material(
      color: context.colorScheme.surface.withValues(alpha: 0),
      child: InkWell(
        onTap: isSaving ? null : () => onSelected(visibility),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20 + MediaQuery.paddingOf(context).left,
            2,
            20 + MediaQuery.paddingOf(context).right,
            2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: settingsValueStyle(context).copyWith(fontSize: 18),
                ),
              ),
              IgnorePointer(
                ignoring: isSaving,
                child: Checkbox(
                  value: selected == visibility,
                  activeColor: context.colorScheme.primary,
                  checkColor: context.colorScheme.onPrimary,
                  side: BorderSide(
                    color: context.colorScheme.outline,
                    width: 2,
                  ),
                  onChanged: (_) => onSelected(visibility),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
