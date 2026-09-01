import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';

/// Deliberately neutral access-restriction page. No moderation reason, report
/// information, or expiry date is exposed to the restricted account.
@RoutePage()
class BannedAccountPage extends StatelessWidget {
  const BannedAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final username = context.select(
      (AuthBloc bloc) => bloc.state.bannedUsername,
    );
    final supportEmail = context.select(
      (AppPublicContentCubit cubit) => cubit.state.content?.supportEmail,
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.block_rounded,
                    size: 64,
                    color: context.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.l10n.authBannedTitle,
                    textAlign: TextAlign.center,
                    style: context.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.authBannedDescription,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (username != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      '@$username',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (supportEmail != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.authBannedSupport(supportEmail),
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.read<AuthBloc>().add(
                      const AuthSignOutRequested(),
                    ),
                    child: Text(context.l10n.authSignOut),
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
