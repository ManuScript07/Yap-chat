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
      flightShuttleBuilder:
          (_, animation, flightDirection, fromHeroContext, toHeroContext) {
            final fromChild = (fromHeroContext.widget as Hero).child;
            final toChild = (toHeroContext.widget as Hero).child;
            final fromRadius = _heroBorderRadius(
              fromChild,
              fallback: borderRadius,
            );
            final toRadius = _heroBorderRadius(toChild, fallback: borderRadius);
            final radius = Tween<double>(
              begin: flightDirection == HeroFlightDirection.push
                  ? fromRadius
                  : toRadius,
              end: flightDirection == HeroFlightDirection.push
                  ? toRadius
                  : fromRadius,
            ).animate(animation);

            final targetChild = _buildFlightChild(
              toChild,
              flightPhoto: _flightPhoto(fromChild),
            );
            return AnimatedBuilder(
              animation: radius,
              builder: (context, child) => ClipRRect(
                borderRadius: BorderRadius.circular(radius.value),
                child: child,
              ),
              child: targetChild,
            );
          },
      child: borderRadius == 0
          ? image
          : ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: image,
            ),
    );
  }
}

double _heroBorderRadius(Widget child, {required double fallback}) {
  if (child is UserAvatar) return child.borderRadius;
  if (child is ClipRRect) {
    return child.borderRadius.resolve(TextDirection.ltr).topLeft.x;
  }
  if (child is ProfilePhotoImage) return 0;
  return fallback;
}

ProfilePhoto? _flightPhoto(Widget child) {
  if (child is ClipRRect && child.child is ProfilePhotoImage) {
    return (child.child! as ProfilePhotoImage).photo;
  }
  return child is ProfilePhotoImage ? child.photo : null;
}

Widget _buildFlightChild(Widget child, {ProfilePhoto? flightPhoto}) {
  if (child is UserAvatar) {
    return FittedBox(fit: BoxFit.fill, child: child);
  }
  if (child is ClipRRect && child.child is ProfilePhotoImage) {
    final image = child.child as ProfilePhotoImage;
    return ClipRRect(
      borderRadius: child.borderRadius,
      child: ProfilePhotoImage(
        photo: flightPhoto ?? image.photo,
        fit: image.fit,
        placeholderIconSize: image.placeholderIconSize,
        cacheWidth: image.cacheWidth,
        revealOnLoad: false,
      ),
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
