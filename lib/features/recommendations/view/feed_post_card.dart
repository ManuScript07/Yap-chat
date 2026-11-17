import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_body.dart';
import 'feed_post_controls.dart';
import 'feed_post_gallery.dart';

class FeedPostCard extends StatefulWidget {
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
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> {
  bool _openingProfile = false;

  Future<void> _openProfile() async {
    final timeline = widget.timeline;
    final actions = timeline.actions;
    if (_openingProfile ||
        ModalRoute.isCurrentOf(context) == false ||
        !timeline.isCurrentAccount() ||
        actions?.canShow(widget.post) == false ||
        actions?.beginProfile() == false) {
      return;
    }
    final authorId = widget.post.authorId;
    setState(() => _openingProfile = true);
    try {
      // Register just the tapped avatar with the navigator before the push.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !timeline.isCurrentAccount() ||
          ModalRoute.isCurrentOf(context) == false ||
          actions?.canShow(widget.post) == false ||
          widget.post.authorId != authorId) {
        return;
      }
      await openViewedProfile(context, userId: authorId, waitForClose: true);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      actions?.endProfile();
      if (mounted) setState(() => _openingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final timeline = widget.timeline;
    final details = widget.details;
    final safe = MediaQuery.paddingOf(context);
    const gutter = PrimaryHeaderGeometry.horizontalPadding;
    final contentInsets = details
        ? const EdgeInsets.symmetric(horizontal: 14)
        : EdgeInsets.only(left: safe.left + gutter, right: safe.right + gutter);
    const avatarSize = 40.0;
    const authorGap = 10.0;
    const headerEndAdjustment = 4.0;
    final leftToRight = Directionality.of(context) == TextDirection.ltr;
    final headerInsets = details
        ? contentInsets
        : leftToRight
        ? contentInsets.copyWith(
            right: contentInsets.right - headerEndAdjustment,
          )
        : contentInsets.copyWith(
            left: contentInsets.left - headerEndAdjustment,
          );
    final textInsets = leftToRight
        ? contentInsets.copyWith(
            left: contentInsets.left + avatarSize + authorGap,
          )
        : contentInsets.copyWith(
            right: contentInsets.right + avatarSize + authorGap,
          );
    final avatar = FeedPostAuthorAvatar(
      post: post,
      timeline: timeline,
      visible: widget.visible,
      size: avatarSize,
      heroEnabled: _openingProfile,
      onOpenProfile: post.authorId == timeline.account.userId
          ? null
          : _openProfile,
    );
    void openPost() {
      if (timeline.actions?.canShow(post) != false) widget.onOpenPost(post.id);
    }

    final header = FeedPostHeader(
      post: post,
      timeline: timeline,
      details: details,
      avatar: avatar,
      onOpenProfile: post.authorId == timeline.account.userId
          ? null
          : _openProfile,
    );

    const separatorSpacing = 14.0;
    return Card(
      margin: EdgeInsets.zero,
      color: context.scaffoldBackgroundColor,
      elevation: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: details ? null : openPost,
        child: Padding(
          padding: EdgeInsets.only(
            top: separatorSpacing,
            bottom: details ? 24 : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: headerInsets, child: header),
              if (post.text.isNotEmpty) ...[
                SizedBox(height: details ? 6 : 4),
                Padding(
                  padding: details ? contentInsets : textInsets,
                  child: FeedPostBody(
                    post: post,
                    timeline: timeline,
                    details: details,
                    onOpen: openPost,
                  ),
                ),
              ],
              if (post.photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                _FeedPhotos(
                  post: post,
                  timeline: timeline,
                  visible: widget.visible,
                  padding: contentInsets,
                  leadingInset: details ? 0 : avatarSize + authorGap,
                ),
              ],
              Padding(
                padding: details ? contentInsets : textInsets,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (post.isQuote)
                      FeedQuotePreview(
                        post: post.original,
                        timeline: timeline,
                        onOpenPost: widget.onOpenPost,
                      ),
                    FeedPostFooter(
                      post: post,
                      timeline: timeline,
                      details: details,
                      bottomSpacing: details ? 0 : separatorSpacing,
                      onOpenPost: widget.onOpenPost,
                    ),
                  ],
                ),
              ),
              if (details)
                Padding(padding: contentInsets, child: _divider(context))
              else
                _divider(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
    height: 1,
    color: context.colorScheme.onSurface.withValues(alpha: .12),
  );
}

class _FeedPhotos extends StatefulWidget {
  const _FeedPhotos({
    required this.post,
    required this.timeline,
    required this.visible,
    required this.padding,
    required this.leadingInset,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool visible;
  final EdgeInsets padding;
  final double leadingInset;

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
      final width = constraints.maxWidth - widget.padding.horizontal;
      final tile = width < 360
          ? 132.0
          : width < 600
          ? 164.0
          : 192.0;
      return SizedBox(
        height: tile,
        child: ListView.separated(
          key: PageStorageKey(('feed-photos', widget.post.id)),
          primary: false,
          scrollDirection: Axis.horizontal,
          padding: widget.padding.add(
            EdgeInsetsDirectional.only(start: widget.leadingInset),
          ),
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
