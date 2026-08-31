import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/bloc/bloc.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/view/profile_gallery_page.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/ui/widgets/glass_button.dart';
import 'package:yap_chat/utils/utils.dart';

@RoutePage()
class ViewedProfilePage extends StatelessWidget {
  const ViewedProfilePage({super.key, required this.userId, this.originChatId});

  final String userId;
  final String? originChatId;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (context) => ViewedProfileCubit(
          userId: userId,
          profileRepository: context.read<IProfileRepository>(),
          friendsRepository: context.read<IFriendsRepository>(),
          chatsRepository: context.read<IChatsRepository>(),
          locationRepository: context.read<ILocationRepository>(),
        )..load(),
      ),
      BlocProvider(
        create: (context) => LocationVisibilityCubit(
          repository: context.read<ISettingsRepository>(),
        )..load(),
      ),
    ],
    child: _ViewedProfileView(originChatId: originChatId),
  );
}

class _ViewedProfileView extends StatelessWidget {
  const _ViewedProfileView({this.originChatId});

  final String? originChatId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ViewedProfileCubit, ViewedProfileState>(
          listenWhen: (previous, current) =>
              previous.actionError != current.actionError &&
              current.actionError != null,
          listener: (context, state) {
            showAppSnackBar(
              context,
              message: context.l10n.friendsActionFailed,
              type: SnackBarType.error,
            );
            context.read<ViewedProfileCubit>().clearActionError();
          },
        ),
        BlocListener<LocationVisibilityCubit, LocationVisibilityState>(
          listenWhen: (previous, current) =>
              previous.feedbackId != current.feedbackId &&
              current.feedback != null,
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
        ),
      ],
      child: BlocBuilder<ViewedProfileCubit, ViewedProfileState>(
        builder: (context, state) {
          final viewedProfile = state.viewedProfile;
          if (viewedProfile == null) {
            return Scaffold(
              backgroundColor: context.scaffoldBackgroundColor,
              body: Stack(
                children: [
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 16,
                    left: MediaQuery.paddingOf(context).left + 16,
                    child: GlassButton(
                      icon: Icons.arrow_back_rounded,
                      size: 50,
                      iconSize: 28,
                      borderRadius: 20,
                      onPressed: () => context.router.maybePop(),
                    ),
                  ),
                  Center(
                    child: state.status == ViewedProfileStatus.failure
                        ? Text(
                            context.l10n.viewedProfileLoadFailed,
                            style: TextStyle(
                              color: context.colorScheme.onSurface,
                            ),
                          )
                        : CircularProgressIndicator(
                            color: context.colorScheme.primary,
                          ),
                  ),
                ],
              ),
            );
          }
          return BlocListener<PresenceCubit, PresenceState>(
            listenWhen: (previous, current) =>
                previous.isOnline(viewedProfile.profile.id) &&
                !current.isOnline(viewedProfile.profile.id),
            listener: (context, _) =>
                context.read<ViewedProfileCubit>().markOfflineNow(),
            child: _ProfileScaffold(
              viewedProfile: viewedProfile,
              state: state,
              originChatId: originChatId,
            ),
          );
        },
      ),
    );
  }
}

class _ProfileScaffold extends StatelessWidget {
  const _ProfileScaffold({
    required this.viewedProfile,
    required this.state,
    this.originChatId,
  });

  final ViewedProfile viewedProfile;
  final ViewedProfileState state;
  final String? originChatId;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = mediaQuery.orientation == Orientation.landscape;
          final glowHeight = constraints.maxHeight * .45;
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: glowHeight,
                child: ProfileAmbientGlow(height: glowHeight),
              ),
              Positioned.fill(
                child: _ProfileContent(
                  viewedProfile: viewedProfile,
                  state: state,
                  topPadding: mediaQuery.padding.top + (isLandscape ? 88 : 98),
                  onPhotoTap: (index) =>
                      _openGallery(context, viewedProfile.profile, index),
                  onChat: () => _openChat(context),
                  onLocation: !viewedProfile.isFriend || state.location == null
                      ? null
                      : () => _openLocation(context, state.location!),
                  onFriends: () => _openFriends(context),
                ),
              ),
              Positioned(
                top: mediaQuery.padding.top + 16,
                left: mediaQuery.padding.left + 16,
                right: mediaQuery.padding.right + 16,
                child: Row(
                  children: [
                    GlassButton(
                      icon: Icons.arrow_back_rounded,
                      size: 50,
                      iconSize: 28,
                      borderRadius: 20,
                      onPressed: () => context.router.maybePop(),
                    ),
                    const Spacer(),
                    if (viewedProfile.isFriend) ...[
                      BlocBuilder<
                        LocationVisibilityCubit,
                        LocationVisibilityState
                      >(
                        builder: (context, visibilityState) {
                          final globalVisible =
                              visibilityState.settings?.sharePreciseLocation ??
                              false;
                          final isExcluded = visibilityState.excludedFriendIds
                              .contains(viewedProfile.profile.id);
                          final visible = globalVisible && !isExcluded;
                          return GlassButton(
                            icon: visible
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            size: 50,
                            iconSize: 28,
                            borderRadius: 20,
                            onPressed:
                                visibilityState.isSaving || !globalVisible
                                ? null
                                : () => context
                                      .read<LocationVisibilityCubit>()
                                      .setFriendExcluded(
                                        viewedProfile.profile.id,
                                        excluded: visible,
                                      ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                    ],
                    GlassButton(
                      icon: Icons.settings_rounded,
                      size: 50,
                      iconSize: 29,
                      borderRadius: 20,
                      onPressed: () => _showActions(context),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openChat(BuildContext context) async {
    final chat = await context.read<ViewedProfileCubit>().prepareChat();
    if (!context.mounted) return;
    if (originChatId != null &&
        (chat.id == originChatId || chat.peerId == viewedProfile.profile.id)) {
      await context.router.maybePop();
      return;
    }
    await context.read<ChatNavigationCoordinator>().open(chat);
  }

  Future<void> _openFriends(BuildContext context) async {
    await context.router.push(
      UserFriendsRoute(
        userId: viewedProfile.profile.id,
        userName: viewedProfile.profile.displayName,
      ),
    );
  }

  Future<void> _showActions(BuildContext pageContext) async {
    final cubit = pageContext.read<ViewedProfileCubit>();
    await showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: pageContext.scaffoldBackgroundColor,
      barrierColor: pageContext.colorScheme.primary.withValues(alpha: .22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      showDragHandle: true,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(size.width, 720),
            maxHeight: size.height * .72,
          ),
          child: SingleChildScrollView(
            child: BlocProvider.value(
              value: cubit,
              child: BlocBuilder<ViewedProfileCubit, ViewedProfileState>(
                builder: (_, currentState) {
                  final currentProfile =
                      currentState.viewedProfile ?? viewedProfile;
                  return _ProfileActionsSheet(
                    viewedProfile: currentProfile,
                    chatIsMuted: currentState.chat?.isMuted ?? false,
                    canMute: currentProfile.isFriend,
                    onMute: () async {
                      Navigator.of(sheetContext).pop();
                      await cubit.toggleMute();
                    },
                    onRemove: currentProfile.isFriend
                        ? () async {
                            final confirmed = await showConfirmationDialog(
                              pageContext,
                              title: pageContext
                                  .l10n
                                  .viewedProfileRemoveFriendTitle,
                              content: pageContext.l10n
                                  .viewedProfileRemoveFriendContent(
                                    currentProfile.profile.displayName,
                                  ),
                              confirmLabel:
                                  pageContext.l10n.viewedProfileRemoveFriend,
                            );
                            if (confirmed != true || !pageContext.mounted) {
                              return;
                            }
                            Navigator.of(sheetContext).pop();
                            await cubit.removeFriend();
                          }
                        : null,
                    onStub: (message) {
                      Navigator.of(sheetContext).pop();
                      showAppSnackBar(pageContext, message: message);
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.viewedProfile,
    required this.state,
    required this.topPadding,
    required this.onPhotoTap,
    required this.onChat,
    required this.onFriends,
    this.onLocation,
  });

  final ViewedProfile viewedProfile;
  final ViewedProfileState state;
  final double topPadding;
  final ValueChanged<int> onPhotoTap;
  final VoidCallback onChat;
  final VoidCallback onFriends;
  final VoidCallback? onLocation;

  @override
  Widget build(BuildContext context) {
    final profile = viewedProfile.profile;
    final isOnline = context.select<PresenceCubit, bool>(
      (cubit) => cubit.state.isOnline(profile.id),
    );
    final status = isOnline
        ? context.l10n.chatOnlineStatus
        : viewedProfile.showsLastSeen && viewedProfile.lastSeenAt != null
        ? TimeFormatter.formatLastSeen(context, viewedProfile.lastSeenAt!)
        : context.l10n.chatOfflineStatus;
    final joinedAt = profile.createdAt ?? DateTime.now();
    final days = math.max(
      1,
      DateTime.now().difference(joinedAt.toLocal()).inDays + 1,
    );
    final age = _age(profile.birthDate);
    return CustomScrollView(
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  children: [
                    _ProfilePhotoCard(
                      profile: profile,
                      onTap: () => onPhotoTap(0),
                    ),
                    const SizedBox(height: 4),
                    AnimatedStatusSwitcher(
                      child: Text(
                        status,
                        key: ValueKey(status),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: profile.displayName,
                            style: TextStyle(
                              color: context.colorScheme.onSurface,
                              fontSize: 32,
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w600,
                              height: 1,
                              letterSpacing: 1,
                            ),
                          ),
                          if (age != null)
                            TextSpan(
                              text: '  $age',
                              style: TextStyle(
                                color: context.colorScheme.onSurface,
                                fontSize: 24,
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w400,
                                height: .67,
                                letterSpacing: .5,
                              ),
                            ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (profile.bio.trim().isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        profile.bio.trim(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colorScheme.onSurface,
                          fontSize: 18,
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w400,
                          height: 1,
                          letterSpacing: .5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _ProfileActions(
                      viewedProfile: viewedProfile,
                      state: state,
                      onChat: onChat,
                      onLocation: onLocation,
                    ),
                    const SizedBox(height: 24),
                    _ProfileStats(
                      viewedProfile: viewedProfile,
                      onFriends: onFriends,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.orientationOf(context) == Orientation.landscape
                  ? 56
                  : 32,
              16,
              // Unlike ProfilePage, this route is not covered by MainPage's
              // floating bottom navigation. Reserve only its visual inset.
              MediaQuery.paddingOf(context).bottom + 28,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ProfileDaysLabel(days: days),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfilePhotoCard extends StatelessWidget {
  const _ProfilePhotoCard({required this.profile, required this.onTap});

  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = profile.primaryPhoto;
    return SizedBox(
      width: 270,
      height: 204,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox.square(
                dimension: 176,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (primary == null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: ColoredBox(
                          color: context.colorScheme.primary,
                          child: Icon(
                            Icons.person_rounded,
                            size: 96,
                            color: context.colorScheme.onSurface,
                          ),
                        ),
                      )
                    else
                      ProfilePhotoHero(
                        photo: primary,
                        borderRadius: 32,
                        cacheWidth: 352,
                      ),
                    Material(
                      color: context.colorScheme.surface.withValues(alpha: 0),
                      child: InkWell(
                        onTap: primary == null ? null : onTap,
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: GestureDetector(
                onTap: () => _copyUsername(context, profile.username),
                onLongPress: () => _copyUsername(context, profile.username),
                child: Transform.rotate(
                  angle: -.09,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 32,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 5,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: Text(
                            '@${profile.username}',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: context.colorScheme.onPrimary,
                              fontSize: 24,
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w500,
                              height: 1,
                              letterSpacing: .50,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.viewedProfile,
    required this.state,
    required this.onChat,
    this.onLocation,
  });

  final ViewedProfile viewedProfile;
  final ViewedProfileState state;
  final VoidCallback onChat;
  final VoidCallback? onLocation;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ViewedProfileCubit>();
    final location = _distanceLabel(context, state.distance);
    final locationAge = viewedProfile.isFriend
        ? _locationAge(context, state.location?.updatedAt)
        : null;
    final buttons = <Widget>[
      _ActionButton(icon: Icons.chat_bubble_rounded, label: '', onTap: onChat),
      if (viewedProfile.relationship == ProfileRelationship.none)
        _ActionButton(
          icon: Icons.person_add_alt_1_rounded,
          label: context.l10n.viewedProfileAddFriend,
          onTap: state.isActionPending ? null : cubit.sendRequest,
          wide: true,
        ),
      if (viewedProfile.relationship == ProfileRelationship.outgoing)
        _ActionButton(
          icon: Icons.schedule_rounded,
          label: context.l10n.viewedProfileRequestSent,
          onTap: state.isActionPending ? null : () => _cancelRequest(context),
          wide: true,
          transparent: true,
        ),
      if (viewedProfile.relationship == ProfileRelationship.incoming) ...[
        _IncomingRequestActions(
          isPending: state.isActionPending,
          onAccept: () => cubit.respondToRequest(accept: true),
          onDecline: () => cubit.respondToRequest(accept: false),
        ),
      ],
      _LocationAction(distance: location, age: locationAge, onTap: onLocation),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final button in buttons)
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 70,
                maxWidth: constraints.maxWidth < 390
                    ? constraints.maxWidth
                    : 190,
              ),
              child: button,
            ),
        ],
      ),
    );
  }

  Future<void> _cancelRequest(BuildContext context) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: context.l10n.viewedProfileCancelRequestTitle,
      content: context.l10n.viewedProfileCancelRequestContent,
      confirmLabel: context.l10n.friendsCancelRequest,
    );
    if (confirmed == true && context.mounted) {
      await context.read<ViewedProfileCubit>().cancelRequest();
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.wide = false,
    this.transparent = false,
    this.minWidth = 68,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool wide;
  final bool transparent;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final foreground = transparent
        ? context.colorScheme.onSurface.withValues(alpha: .70)
        : context.colorScheme.onPrimary;
    return Material(
      color: transparent
          ? context.colorScheme.onSurface.withValues(alpha: .20)
          : context.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: wide ? 138 : minWidth,
            minHeight: 46,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: foreground),
                if (label.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            style: TextStyle(
                              color: foreground.withValues(alpha: .68),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingRequestActions extends StatelessWidget {
  const _IncomingRequestActions({
    required this.isPending,
    required this.onAccept,
    required this.onDecline,
  });

  final bool isPending;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 138,
    child: Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.check_rounded,
            label: '',
            minWidth: 0,
            onTap: isPending ? null : onAccept,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.close_rounded,
            label: '',
            minWidth: 0,
            transparent: true,
            onTap: isPending ? null : onDecline,
          ),
        ),
      ],
    ),
  );
}

class _LocationAction extends StatelessWidget {
  const _LocationAction({
    required this.distance,
    required this.age,
    required this.onTap,
  });

  final String distance;
  final String? age;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _ActionButton(icon: Icons.near_me_rounded, label: distance, onTap: onTap),
      if (age != null) ...[
        const SizedBox(height: 5),
        Text(
          age!,
          style: TextStyle(
            color: context.colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ],
  );
}

class _ProfileStats extends StatelessWidget {
  const _ProfileStats({required this.viewedProfile, required this.onFriends});

  final ViewedProfile viewedProfile;
  final VoidCallback onFriends;

  @override
  Widget build(BuildContext context) {
    final hasNoFriends = viewedProfile.friendCount == 0;
    final onlyFriendIsViewer =
        viewedProfile.isFriend && viewedProfile.friendCount == 1;
    final canOpenFriends = !hasNoFriends && !onlyFriendIsViewer;
    final friendsLabel = hasNoFriends
        ? context.l10n.viewedProfileNoFriends
        : onlyFriendIsViewer
        ? context.l10n.viewedProfileFriendIsYou
        : context.l10n.friendsCount(viewedProfile.friendCount);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: InkWell(
            onTap: canOpenFriends ? onFriends : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: viewedProfile.friendsPreview.isEmpty
                        ? 0
                        : 32 + (viewedProfile.friendsPreview.length - 1) * 20,
                    height: 32,
                    child: Stack(
                      children: [
                        for (
                          var index = 0;
                          index < viewedProfile.friendsPreview.length;
                          index++
                        )
                          Positioned(
                            left: index * 20,
                            child: _MiniFriendAvatar(
                              friend: viewedProfile.friendsPreview[index],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (viewedProfile.friendsPreview.isNotEmpty)
                    const SizedBox(width: 8),
                  Text(
                    friendsLabel,
                    style: TextStyle(
                      color: context.colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Icon(
          Icons.visibility_outlined,
          size: 20,
          color: context.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Text(
          '${viewedProfile.viewCount}',
          style: TextStyle(
            color: context.colorScheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MiniFriendAvatar extends StatelessWidget {
  const _MiniFriendAvatar({required this.friend});

  final ViewedProfileFriend friend;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: context.scaffoldBackgroundColor, width: 2),
      borderRadius: BorderRadius.circular(9),
    ),
    child: UserAvatar(
      avatarUrl: friend.avatarUrl,
      avatarLoader: () => context
          .read<IProfileRepository>()
          .resolveViewedProfileFriendAvatar(friend),
      avatarRevision: friend.avatarStoragePath ?? friend.avatarUrl,
      size: 30,
      borderRadius: 7,
    ),
  );
}

class _ProfileActionsSheet extends StatelessWidget {
  const _ProfileActionsSheet({
    required this.viewedProfile,
    required this.chatIsMuted,
    required this.canMute,
    required this.onMute,
    required this.onStub,
    this.onRemove,
  });

  final ViewedProfile viewedProfile;
  final bool chatIsMuted;
  final bool canMute;
  final VoidCallback onMute;
  final ValueChanged<String> onStub;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final itemStyle = TextStyle(
      color: context.colorScheme.onSurface,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: .5,
    );
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          MediaQuery.paddingOf(context).bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (viewedProfile.isFriend)
              ListTile(
                enabled: canMute,
                leading: Icon(
                  chatIsMuted
                      ? Icons.notifications_rounded
                      : Icons.notifications_off_rounded,
                ),
                title: Text(
                  chatIsMuted
                      ? context.l10n.viewedProfileUnmute.toLowerCase()
                      : context.l10n.viewedProfileMute.toLowerCase(),
                  style: itemStyle,
                ),
                onTap: onMute,
              ),
            if (onRemove != null)
              ListTile(
                leading: const Icon(Icons.person_remove_rounded),
                title: Text(
                  context.l10n.viewedProfileRemoveFriend.toLowerCase(),
                  style: itemStyle,
                ),
                onTap: onRemove,
              ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: Text(
                context.l10n.viewedProfileBlock.toLowerCase(),
                style: itemStyle,
              ),
              onTap: () => onStub(context.l10n.viewedProfileStub),
            ),
            ListTile(
              leading: const Icon(Icons.flag_rounded),
              title: Text(
                context.l10n.viewedProfileReport.toLowerCase(),
                style: itemStyle,
              ),
              onTap: () => onStub(context.l10n.viewedProfileStub),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openGallery(
  BuildContext context,
  UserProfile profile,
  int index,
) async {
  final photos = profile.effectivePhotos;
  if (photos.isEmpty) return;
  final provider = profilePhotoImageProvider(photos[index], cacheWidth: 352);
  final aspectRatio = provider == null
      ? null
      : await resolveImageAspectRatio(context, provider);
  if (!context.mounted) return;
  final ratios = List<double?>.filled(photos.length, null);
  ratios[index] = aspectRatio;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => ProfileGalleryPage(
        photos: photos,
        initialIndex: index,
        initialThumbnailCacheWidth: 352,
        displayName: profile.displayName,
        imageAspectRatios: ratios,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

Future<void> _openLocation(
  BuildContext context,
  FriendLocation location,
) async {
  final uri = Uri.parse(
    'geo:${location.latitude},${location.longitude}?q=${location.latitude},${location.longitude}',
  );
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.locationOpenError,
        type: SnackBarType.error,
      );
    }
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.locationOpenError,
        type: SnackBarType.error,
      );
    }
  }
}

String _distanceLabel(BuildContext context, UserDistance? distance) {
  if (distance == null) return '???';
  return distance.unit == DistanceUnit.meters
      ? context.l10n.viewedProfileDistanceMeters(distance.value)
      : context.l10n.viewedProfileDistanceKilometers(distance.value);
}

String? _locationAge(BuildContext context, DateTime? updatedAt) {
  if (updatedAt == null) return null;
  return TimeFormatter.formatLocationAge(context, updatedAt);
}

Future<void> _copyUsername(BuildContext context, String username) async {
  await Clipboard.setData(ClipboardData(text: '@$username'));
  await HapticFeedback.mediumImpact();
  if (context.mounted) {
    showAppSnackBar(context, message: context.l10n.viewedProfileUsernameCopied);
  }
}

int? _age(DateTime? birthDate) {
  if (birthDate == null) return null;
  final now = DateTime.now();
  return now.year -
      birthDate.year -
      ((now.month < birthDate.month ||
              (now.month == birthDate.month && now.day < birthDate.day))
          ? 1
          : 0);
}
