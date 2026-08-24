import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/friends/widgets/widgets.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class AddFriendPage extends StatelessWidget {
  const AddFriendPage({super.key});

  @override
  Widget build(BuildContext context) => const _AddFriendView();
}

class _AddFriendView extends StatelessWidget {
  const _AddFriendView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: context.scaffoldBackgroundColor,
      appBar: PrimaryAppBar(title: context.l10n.friendsAddTitle),
      body: const _AddFriendBody(),
    );
  }
}

class _AddFriendBody extends StatelessWidget {
  const _AddFriendBody();

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = math.max(16.0, (constraints.maxWidth - 720) / 2);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontal + systemPadding.left,
            130,
            horizontal + systemPadding.right,
            systemPadding.bottom + 24,
          ),
          children: [
            AddFriendMethodTile(
              icon: Icons.contacts_rounded,
              title: context.l10n.friendsAddContacts,
              onTap: () => _openContacts(context),
            ),
            AddFriendMethodTile(
              icon: Icons.alternate_email_rounded,
              title: context.l10n.friendsAddByUsername,
              trailing: context.l10n.friendsAddComingSoon,
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 5),
              child: Text(
                context.l10n.friendsAddSocialNetworks,
                style: context.textTheme.headlineSmall?.copyWith(
                  color: context.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            AddFriendMethodTile(
              icon: Icons.send_rounded,
              title: context.l10n.friendsSocialTelegram,
              trailing: context.l10n.friendsAddComingSoon,
            ),
            AddFriendMethodTile(
              icon: Icons.people_alt_rounded,
              title: context.l10n.friendsSocialVk,
              trailing: context.l10n.friendsAddComingSoon,
            ),
            AddFriendMethodTile(
              icon: Icons.chat_rounded,
              title: context.l10n.friendsSocialWhatsapp,
              trailing: context.l10n.friendsAddComingSoon,
            ),
          ],
        );
      },
    );
  }

  Future<void> _openContacts(BuildContext context) async {
    final repository = context.read<IContactsRepository>();
    try {
      final status = await repository.requestPermission();
      if (!context.mounted) return;
      if (status == ContactsPermissionStatus.permanentlyDenied) {
        await showPermissionDeniedDialog(
          context,
          title: context.l10n.friendsContactsPermissionTitle,
          content: context.l10n.friendsContactsPermissionDescription,
          onOpenSettings: repository.openAppSettings,
        );
        return;
      }
      if (status != ContactsPermissionStatus.granted) return;

      await showContactDiscoverySheet(
        context,
        username: context.read<AuthBloc>().state.profile?.username,
      );
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.friendsContactsLoadFailed,
        type: SnackBarType.error,
      );
    }
  }
}
