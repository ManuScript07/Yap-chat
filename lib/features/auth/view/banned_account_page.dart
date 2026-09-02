import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';

/// Deliberately neutral access-restriction page. No moderation reason, report
/// information, or expiry date is exposed to the restricted account.
@RoutePage()
class BannedAccountPage extends StatefulWidget {
  const BannedAccountPage({super.key});

  @override
  State<BannedAccountPage> createState() => _BannedAccountPageState();
}

class _BannedAccountPageState extends State<BannedAccountPage> {
  @override
  void initState() {
    super.initState();
    // The cubit starts this load at app startup. Calling ensureContent here is
    // harmless when it is already in progress and covers a direct route to
    // this page before public content has reached the widget tree.
    unawaited(context.read<AppPublicContentCubit>().ensureContent());
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.select(
      (AuthBloc bloc) => bloc.state.session?.userId,
    );
    final accessSupportEmail = context.select(
      (AuthBloc bloc) => bloc.state.bannedSupportEmail,
    );
    final publicSupportEmail = context.select(
      (AppPublicContentCubit cubit) => cubit.state.content?.supportEmail,
    );
    final supportEmail = accessSupportEmail ?? publicSupportEmail;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                        if (userId != null) ...[
                          const SizedBox(height: 18),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              await Clipboard.setData(
                                ClipboardData(text: userId),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      userId,
                                      textAlign: TextAlign.center,
                                      style: context.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (supportEmail != null) ...[
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Clipboard.setData(
                              ClipboardData(text: supportEmail),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      context.l10n.authBannedSupport(
                                        supportEmail,
                                      ),
                                      textAlign: TextAlign.center,
                                      style: context.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: context.colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
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
          ),
        ),
      ),
    );
  }
}
