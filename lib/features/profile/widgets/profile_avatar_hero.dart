import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/widgets/profile_photo_image.dart';
import 'package:yap_chat/ui/widgets/user_avatar.dart';

class ProfileAvatarHero extends StatelessWidget {
  const ProfileAvatarHero({
    super.key,
    required this.child,
    this.avatarUrl,
    this.avatarStoragePath,
  });

  final Widget child;
  final String? avatarUrl;
  final String? avatarStoragePath;

  @override
  Widget build(BuildContext context) {
    if (!Visibility.of(context)) return child;
    if ((avatarUrl == null || avatarUrl!.isEmpty) &&
        (avatarStoragePath == null || avatarStoragePath!.isEmpty)) {
      return child;
    }
    final photo = ProfilePhoto(
      position: 0,
      avatarUrl: avatarStoragePath == null ? avatarUrl : null,
      storagePath: avatarStoragePath,
    );
    return Hero(
      tag: profilePhotoHeroTag(photo),
      transitionOnUserGestures: true,
      flightShuttleBuilder:
          (_, animation, flightDirection, fromHeroContext, toHeroContext) {
            final fromChild = (fromHeroContext.widget as Hero).child;
            final toChild = (toHeroContext.widget as Hero).child;
            final radius = Tween<double>(
              begin: flightDirection == HeroFlightDirection.push
                  ? _avatarBorderRadius(fromChild)
                  : _avatarBorderRadius(toChild),
              end: flightDirection == HeroFlightDirection.push
                  ? _avatarBorderRadius(toChild)
                  : _avatarBorderRadius(fromChild),
            ).animate(animation);
            final fromHasOnlineBadge = _hasOnlineBadge(fromChild);
            final toHasOnlineBadge = _hasOnlineBadge(toChild);
            final flightChild =
                flightDirection == HeroFlightDirection.pop &&
                    toChild is UserAvatar
                ? toChild
                : fromChild;
            return AnimatedBuilder(
              animation: radius,
              child: _avatarFlightChild(flightChild),
              builder: (context, child) {
                final progress = flightDirection == HeroFlightDirection.push
                    ? animation.value
                    : 1 - animation.value;
                final onlineBadgeOpacity =
                    (fromHasOnlineBadge ? 1.0 : 0.0) +
                    ((toHasOnlineBadge ? 1.0 : 0.0) -
                            (fromHasOnlineBadge ? 1.0 : 0.0)) *
                        progress;
                return Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(radius.value),
                      child: child,
                    ),
                    if (fromHasOnlineBadge || toHasOnlineBadge)
                      _HeroOnlineBadge(opacity: onlineBadgeOpacity),
                  ],
                );
              },
            );
          },
      child: child,
    );
  }
}

class _HeroOnlineBadge extends StatelessWidget {
  const _HeroOnlineBadge({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final avatarSize = constraints.biggest.shortestSide;
        final scale = avatarSize / 56;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -2 * scale,
              bottom: -2 * scale,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: avatarSize * 0.32,
                  height: avatarSize * 0.32,
                  decoration: BoxDecoration(
                    color: context.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.scaffoldBackgroundColor,
                      width: 2 * scale,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

double _avatarBorderRadius(Widget child) {
  if (child is UserAvatar) return child.borderRadius;
  if (child is ClipRRect) {
    return child.borderRadius.resolve(TextDirection.ltr).topLeft.x;
  }
  return 0;
}

bool _hasOnlineBadge(Widget child) =>
    child is UserAvatar && child.showOnlineBadge && child.isOnline;

Widget _avatarFlightChild(Widget child) {
  if (child is UserAvatar) {
    return FittedBox(
      fit: BoxFit.fill,
      child: UserAvatar(
        avatarUrl: child.avatarUrl,
        avatarImage: child.avatarImage,
        avatarLoader: child.avatarLoader,
        avatarRevision: child.avatarRevision,
        size: child.size,
        borderRadius: child.borderRadius,
      ),
    );
  }
  // The outer clip owns the animated corner radius. Keeping this inner clip
  // would preserve the profile radius until the final frame of a pop.
  if (child is ClipRRect && child.child is ProfilePhotoImage) {
    return _profilePhotoFlightImage(child.child! as ProfilePhotoImage);
  }
  if (child is ProfilePhotoImage) {
    return _profilePhotoFlightImage(child);
  }
  return child;
}

Widget _profilePhotoFlightImage(ProfilePhotoImage image) => ProfilePhotoImage(
  photo: image.photo,
  fit: image.fit,
  placeholderIconSize: image.placeholderIconSize,
  cacheWidth: image.cacheWidth,
  // The source photo has already been displayed. Replaying its normal fade
  // while it is being moved by Hero can expose a translucent first frame.
  revealOnLoad: false,
);
