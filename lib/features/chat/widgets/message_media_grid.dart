import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/core/core.dart';

import 'widgets.dart';

class MessageMediaGrid extends StatelessWidget {
  const MessageMediaGrid({
    super.key,
    required this.message,
    required this.maxWidth,
    required this.senderName,
    this.senderAvatarUrl,
    this.senderAvatarLoader,
    this.senderAvatarImage,
  });

  final ChatMessage message;
  final double maxWidth;
  final String senderName;
  final String? senderAvatarUrl;
  final Future<String?> Function()? senderAvatarLoader;
  final ImageProvider? senderAvatarImage;

  @override
  Widget build(BuildContext context) {
    final chunks = <List<String>>[];
    for (var start = 0; start < message.mediaUrls.length; start += 5) {
      final end = (start + 5).clamp(0, message.mediaUrls.length).toInt();
      chunks.add(message.mediaUrls.sublist(start, end));
    }

    return Column(
      children: [
        for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) ...[
          if (chunkIndex > 0) const SizedBox(height: 4),
          _MediaAlbum(
            paths: chunks[chunkIndex],
            startIndex: chunkIndex * 5,
            message: message,
            maxWidth: maxWidth,
            senderName: senderName,
            senderAvatarUrl: senderAvatarUrl,
            senderAvatarLoader: senderAvatarLoader,
            senderAvatarImage: senderAvatarImage,
          ),
        ],
      ],
    );
  }
}

class _MediaAlbum extends StatelessWidget {
  const _MediaAlbum({
    required this.paths,
    required this.startIndex,
    required this.message,
    required this.maxWidth,
    required this.senderName,
    this.senderAvatarUrl,
    this.senderAvatarLoader,
    this.senderAvatarImage,
  });

  final List<String> paths;
  final int startIndex;
  final ChatMessage message;
  final double maxWidth;
  final String senderName;
  final String? senderAvatarUrl;
  final Future<String?> Function()? senderAvatarLoader;
  final ImageProvider? senderAvatarImage;

  @override
  Widget build(BuildContext context) {
    final albumSize = maxWidth.clamp(160.0, 300.0).toDouble();

    return RepaintBoundary(
      key: ValueKey('${message.id}:album:$startIndex'),
      child: SizedBox(
        width: albumSize,
        height: paths.length == 1 ? albumSize * .72 : albumSize,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: switch (paths.length) {
            1 => _tile(context, 0),
            2 => Row(
              children: [
                _expandedTile(context, 0),
                _gap(),
                _expandedTile(context, 1),
              ],
            ),
            3 => Row(
              children: [
                Expanded(flex: 2, child: _tile(context, 0)),
                _gap(),
                Expanded(
                  child: Column(
                    children: [
                      _expandedTile(context, 1),
                      _gap(),
                      _expandedTile(context, 2),
                    ],
                  ),
                ),
              ],
            ),
            4 => _fourTileGrid(context, [0, 1, 2, 3]),
            5 => Row(
              children: [
                Expanded(child: _tile(context, 0)),
                _gap(),
                Expanded(child: _fourTileGrid(context, [1, 2, 3, 4])),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _fourTileGrid(BuildContext context, List<int> indices) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _expandedTile(context, indices[0]),
              _gap(),
              _expandedTile(context, indices[1]),
            ],
          ),
        ),
        _gap(),
        Expanded(
          child: Row(
            children: [
              _expandedTile(context, indices[2]),
              _gap(),
              _expandedTile(context, indices[3]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gap() => const SizedBox(width: 3, height: 3);

  Widget _expandedTile(BuildContext context, int index) {
    return Expanded(child: _tile(context, index));
  }

  Widget _tile(BuildContext context, int index) {
    final path = paths[index];
    final absoluteIndex = startIndex + index;
    final isSending = message.status == MessageStatus.sending;
    final isError = message.status == MessageStatus.error;

    return KeyedSubtree(
      key: ValueKey('${message.id}:media:$absoluteIndex'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cacheWidth = path.startsWith('http')
              ? null
              : _cacheWidthFor(context, constraints.maxWidth);
          return Stack(
            fit: StackFit.expand,
            children: [
              ChatMediaHero(
                path: path,
                heroTag: chatMediaHeroTag(message.id, absoluteIndex),
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                borderRadius: _tileBorderRadius(index),
              ),
              if (!isSending && !isError)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        _openGallery(context, absoluteIndex, cacheWidth),
                  ),
                ),
              if (isSending)
                ColoredBox(
                  color: context.scaffoldBackgroundColor.withValues(alpha: 0.4),
                  child: Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        color: context.colorScheme.primary,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              if (isError)
                ColoredBox(
                  color: context.scaffoldBackgroundColor.withValues(alpha: 0.4),
                  child: Center(
                    child: Material(
                      color: context.colorScheme.primary,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => context.read<ChatBloc>().add(
                          ChatMessageRetryRequested(message),
                        ),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.refresh_rounded,
                            color: context.colorScheme.surface,
                            size: 28,
                          ),
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

  BorderRadiusGeometry _tileBorderRadius(int index) {
    const corner = Radius.circular(20);
    return switch ((paths.length, index)) {
      (1, 0) => const BorderRadius.all(corner),
      (2, 0) || (3, 0) || (5, 0) => const BorderRadiusDirectional.only(
        topStart: corner,
        bottomStart: corner,
      ),
      (2, 1) => const BorderRadiusDirectional.only(
        topEnd: corner,
        bottomEnd: corner,
      ),
      (3, 1) ||
      (4, 1) ||
      (5, 2) => const BorderRadiusDirectional.only(topEnd: corner),
      (3, 2) ||
      (4, 3) ||
      (5, 4) => const BorderRadiusDirectional.only(bottomEnd: corner),
      (4, 0) => const BorderRadiusDirectional.only(topStart: corner),
      (4, 2) => const BorderRadiusDirectional.only(bottomStart: corner),
      _ => BorderRadius.zero,
    };
  }

  int _cacheWidthFor(BuildContext context, double logicalWidth) {
    if (!logicalWidth.isFinite || logicalWidth <= 0) return 900;
    final physicalWidth =
        (logicalWidth * MediaQuery.devicePixelRatioOf(context)).ceil();
    return physicalWidth.clamp(1, 900);
  }

  Future<void> _openGallery(
    BuildContext context,
    int index,
    int? thumbnailCacheWidth,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final aspectRatio = chatMediaAspectRatios.lookup(message.mediaUrls[index]);
    final aspectRatios = List<double?>.filled(message.mediaUrls.length, null);
    aspectRatios[index] = aspectRatio;

    final transitionGeometry = ChatMediaTransitionScope.maybeOf(context);
    late final _ChatMediaGalleryRoute route;
    route = _ChatMediaGalleryRoute(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => ChatMediaGalleryPage(
        imagePaths: message.mediaUrls,
        heroTags: List.generate(
          message.mediaUrls.length,
          (imageIndex) => chatMediaHeroTag(message.id, imageIndex),
        ),
        initialIndex: index,
        initialThumbnailCacheWidth: thumbnailCacheWidth,
        senderName: senderName,
        sentAt: message.timestamp,
        senderAvatarUrl: senderAvatarUrl,
        senderAvatarLoader: senderAvatarLoader,
        senderAvatarImage: senderAvatarImage,
        imageAspectRatios: aspectRatios,
        transitionGeometry: transitionGeometry,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          transitionGeometry?.localFlight.routeTransition(
            route.mediaAnimation,
            child,
          ) ??
          FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          ),
    );
    final completion = Navigator.of(context).push(route);
    transitionGeometry?.localFlight.follow(
      route.mediaAnimation,
      tag: chatMediaHeroTag(message.id, index),
      ratio: aspectRatio,
    );
    final animation = route.mediaAnimation;
    unawaited(
      route.completed.then(
        (_) => transitionGeometry?.localFlight.release(animation),
      ),
    );
    await completion;
  }
}

class _ChatMediaGalleryRoute extends PageRouteBuilder<void> {
  _ChatMediaGalleryRoute({
    required super.pageBuilder,
    required super.transitionsBuilder,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
  });

  // ModalRoute.animation is a proxy: HeroController temporarily replaces it
  // with a completed animation for offstage layout, before any time advances.
  // Use the SAME route controller's read-only view for visible local effects.
  // No additional ticker/controller and no changes to Navigator/Hero behavior.
  Animation<double> get mediaAnimation => controller!.view;
}

String chatMediaHeroTag(String messageId, int imageIndex) {
  return 'chat-media-$messageId-$imageIndex';
}
