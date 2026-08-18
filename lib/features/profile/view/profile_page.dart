import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.select<AuthBloc, UserProfile?>(
      (bloc) => bloc.state.profile,
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.navProfile)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  UserAvatar(
                    avatarUrl: profile?.avatarUrl,
                    avatarImage: profile?.avatarBytes == null
                        ? null
                        : MemoryImage(profile!.avatarBytes!),
                    size: 96,
                    borderRadius: 28,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    profile?.displayName ?? '',
                    style: context.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '@${profile?.username ?? ''}',
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: () => context.read<AuthBloc>().add(
                      const AuthSignOutRequested(),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(context.l10n.authSignOut),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
