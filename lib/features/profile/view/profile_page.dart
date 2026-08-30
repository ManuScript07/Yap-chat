import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/view/profile_gallery_page.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/features/settings/settings.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/ui/widgets/glass_button.dart';

@RoutePage()
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    final profile = context.select<AuthBloc, UserProfile?>(
      (bloc) => bloc.state.profile,
    );
    if (profile == null) {
      return Scaffold(
        backgroundColor: context.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: context.colorScheme.primary),
        ),
      );
    }

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
                child: _ProfileAmbientGlow(height: glowHeight),
              ),
              Positioned.fill(
                child: _ProfileScrollContent(
                  profile: profile,
                  topPadding: mediaQuery.padding.top + (isLandscape ? 88 : 98),
                  onPhotoTap: (index) => _openGallery(profile, index),
                ),
              ),
              Positioned(
                top: mediaQuery.padding.top + 16,
                left: mediaQuery.padding.left + 16,
                right: mediaQuery.padding.right + 16,
                child: Row(
                  children: [
                    GlassButton(
                      icon: Icons.edit_rounded,
                      size: 50,
                      iconSize: 28,
                      borderRadius: 20,
                      onPressed: () =>
                          showProfileEditPage(context, profile: profile),
                    ),
                    const SizedBox(width: 12),
                    GlassButton(
                      icon: Icons.settings_rounded,
                      size: 50,
                      iconSize: 29,
                      borderRadius: 20,
                      onPressed: () => showSettingsPage(context),
                    ),
                    const Spacer(),
                    GlassButton(
                      icon: Icons.share_rounded,
                      size: 50,
                      iconSize: 28,
                      borderRadius: 20,
                      onPressed: _isSharing ? null : () => _share(profile),
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

  Future<void> _openGallery(UserProfile profile, int index) async {
    final photos = profile.effectivePhotos;
    if (photos.isEmpty) return;
    final provider = profilePhotoImageProvider(photos[index], cacheWidth: 352);
    final aspectRatio = provider == null
        ? null
        : await resolveImageAspectRatio(context, provider);
    if (!mounted) return;
    final aspectRatios = List<double?>.filled(photos.length, null);
    aspectRatios[index] = aspectRatio;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => ProfileGalleryPage(
          photos: photos,
          initialIndex: index,
          initialThumbnailCacheWidth: 352,
          displayName: profile.displayName,
          imageAspectRatios: aspectRatios,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _share(UserProfile profile) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      await context.read<IContactsRepository>().shareInvitation(
        context.l10n.friendsContactsInviteText(profile.username),
      );
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
}

class _ProfileAmbientGlow extends StatelessWidget {
  const _ProfileAmbientGlow({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.primary;
    final transparent = color.withValues(alpha: 0);
    return IgnorePointer(
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 42,
                sigmaY: 18,
                tileMode: ui.TileMode.decal,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: .98),
                      color.withValues(alpha: .86),
                      color.withValues(alpha: .52),
                      color.withValues(alpha: .1),
                    ],
                    stops: const [0, .22, .65, 1],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: .34),
                    color.withValues(alpha: .22),
                    transparent,
                  ],
                  stops: const [0, .42, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileScrollContent extends StatelessWidget {
  const _ProfileScrollContent({
    required this.profile,
    required this.topPadding,
    required this.onPhotoTap,
  });

  final UserProfile profile;
  final double topPadding;
  final ValueChanged<int> onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final age = _age(profile.birthDate);
    final textColor = context.colorScheme.onSurface;
    final inactiveColor = context.colorScheme.outline;
    final joinedAt =
        profile.createdAt ?? profile.termsAcceptedAt ?? DateTime.now();
    final days = math.max(
      1,
      DateTime.now().difference(joinedAt.toLocal()).inDays + 1,
    );
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
                    const SizedBox(height: 24),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: profile.displayName,
                            style: TextStyle(
                              color: textColor,
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
                                color: textColor,
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
                          color: textColor,
                          fontSize: 18,
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w400,
                          height: 1,
                          letterSpacing: .5,
                        ),
                      ),
                    ],
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
              MediaQuery.paddingOf(context).bottom + 118,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    color: inactiveColor,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.profileDaysWithUs(days),
                    style: TextStyle(
                      color: inactiveColor,
                      fontSize: 20,
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w500,
                      height: 1.20,
                      letterSpacing: .50,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Icon(
                    Icons.visibility_outlined,
                    color: inactiveColor,
                    size: 24,
                  ),
                  const SizedBox(width: 6),
                  _ProfileViewCount(userId: profile.id),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileViewCount extends StatefulWidget {
  const _ProfileViewCount({required this.userId});

  final String userId;

  @override
  State<_ProfileViewCount> createState() => _ProfileViewCountState();
}

class _ProfileViewCountState extends State<_ProfileViewCount> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = context.read<IProfileRepository>();
    final cached = await repository.getCachedProfileViewCount(widget.userId);
    if (mounted && cached != null) setState(() => _count = cached);
    try {
      final remote = await repository.getProfileViewCount(widget.userId);
      if (mounted) setState(() => _count = remote);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Text(
    '$_count',
    style: TextStyle(
      color: context.colorScheme.outline,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _ProfilePhotoCard extends StatelessWidget {
  const _ProfilePhotoCard({required this.profile, required this.onTap});

  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = context.colorScheme.surface;
    final usernameTextColor = context.colorScheme.onPrimary;
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
                        child: const _ProfilePhotoPlaceholder(),
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
                onLongPress: () => _copyUsername(context, profile.username),
                child: Transform.rotate(
                  angle: -0.09,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 32,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: surfaceColor,
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
                              color: usernameTextColor,
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

class _ProfilePhotoPlaceholder extends StatelessWidget {
  const _ProfilePhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colorScheme.primary,
      child: Icon(
        Icons.person_rounded,
        size: 96,
        color: context.colorScheme.onSurface,
      ),
    );
  }
}

Future<void> _copyUsername(BuildContext context, String username) async {
  await Clipboard.setData(ClipboardData(text: '@$username'));
  await HapticFeedback.mediumImpact();
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
