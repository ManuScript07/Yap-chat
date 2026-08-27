import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class ChatMediaHero extends StatelessWidget {
  const ChatMediaHero({
    super.key,
    required this.path,
    required this.heroTag,
    required this.fit,
    this.cacheWidth,
  });

  static const _thumbnailRadius = 20.0;

  final String path;
  final String heroTag;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: heroTag,
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
            color: Colors.black,
            child: ChatMediaImage(path: path, fit: BoxFit.cover),
          ),
        );
      },
      child: ChatMediaImage(path: path, fit: fit, cacheWidth: cacheWidth),
    );
  }
}

class ChatMediaImage extends StatelessWidget {
  const ChatMediaImage({
    super.key,
    required this.path,
    required this.fit,
    this.cacheWidth,
  });

  final String path;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(_, _, _) => ColoredBox(
      color: context.scaffoldBackgroundColor,
      child: Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: context.colorScheme.surface,
          size: 48,
        ),
      ),
    );

    return Image(
      image: chatMediaImageProvider(path, cacheWidth: cacheWidth),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: errorBuilder,
    );
  }
}

ImageProvider<Object> chatMediaImageProvider(String path, {int? cacheWidth}) {
  final ImageProvider<Object> provider;
  if (path.startsWith('http://') || path.startsWith('https://')) {
    provider = NetworkImage(path);
  } else {
    provider = FileImage(File(path));
  }
  return ResizeImage.resizeIfNeeded(cacheWidth, null, provider);
}
