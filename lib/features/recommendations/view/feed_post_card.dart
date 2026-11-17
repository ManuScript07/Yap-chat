import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_post_body.dart';
import 'feed_post_controls.dart';
import 'feed_post_gallery.dart';

class FeedPostCard extends StatelessWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.timeline,
    required this.visible,
    required this.onOpenPost,
    this.details = false,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool visible;
  final ValueChanged<String> onOpenPost;
  final bool details;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        color: context.scaffoldBackgroundColor,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FeedPostHeader(
                post: post,
                timeline: timeline,
                visible: visible,
                details: details,
              ),
              if (post.coordinates != null || post.nearby)
                FeedPostLocation(post: post),
              if (post.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                FeedPostBody(
                  post: post,
                  timeline: timeline,
                  details: details,
                  onOpen: () => onOpenPost(post.id),
                ),
              ],
              if (post.photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                _FeedPhotos(post: post, timeline: timeline, visible: visible),
              ],
              if (post.isQuote)
                FeedQuotePreview(
                  post: post.original,
                  timeline: timeline,
                  onOpenPost: onOpenPost,
                ),
              FeedPostFooter(
                post: post,
                timeline: timeline,
                details: details,
                onOpenPost: onOpenPost,
              ),
              Divider(
                height: 1,
                color: context.colorScheme.onSurface.withValues(alpha: .12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedPhotos extends StatefulWidget {
  const _FeedPhotos({
    required this.post,
    required this.timeline,
    required this.visible,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool visible;

  @override
  State<_FeedPhotos> createState() => _FeedPhotosState();
}

class _FeedPhotosState extends State<_FeedPhotos> {
  final _instance = Object();
  bool _opening = false;

  Future<void> _open(int index, Object tag, ui.Image image) async {
    if (_opening) return;
    _opening = true;
    try {
      await openFeedGallery(
        context,
        timeline: widget.timeline,
        post: widget.post,
        index: index,
        heroTag: tag,
        preview: image,
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final photos = widget.post.photos;
      final width = constraints.maxWidth;
      final tile = width < 360
          ? 132.0
          : width < 600
          ? 164.0
          : 192.0;
      return SizedBox(
        height: tile,
        child: ListView.separated(
          primary: false,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: photos.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, index) {
            final photo = photos[index];
            final tag = (_instance, photo.id);
            return SizedBox(
              width: tile,
              child: _FeedThumbnail(
                key: ValueKey(photo.id),
                timeline: widget.timeline,
                photo: photo,
                visible: widget.visible,
                decodeSize: (tile * MediaQuery.devicePixelRatioOf(context))
                    .ceil(),
                heroTag: tag,
                onOpen: (image) => _open(index, tag, image),
              ),
            );
          },
        ),
      );
    },
  );
}

class _FeedThumbnail extends StatefulWidget {
  const _FeedThumbnail({
    super.key,
    required this.timeline,
    required this.photo,
    required this.decodeSize,
    required this.heroTag,
    required this.onOpen,
    required this.visible,
  });

  final FeedCubit timeline;
  final FeedPhoto photo;
  final int decodeSize;
  final Object heroTag;
  final ValueChanged<ui.Image> onOpen;
  final bool visible;

  @override
  State<_FeedThumbnail> createState() => _FeedThumbnailState();
}

class _FeedThumbnailState extends State<_FeedThumbnail> {
  ui.Image? _image;
  int _generation = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _FeedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photo.thumbnailPath != oldWidget.photo.thumbnailPath ||
        widget.decodeSize != oldWidget.decodeSize) {
      _image?.dispose();
      _image = null;
      _generation++;
      _loading = false;
    }
    if (widget.visible && _image == null && !_loading) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    _loading = true;
    final generation = ++_generation;
    final timeline = widget.timeline;
    final decodeSize = widget.decodeSize;
    bool isCurrent() =>
        mounted && generation == _generation && timeline.isCurrentAccount();
    try {
      final bytes = await timeline.repository.downloadThumbnail(
        widget.photo,
        account: timeline.account,
        stillNeeded: () => isCurrent() && widget.visible,
      );
      if (!isCurrent()) return;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: decodeSize,
        allowUpscaling: false,
      );
      try {
        if (!isCurrent()) return;
        final frame = await codec.getNextFrame();
        if (!isCurrent()) {
          frame.image.dispose();
          return;
        }
        setState(() => _image = frame.image);
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // Keep the tile's dimensions on storage or decoding errors.
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: const _PhotoPlaceholder(),
      );
    }
    return Semantics(
      button: true,
      label: context.l10n.feedOpenPhoto,
      child: GestureDetector(
        onTap: () => widget.onOpen(image),
        child: Hero(
          tag: widget.heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: RawImage(image: image, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colorScheme.onSurface.withValues(alpha: .08),
    child: const Center(child: Icon(Icons.image_outlined)),
  );
}
