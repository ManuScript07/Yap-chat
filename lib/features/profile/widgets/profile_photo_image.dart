import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

class ProfilePhotoHero extends StatelessWidget {
  const ProfilePhotoHero({
    super.key,
    required this.photo,
    required this.borderRadius,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.revealOnLoad = true,
  });

  final ProfilePhoto photo;
  final double borderRadius;
  final BoxFit fit;
  final int? cacheWidth;
  final bool revealOnLoad;

  @override
  Widget build(BuildContext context) {
    final image = ProfilePhotoImage(
      photo: photo,
      fit: fit,
      cacheWidth: cacheWidth,
      revealOnLoad: revealOnLoad,
    );
    return Hero(
      tag: profilePhotoHeroTag(photo),
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: buildProfilePhotoHeroFlight,
      child: borderRadius == 0
          ? image
          : ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: image,
            ),
    );
  }
}

/// Both endpoints use this builder: Flutter gives the destination Hero's
/// builder priority, which must not change the flight's corner semantics.
Widget buildProfilePhotoHeroFlight(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final fromChild = (fromContext.widget as Hero).child;
  final toChild = (toContext.widget as Hero).child;
  final fromRadius = _heroBorderRadius(fromChild);
  final toRadius = _heroBorderRadius(toChild);
  final fromBadge =
      fromChild is UserAvatar &&
      fromChild.showOnlineBadge &&
      fromChild.isOnline;
  final toBadge =
      toChild is UserAvatar && toChild.showOnlineBadge && toChild.isOnline;
  final badgeAvatar = fromBadge
      ? fromChild
      : toBadge
      ? toChild
      : null;
  final flightChild = fromChild is UserAvatar
      ? _buildFlightChild(fromChild)
      : _buildFlightChild(toChild, flightPhoto: _flightPhoto(fromChild));
  return AnimatedBuilder(
    animation: animation,
    child: flightChild,
    builder: (_, child) {
      final progress = direction == HeroFlightDirection.push
          ? animation.value
          : 1 - animation.value;
      return Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          ClipRRect(
            key: const ValueKey('profile-photo-flight-clip'),
            borderRadius: BorderRadius.circular(
              fromRadius + (toRadius - fromRadius) * progress,
            ),
            child: child,
          ),
          if (badgeAvatar is UserAvatar)
            _HeroOnlineBadge(
              referenceSize: badgeAvatar.size,
              opacity:
                  (fromBadge ? 1.0 : 0.0) +
                  ((toBadge ? 1.0 : 0.0) - (fromBadge ? 1.0 : 0.0)) * progress,
            ),
        ],
      );
    },
  );
}

double _heroBorderRadius(Widget child) {
  if (child is UserAvatar) return child.borderRadius;
  if (child is ClipRRect) {
    return child.borderRadius.resolve(TextDirection.ltr).topLeft.x;
  }
  return 0;
}

ProfilePhoto? _flightPhoto(Widget child) {
  if (child is ClipRRect && child.child is ProfilePhotoImage) {
    return (child.child! as ProfilePhotoImage).photo;
  }
  return child is ProfilePhotoImage ? child.photo : null;
}

Widget _buildFlightChild(Widget child, {ProfilePhoto? flightPhoto}) {
  if (child is UserAvatar) {
    return FittedBox(
      fit: BoxFit.fill,
      child: UserAvatar(
        // A shuttle only reuses the row's warmed cache/provider. In particular,
        // opening a profile before its row finishes loading must not start a
        // second resolver or bypass preferAvatarLoader with a network fallback.
        avatarUrl: child.preferAvatarLoader ? null : child.avatarUrl,
        avatarImage: child.avatarImage,
        preferAvatarLoader: child.preferAvatarLoader,
        avatarRevision: child.avatarRevision ?? child.avatarUrl,
        initialAvatarPath: child.initialAvatarPath,
        size: child.size,
        // The outer flight clip is the only owner of animated corners.
        borderRadius: 0,
      ),
    );
  }
  if (child is ClipRRect && child.child is ProfilePhotoImage) {
    final image = child.child as ProfilePhotoImage;
    return ProfilePhotoImage(
      photo: flightPhoto ?? image.photo,
      fit: image.fit,
      placeholderIconSize: image.placeholderIconSize,
      cacheWidth: image.cacheWidth,
      revealOnLoad: false,
    );
  }
  if (child is ProfilePhotoImage) {
    return ProfilePhotoImage(
      photo: flightPhoto ?? child.photo,
      fit: child.fit,
      placeholderIconSize: child.placeholderIconSize,
      cacheWidth: child.cacheWidth,
      revealOnLoad: false,
    );
  }
  return child;
}

String profilePhotoHeroTag(ProfilePhoto photo) =>
    'profile-photo-${photo.identity}';

class ProfilePhotoImage extends StatefulWidget {
  const ProfilePhotoImage({
    super.key,
    required this.photo,
    this.fit = BoxFit.cover,
    this.placeholderIconSize = 64,
    this.cacheWidth,
    this.revealOnLoad = true,
  });

  final ProfilePhoto photo;
  final BoxFit fit;
  final double placeholderIconSize;
  final int? cacheWidth;
  final bool revealOnLoad;

  @override
  State<ProfilePhotoImage> createState() => _ProfilePhotoImageState();
}

class _ProfilePhotoImageState extends State<ProfilePhotoImage> {
  late ProfilePhoto _displayedPhoto = widget.photo;

  @override
  void didUpdateWidget(covariant ProfilePhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isNewPhoto = oldWidget.photo.identity != widget.photo.identity;
    final hasNewCachedBytes =
        oldWidget.photo.bytes == null && widget.photo.bytes != null;
    if (isNewPhoto || hasNewCachedBytes) {
      _displayedPhoto = widget.photo;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(_, _, _) => _placeholder(context);
    final provider = profilePhotoImageProvider(
      _displayedPhoto,
      cacheWidth: widget.cacheWidth,
    );
    return provider == null
        ? _placeholder(context)
        : Image(
            image: provider,
            fit: widget.fit,
            gaplessPlayback: true,
            frameBuilder: widget.revealOnLoad ? _revealImageFrame : null,
            errorBuilder: errorBuilder,
          );
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: context.colorScheme.primary,
    child: Center(
      child: Icon(
        Icons.person_rounded,
        size: widget.placeholderIconSize,
        color: context.colorScheme.onPrimary,
      ),
    ),
  );
}

Widget _revealImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  final isReady = wasSynchronouslyLoaded || frame != null;
  return AnimatedOpacity(
    opacity: isReady ? 1 : 0,
    duration: wasSynchronouslyLoaded
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    child: child,
  );
}

ImageProvider<Object>? profilePhotoImageProvider(
  ProfilePhoto photo, {
  int? cacheWidth,
}) {
  final bytes = photo.bytes;
  if (bytes != null) {
    return ResizeImage.resizeIfNeeded(cacheWidth, null, MemoryImage(bytes));
  }
  final url = photo.avatarUrl;
  return url == null || url.isEmpty
      ? null
      : ResizeImage.resizeIfNeeded(cacheWidth, null, NetworkImage(url));
}

class _HeroOnlineBadge extends StatelessWidget {
  const _HeroOnlineBadge({required this.opacity, required this.referenceSize});

  final double opacity;
  final double referenceSize;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final avatarSize = constraints.biggest.shortestSide;
        final scale = avatarSize / referenceSize;
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
