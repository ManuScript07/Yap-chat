import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/widgets/settings_widgets.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

class VisibilitySettingsPage extends StatelessWidget {
  const VisibilitySettingsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        LocationVisibilityCubit(repository: context.read<ISettingsRepository>())
          ..load(),
    child: const _VisibilitySettingsView(),
  );
}

class _VisibilitySettingsView extends StatefulWidget {
  const _VisibilitySettingsView();

  @override
  State<_VisibilitySettingsView> createState() =>
      _VisibilitySettingsViewState();
}

class _VisibilitySettingsViewState extends State<_VisibilitySettingsView> {
  late final Stream<List<Friend>> _friends;

  @override
  void initState() {
    super.initState();
    _friends = context.read<IFriendsRepository>().watchFriends();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return BlocListener<LocationVisibilityCubit, LocationVisibilityState>(
      listenWhen: (previous, current) =>
          previous.feedbackId != current.feedbackId && current.feedback != null,
      listener: (context, state) {
        final message = switch (state.feedback) {
          LocationVisibilityFeedback.success =>
            context.l10n.settingsPrivacySaved,
          LocationVisibilityFeedback.failure =>
            context.l10n.settingsPrivacySaveFailed,
          null => null,
        };
        if (message == null) return;
        showAppSnackBar(
          context,
          message: message,
          type: state.feedback == LocationVisibilityFeedback.success
              ? SnackBarType.success
              : SnackBarType.error,
        );
      },
      child: Scaffold(
        backgroundColor: context.scaffoldBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: SettingsPageAppBar(
          title: context.l10n.settingsVisibility,
          wrapAfterFirstWord: true,
        ),
        body: BlocBuilder<LocationVisibilityCubit, LocationVisibilityState>(
          builder: (context, state) {
            final settings = state.settings;
            if (settings == null) {
              return Center(
                child: state.status == LocationVisibilityStatus.failure
                    ? Text(
                        context.l10n.settingsPrivacyLoadFailed,
                        style: settingsValueStyle(context),
                      )
                    : const CircularProgressIndicator(),
              );
            }
            final isLoading = state.status == LocationVisibilityStatus.loading;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                0,
                130,
                0,
                mediaQuery.padding.bottom + 24,
              ),
              children: [
                SettingsToggleRow(
                  icon: Icons.near_me_outlined,
                  title: context.l10n.settingsShareLocation,
                  value: settings.sharePreciseLocation,
                  isLoading: isLoading,
                  isSaving: state.isSaving,
                  onChanged: isLoading
                      ? null
                      : (value) => context
                            .read<LocationVisibilityCubit>()
                            .setGlobal(sharePreciseLocation: value),
                ),
                SettingsToggleRow(
                  icon: Icons.social_distance_outlined,
                  title: context.l10n.settingsShareDistance,
                  value: settings.shareDistance,
                  isLoading: isLoading,
                  isSaving: state.isSaving,
                  onChanged: isLoading
                      ? null
                      : (value) => context
                            .read<LocationVisibilityCubit>()
                            .setGlobal(shareDistance: value),
                ),
                const SizedBox(height: 24),
                StreamBuilder<List<Friend>>(
                  stream: _friends,
                  builder: (context, snapshot) => _FriendsVisibilityList(
                    snapshot: snapshot,
                    exactLocationEnabled: settings.sharePreciseLocation,
                    excludedFriendIds: state.excludedFriendIds,
                    isSaving: state.isSaving || isLoading,
                  ),
                ),
                if (state.status == LocationVisibilityStatus.failure)
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

class _FriendsVisibilityList extends StatelessWidget {
  const _FriendsVisibilityList({
    required this.snapshot,
    required this.exactLocationEnabled,
    required this.excludedFriendIds,
    required this.isSaving,
  });

  final AsyncSnapshot<List<Friend>> snapshot;
  final bool exactLocationEnabled;
  final Set<String> excludedFriendIds;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Center(
          child: CircularProgressIndicator(color: context.colorScheme.primary),
        ),
      );
    }
    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Center(
          child: Text(
            context.l10n.friendsLoadFailed,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colorScheme.onSurface),
          ),
        ),
      );
    }
    final friends = snapshot.data ?? const <Friend>[];
    if (friends.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Center(
          child: Text(
            context.l10n.settingsNobodyHere,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colorScheme.onSurface),
          ),
        ),
      );
    }
    final visibleCount = exactLocationEnabled
        ? friends
              .where((friend) => !excludedFriendIds.contains(friend.id))
              .length
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            16 + MediaQuery.paddingOf(context).left,
            0,
            16 + MediaQuery.paddingOf(context).right,
            0,
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${context.l10n.settingsFriendsSeeGeo} ',
                  style: TextStyle(
                    color: context.colorScheme.onSurfaceVariant,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: .4,
                  ),
                ),
                TextSpan(
                  text: '$visibleCount',
                  style: TextStyle(
                    color: context.colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final friend in friends)
          _FriendVisibilityRow(
            friend: friend,
            isVisible: !excludedFriendIds.contains(friend.id),
            isSaving: isSaving,
            exactLocationEnabled: exactLocationEnabled,
          ),
      ],
    );
  }
}

class _FriendVisibilityRow extends StatelessWidget {
  const _FriendVisibilityRow({
    required this.friend,
    required this.isVisible,
    required this.isSaving,
    required this.exactLocationEnabled,
  });

  final Friend friend;
  final bool isVisible;
  final bool isSaving;
  final bool exactLocationEnabled;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: isSaving || !exactLocationEnabled,
    child: SettingsFriendRow(
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
      isVisible: exactLocationEnabled && isVisible,
      onToggle: () => context.read<LocationVisibilityCubit>().setFriendExcluded(
        friend.id,
        excluded: isVisible,
      ),
    ),
  );
}
