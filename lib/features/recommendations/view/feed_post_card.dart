import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/features/recommendations/data/feed_media_frames.dart';
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
    this.onComments,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool visible;
  final ValueChanged<String> onOpenPost;
  final bool details;
  final VoidCallback? onComments;

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
    final contentInsets = EdgeInsets.only(
      left: safe.left + gutter,
      right: safe.right + gutter,
    );
    const avatarSize = 40.0;
    const authorGap = 10.0;
    const headerEndAdjustment = 4.0;
    final leftToRight = Directionality.of(context) == TextDirection.ltr;
    final headerInsets = leftToRight
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
          padding: const EdgeInsets.only(top: separatorSpacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: headerInsets, child: header),
              if (post.text.isNotEmpty) ...[
                const SizedBox(height: 4),
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
                    if (details) _DetailsTimestamp(post: post),
                    FeedPostFooter(
                      post: post,
                      timeline: timeline,
                      details: details,
                      bottomSpacing: separatorSpacing,
                      onOpenPost: widget.onOpenPost,
                      onComments: widget.onComments,
                    ),
                  ],
                ),
              ),
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

class _DetailsTimestamp extends StatelessWidget {
  const _DetailsTimestamp({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final date = post.createdAt.toLocal();
    final format = MaterialLocalizations.of(context);
    final time = format.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        '$time · ${format.formatMediumDate(date)} · ${date.year}'
        '${post.edited ? ' · ${context.l10n.feedEdited}' : ''}',
        style: AppTextStyles.metadata.copyWith(
          color: context.colorScheme.outline,
          fontWeight: FontWeight.w600,
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
        heroTags: [
          for (final photo in widget.post.photos) (_instance, photo.id),
        ],
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
      final media = MediaQuery.of(context);
      final landscape = media.orientation == Orientation.landscape;
      final available = math.max(
        1.0,
        constraints.maxWidth - widget.padding.horizontal - widget.leadingInset,
      );
      final height = landscape
          ? (media.size.height * .40).clamp(88.0, 164.0)
          : (available * .66).clamp(144.0, 208.0);
      final maxWidth = math.min(available, landscape ? 300.0 : 460.0);
      final minWidth = math.min(maxWidth, height * .55);
      return SizedBox(
        height: height,
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
            final width = (height * (photo.aspectRatio ?? 1)).clamp(
              minWidth,
              maxWidth,
            );
            return SizedBox(
              width: width,
              child: _FeedThumbnail(
                key: ValueKey(photo.id),
                timeline: widget.timeline,
                post: widget.post,
                photo: photo,
                visible: widget.visible,
                decodeSize: (math.max(width, height) * media.devicePixelRatio)
                    .ceil()
                    .clamp(1, 900),
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
    required this.post,
    required this.photo,
    required this.decodeSize,
    required this.heroTag,
    required this.onOpen,
    required this.visible,
  });

  final FeedCubit timeline;
  final FeedPost post;
  final FeedPhoto photo;
  final int decodeSize;
  final Object heroTag;
  final ValueChanged<ui.Image> onOpen;
  final bool visible;

  @override
  State<_FeedThumbnail> createState() => _FeedThumbnailState();
}

class _FeedThumbnailState extends State<_FeedThumbnail> {
  static const _radius = BorderRadius.all(
    Radius.circular(feedPhotoPreviewRadius),
  );
  ui.Image? _image;
  int? _frameSize;
  int _generation = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _FeedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedPhoto =
        widget.photo.thumbnailPath != oldWidget.photo.thumbnailPath ||
        widget.timeline.account != oldWidget.timeline.account;
    final needsFrame =
        changedPhoto || widget.decodeSize != oldWidget.decodeSize;
    if (changedPhoto) {
      _image?.dispose();
      _image = null;
      _frameSize = null;
    }
    if (needsFrame) {
      _generation++;
      _loading = false;
    }
    if (_frameSize != widget.decodeSize &&
        !_loading &&
        (widget.visible || _image == null)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    _loading = true;
    final generation = ++_generation;
    final timeline = widget.timeline;
    final post = widget.post;
    final photo = widget.photo;
    final decodeSize = widget.decodeSize;
    final frames = timeline.actions?.thumbnailFrames;
    bool isCurrent() =>
        mounted &&
        generation == _generation &&
        timeline.isCurrentAccount() &&
        timeline.actions?.canShow(post) != false;
    try {
      if (!isCurrent()) return;
      var frame = frames?.find(post, photo.thumbnailPath, decodeSize);
      if (frame == null) {
        // PageView builds an incoming tab before it becomes active. Resolve a
        // cached frame synchronously, including after a change of tile size.
        if (_image == null) {
          final fallback = frames?.findPreview(post, photo.thumbnailPath);
          if (fallback != null) _showFrame(fallback, null);
        }
        if (!widget.visible) return;
        final bytes = await timeline.repository.downloadThumbnail(
          photo,
          post: post,
          account: timeline.account,
          stillNeeded: () => isCurrent() && widget.visible,
        );
        if (!isCurrent()) return;
        frame = await decodeFeedFrame(bytes, decodeSize);
        if (!isCurrent()) {
          frame.dispose();
          return;
        }
        frames?.store(post, photo.thumbnailPath, decodeSize, frame);
      }
      _showFrame(frame, decodeSize);
    } catch (_) {
      // Keep the tile's dimensions on storage or decoding errors.
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  void _showFrame(ui.Image frame, int? decodeSize) {
    final preceding = _image;
    setState(() {
      _image = frame;
      _frameSize = decodeSize;
    });
    preceding?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return GestureDetector(
        onTap: () {
          if (widget.visible && !_loading) unawaited(_load());
        },
        child: const ClipRRect(
          borderRadius: _radius,
          child: _PhotoPlaceholder(),
        ),
      );
    }
    final ratio = feedPhotoDisplayRatio(
      widget.photo.aspectRatio ?? image.width / image.height,
      MediaQuery.sizeOf(context),
      MediaQuery.devicePixelRatioOf(context),
    );
    return Semantics(
      button: true,
      label: context.l10n.feedOpenPhoto,
      child: GestureDetector(
        onTap: () => widget.onOpen(image),
        child: Hero(
          tag: widget.heroTag,
          child: ClipRRect(
            borderRadius: _radius,
            child: feedPhotoFrame(image, ratio, BoxFit.cover),
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
