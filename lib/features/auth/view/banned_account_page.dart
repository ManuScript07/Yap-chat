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
  Timer? _deletionDeadlineTimer;
  bool _deletionDeadlineReached = false;

  @override
  void initState() {
    super.initState();
    // The cubit starts this load at app startup. Calling ensureContent here is
    // harmless when it is already in progress and covers a direct route to
    // this page before public content has reached the widget tree.
    unawaited(context.read<AppPublicContentCubit>().ensureContent());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _watchDeletionDeadline(
        context.read<AuthBloc>().state.deletionScheduledFor,
      );
    });
  }

  @override
  void dispose() {
    _deletionDeadlineTimer?.cancel();
    super.dispose();
  }

  void _watchDeletionDeadline(DateTime? scheduledFor) {
    _deletionDeadlineTimer?.cancel();
    final now = DateTime.now().toUtc();
    final deadlineReached =
        scheduledFor != null && !scheduledFor.toUtc().isAfter(now);
    if (_deletionDeadlineReached != deadlineReached) {
      setState(() => _deletionDeadlineReached = deadlineReached);
    }
    if (scheduledFor == null || deadlineReached) return;
    _deletionDeadlineTimer = Timer(scheduledFor.toUtc().difference(now), () {
      if (mounted) setState(() => _deletionDeadlineReached = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDeletionPending = context.select(
      (AuthBloc bloc) => bloc.state.status == AuthStatus.deletionPending,
    );
    final isDeletionExpired =
        context.select((AuthBloc bloc) => bloc.state.isDeletionExpired) ||
        _deletionDeadlineReached;
    final isSubmitting = context.select(
      (AuthBloc bloc) => bloc.state.isSubmitting,
    );
    final failure = context.select((AuthBloc bloc) => bloc.state.failure);
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
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.deletionScheduledFor != current.deletionScheduledFor,
      listener: (_, state) =>
          _watchDeletionDeadline(state.deletionScheduledFor),
      child: Scaffold(
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
                            isDeletionPending
                                ? isDeletionExpired
                                      ? context.l10n.accountDeletionExpiredTitle
                                      : context.l10n.accountDeletionPendingTitle
                                : context.l10n.authBannedTitle,
                            textAlign: TextAlign.center,
                            style: context.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isDeletionPending
                                ? isDeletionExpired
                                      ? context
                                            .l10n
                                            .accountDeletionExpiredDescription
                                      : context
                                            .l10n
                                            .accountDeletionPendingDescription
                                : context.l10n.authBannedDescription,
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
                                      color:
                                          context.colorScheme.onSurfaceVariant,
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
                                              color: context
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.copy_rounded,
                                      size: 18,
                                      color:
                                          context.colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          if (isDeletionPending && !isDeletionExpired) ...[
                            FilledButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () => context.read<AuthBloc>().add(
                                      const AuthAccountRestoreRequested(),
                                    ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(context.l10n.accountDeletionRestore),
                            ),
                            if (failure == AuthFailure.accountRestore) ...[
                              const SizedBox(height: 12),
                              Text(
                                context.l10n.accountDeletionRestoreFailed,
                                textAlign: TextAlign.center,
                                style: context.textTheme.bodyMedium?.copyWith(
                                  color: context.colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                          ],
                          OutlinedButton(
                            onPressed: isSubmitting
                                ? null
                                : () => context.read<AuthBloc>().add(
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
      ),
    );
  }
}
