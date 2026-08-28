import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/settings/widgets/settings_widgets.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

class VisibilitySettingsPage extends StatefulWidget {
  const VisibilitySettingsPage({super.key});

  @override
  State<VisibilitySettingsPage> createState() => _VisibilitySettingsPageState();
}

class _VisibilitySettingsPageState extends State<VisibilitySettingsPage> {
  bool _shareLocation = true;
  final _friendVisibility = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: SettingsPageAppBar(
        title: context.l10n.settingsVisibility,
        wrapAfterFirstWord: true,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, 130, 0, mediaQuery.padding.bottom + 24),
        children: [
          SettingsToggleRow(
            icon: Icons.near_me_outlined,
            title: context.l10n.settingsShareLocation,
            value: _shareLocation,
            onChanged: (value) => setState(() => _shareLocation = value),
          ),
          const SizedBox(height: 24),
          StreamBuilder<List<Friend>>(
            stream: context.read<IFriendsRepository>().watchFriends(),
            builder: (context, snapshot) => _buildFriends(context, snapshot),
          ),
        ],
      ),
    );
  }

  Widget _buildFriends(
    BuildContext context,
    AsyncSnapshot<List<Friend>> snapshot,
  ) {
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

    final visibleCount = _shareLocation
        ? friends.where((friend) => _friendVisibility[friend.id] ?? true).length
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
        for (final friend in friends) _friendRow(context, friend),
      ],
    );
  }

  Widget _friendRow(BuildContext context, Friend friend) {
    final isVisible = _friendVisibility[friend.id] ?? true;
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
      isVisible: isVisible,
      onToggle: () => setState(() => _friendVisibility[friend.id] = !isVisible),
    );
  }
}
