import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

class _AddFriendBody extends StatefulWidget {
  const _AddFriendBody();

  @override
  State<_AddFriendBody> createState() => _AddFriendBodyState();
}

class _AddFriendBodyState extends State<_AddFriendBody> {
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final horizontal = isLandscape
            ? 16.0
            : math.max(16.0, (constraints.maxWidth - 720) / 2);
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
            AddFriendMethodTile(
              icon: Icons.phone_rounded,
              title: context.l10n.friendsAddByPhone,
              trailing: context.l10n.friendsAddComingSoon,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                context.l10n.friendsAddSocialNetworks,
                style: context.textTheme.headlineSmall?.copyWith(
                  color: context.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _InviteFriendsCard(
              title: context.l10n.friendsAddInviteMore,
              buttonLabel: context.l10n.friendsContactsInvite,
              onTap: _isSharing ? null : () => _shareInvitation(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareInvitation(BuildContext context) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final username = context.read<AuthBloc>().state.profile?.username;
      final normalized = username?.trim();
      final text = normalized == null || normalized.isEmpty
          ? context.l10n.friendsContactsInviteTextWithoutUsername
          : context.l10n.friendsContactsInviteText(normalized);
      await context.read<IContactsRepository>().shareInvitation(text);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsActionFailed,
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
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

class _InviteFriendsCard extends StatelessWidget {
  const _InviteFriendsCard({
    required this.title,
    required this.buttonLabel,
    required this.onTap,
  });

  final String title;
  final String buttonLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final lightColor = colorScheme.onSurface;
    return SizedBox(
      height: 168,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: (context.textTheme.titleLarge ?? const TextStyle())
                          .copyWith(
                            color: lightColor.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    GlassTextButton(
                      label: buttonLabel,
                      onTap: onTap,
                      backgroundColor: lightColor,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SvgPicture.asset(
                'assets/logo/mood_heart_24dp_.svg',
                width: 112,
                height: 112,
                colorFilter: ColorFilter.mode(lightColor, BlendMode.srcIn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
