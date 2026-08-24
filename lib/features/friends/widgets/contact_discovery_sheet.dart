import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/bloc/bloc.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/friends/widgets/contact_discovery_item.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

Future<void> showContactDiscoverySheet(
  BuildContext context, {
  required String? username,
}) {
  final contactsRepository = context.read<IContactsRepository>();
  final friendsRepository = context.read<IFriendsRepository>();
  final screen = MediaQuery.sizeOf(context);
  final parentTheme = Theme.of(context);
  final parentScheme = parentTheme.colorScheme;
  final sheetTheme = parentTheme.copyWith(
    colorScheme: parentScheme.copyWith(
      primary: parentScheme.onPrimary,
      onPrimary: parentScheme.primary,
      onSurface: parentScheme.onPrimary,
      onSurfaceVariant: parentScheme.onPrimary.withValues(alpha: 0.65),
    ),
  );
  final heightFactor = screen.width > screen.height ? 0.96 : 0.9;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: parentScheme.primary,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    constraints: BoxConstraints(
      maxWidth: math.min(screen.width, 720),
      maxHeight: screen.height * heightFactor,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => Theme(
      data: sheetTheme,
      child: BlocProvider(
        create: (_) => ContactDiscoveryCubit(
          contactsRepository: contactsRepository,
          friendsRepository: friendsRepository,
        )..load(),
        child: _ContactDiscoverySheet(username: username),
      ),
    ),
  );
}

class _ContactDiscoverySheet extends StatelessWidget {
  const _ContactDiscoverySheet({required this.username});

  final String? username;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final searchBottom = keyboardInset > 0
        ? keyboardInset + 12
        : mediaQuery.padding.bottom + 12;
    final contentBottomPadding = searchBottom + 62;
    return BlocListener<ContactDiscoveryCubit, ContactDiscoveryState>(
      listenWhen: (previous, current) =>
          previous.actionError != current.actionError &&
          current.actionError != null,
      listener: (context, state) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsActionFailed,
          type: SnackBarType.error,
        );
        context.read<ContactDiscoveryCubit>().clearActionError();
      },
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.friendsContactsTitle,
                        style: AppTextStyles.titleLargeFlex,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 30),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _ContactDiscoveryBody(
                  username: username,
                  bottomPadding: contentBottomPadding,
                ),
              ),
            ],
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutQuad,
            left: 0,
            right: 0,
            bottom: searchBottom,
            child: BlocBuilder<ContactDiscoveryCubit, ContactDiscoveryState>(
              buildWhen: (previous, current) =>
                  previous.status != current.status,
              builder: (context, state) => GlassSearchBar(
                hintText: context.l10n.friendsSearchHint,
                enabled: state.status == ContactDiscoveryStatus.success,
                onChanged: context.read<ContactDiscoveryCubit>().queryChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactDiscoveryBody extends StatelessWidget {
  const _ContactDiscoveryBody({
    required this.username,
    required this.bottomPadding,
  });

  final String? username;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ContactDiscoveryCubit, ContactDiscoveryState>(
      builder: (context, state) {
        final entries = state.visibleEntries;
        return switch (state.status) {
          ContactDiscoveryStatus.initial ||
          ContactDiscoveryStatus.loading => Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: Center(
              child: CircularProgressIndicator(
                color: context.colorScheme.primary,
              ),
            ),
          ),
          ContactDiscoveryStatus.failure => Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
              child: Text(
                context.l10n.friendsContactsLoadFailed,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          ContactDiscoveryStatus.success when state.entries.isEmpty => Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
              child: Text(
                context.l10n.friendsContactsEmpty,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          ContactDiscoveryStatus.success when entries.isEmpty => Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
              child: Text(
                context.l10n.friendsNoSearchResults,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          ContactDiscoveryStatus.success => ListView.builder(
            padding: EdgeInsets.only(bottom: bottomPadding),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final candidate = entry.candidate;
              final cubit = context.read<ContactDiscoveryCubit>();
              return ContactDiscoveryItem(
                key: ValueKey(entry.contact.id),
                entry: entry,
                friendsLabel: context.l10n.friendsCount,
                notRegisteredLabel: context.l10n.friendsContactsNotRegistered,
                hiddenFriendCountLabel:
                    context.l10n.friendsContactsFriendCountHidden,
                inviteLabel: context.l10n.friendsContactsInvite,
                relationshipLabel: (relationship) => switch (relationship) {
                  FriendRelationship.friend => context.l10n.friendsAlreadyAdded,
                  FriendRelationship.outgoing =>
                    context.l10n.friendsRequestSent,
                  FriendRelationship.incoming =>
                    context.l10n.friendsRequestIncoming,
                  FriendRelationship.none => '',
                },
                avatarLoader: candidate == null
                    ? null
                    : () => context
                          .read<IFriendsRepository>()
                          .resolveCandidateAvatar(candidate),
                onAdd: () => cubit.sendRequest(entry),
                onInvite: () => cubit.invite(_invitationText(context)),
                onAccept: () => cubit.respondToIncoming(entry, accept: true),
                onReject: () => cubit.respondToIncoming(entry, accept: false),
              );
            },
          ),
        };
      },
    );
  }

  String _invitationText(BuildContext context) {
    final normalized = username?.trim();
    return normalized == null || normalized.isEmpty
        ? context.l10n.friendsContactsInviteTextWithoutUsername
        : context.l10n.friendsContactsInviteText(normalized);
  }
}
