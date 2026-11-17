import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_post_body.dart';
import 'feed_post_controls.dart';

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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final size = (constraints.maxWidth / post.photos.length - 6)
                        .clamp(70.0, 170.0);
                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final photo in post.photos)
                          SizedBox.square(
                            dimension: size,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _FeedThumbnail(
                                key: ValueKey(photo.id),
                                timeline: timeline,
                                photo: photo,
                                post: post,
                                visible: visible,
                                decodeSize:
                                    (size *
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ))
                                        .ceil(),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedThumbnail extends StatefulWidget {
  const _FeedThumbnail({
    super.key,
    required this.timeline,
    required this.photo,
    required this.decodeSize,
    required this.post,
    required this.visible,
  });

  final FeedCubit timeline;
  final FeedPhoto photo;
  final int decodeSize;
  final FeedPost post;
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

  Future<void> _preview() async {
    final actions = widget.timeline.actions;
    final source = _image;
    final post = widget.post;
    if (source == null || actions == null || !actions.canShow(post)) return;
    final image = source.clone();
    final accounts = context.read<AccountSessionController?>();
    var revoked = false;
    try {
      final route = DialogRoute<void>(
        context: context,
        builder: (context) {
          Widget preview() => !revoked && actions.canShow(post)
              ? RawImage(image: image, fit: BoxFit.contain)
              : Text(context.l10n.feedPostUnavailable);
          return Dialog(
            child: BlocBuilder<FeedActionsCubit, FeedActionsState>(
              bloc: actions,
              builder: (context, state) {
                revoked |=
                    state.revokedAuthor == post.authorId ||
                    !actions.canShow(post);
                return accounts == null
                    ? preview()
                    : ValueListenableBuilder(
                        valueListenable: accounts.generationChanges,
                        builder: (context, _, _) => preview(),
                      );
              },
            ),
          );
        },
      );
      await Navigator.of(context, rootNavigator: true).push(route);
      await route.completed;
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const _PhotoPlaceholder();
    return Semantics(
      button: true,
      label: context.l10n.feedOpenPhoto,
      child: GestureDetector(
        onTap: _preview,
        child: RawImage(image: image, fit: BoxFit.cover),
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
    color: context.colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.image_outlined)),
  );
}
