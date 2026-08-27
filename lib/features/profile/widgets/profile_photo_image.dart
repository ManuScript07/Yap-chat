import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/data/data.dart';

class ProfilePhotoHero extends StatelessWidget {
  const ProfilePhotoHero({
    super.key,
    required this.photo,
    required this.borderRadius,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  static const _thumbnailRadius = 32.0;

  final ProfilePhoto photo;
  final double borderRadius;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final image = ProfilePhotoImage(
      photo: photo,
      fit: fit,
      cacheWidth: cacheWidth,
    );
    return Hero(
      tag: 'profile-photo-${photo.identity}',
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: (_, animation, _, _, _) {
        final radius = Tween<double>(
          begin: _thumbnailRadius,
          end: 0,
        ).animate(animation);
        return AnimatedBuilder(
          animation: radius,
          builder: (context, child) => ClipRRect(
            borderRadius: BorderRadius.circular(radius.value),
            child: child,
          ),
          child: ColoredBox(
            color: context.scaffoldBackgroundColor,
            child: ProfilePhotoImage(photo: photo, fit: BoxFit.cover),
          ),
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

class ProfilePhotoImage extends StatelessWidget {
  const ProfilePhotoImage({
    super.key,
    required this.photo,
    this.fit = BoxFit.cover,
    this.placeholderIconSize = 64,
    this.cacheWidth,
  });

  final ProfilePhoto photo;
  final BoxFit fit;
  final double placeholderIconSize;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(_, _, _) => _placeholder(context);
    final bytes = photo.bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: errorBuilder,
      );
    }
    final url = photo.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: errorBuilder,
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: context.colorScheme.primary,
    child: Center(
      child: Icon(
        Icons.person_rounded,
        size: placeholderIconSize,
        color: context.colorScheme.onPrimary,
      ),
    ),
  );
}
