import 'dart:io';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class ChatMediaHero extends StatelessWidget {
  const ChatMediaHero({
    super.key,
    required this.path,
    required this.heroTag,
    required this.fit,
    this.cacheWidth,
    this.revealOnLoad = true,
  });

  static const _thumbnailRadius = 20.0;

  final String path;
  final String heroTag;
  final BoxFit fit;
  final int? cacheWidth;
  final bool revealOnLoad;

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
            child: ChatMediaImage(
              path: path,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              revealOnLoad: false,
            ),
          ),
        );
      },
      child: ChatMediaImage(
        path: path,
        fit: fit,
        cacheWidth: cacheWidth,
        revealOnLoad: revealOnLoad,
      ),
    );
  }
}

class ChatMediaImage extends StatelessWidget {
  const ChatMediaImage({
    super.key,
    required this.path,
    required this.fit,
    this.cacheWidth,
    this.revealOnLoad = true,
  });

  final String path;
  final BoxFit fit;
  final int? cacheWidth;
  final bool revealOnLoad;

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
      frameBuilder: revealOnLoad
          ? (context, child, frame, wasSynchronouslyLoaded) =>
                _revealImageFrame(
                  context,
                  child,
                  frame,
                  wasSynchronouslyLoaded,
                  path,
                )
          : null,
      errorBuilder: errorBuilder,
    );
  }
}

Widget _revealImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
  String path,
) {
  final isReady = wasSynchronouslyLoaded || frame != null;
  final shouldReveal = !_revealedChatMediaPaths.contains(path);
  if (isReady) _rememberRevealedChatMedia(path);
  return AnimatedOpacity(
    opacity: !shouldReveal || isReady ? 1 : 0,
    duration: !shouldReveal || wasSynchronouslyLoaded
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    child: child,
  );
}

const _maxRememberedChatMediaPaths = 512;
final LinkedHashSet<String> _revealedChatMediaPaths = LinkedHashSet<String>();

void _rememberRevealedChatMedia(String path) {
  _revealedChatMediaPaths.remove(path);
  _revealedChatMediaPaths.add(path);
  if (_revealedChatMediaPaths.length > _maxRememberedChatMediaPaths) {
    _revealedChatMediaPaths.remove(_revealedChatMediaPaths.first);
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
