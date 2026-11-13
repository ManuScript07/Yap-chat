import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_text.dart';

class FeedTabView extends StatefulWidget {
  const FeedTabView({
    super.key,
    required this.timeline,
    required this.controller,
    required this.header,
    required this.bottomPadding,
    required this.visible,
    required this.onUpdateLocation,
  });

  final FeedCubit timeline;
  final ScrollController controller;
  final Widget header;
  final double bottomPadding;
  final bool visible;
  final VoidCallback? onUpdateLocation;

  @override
  State<FeedTabView> createState() => _FeedTabViewState();
}

class _FeedTabViewState extends State<FeedTabView> {
  bool _scrollingTowardEnd = false;

  void _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return;
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _scrollingTowardEnd = false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _scrollingTowardEnd = (notification.scrollDelta ?? 0) > 0;
    }
    if (notification is ScrollUpdateNotification &&
        _scrollingTowardEnd &&
        notification.metrics.extentAfter < 480) {
      final timeline = widget.timeline;
      final state = timeline.state;
      if (state.canContinue && !state.loading && state.failure == null) {
        _scrollingTowardEnd = false;
        // Scroll notifications arrive after layout. Start the request outside it.
        scheduleMicrotask(() {
          if (mounted) unawaited(timeline.loadMore());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.timeline;
    final media = MediaQuery.paddingOf(context);
    return PullRefresh(
      indicatorTop: PrimaryHeaderGeometry.compactTabsContentTop,
      indicatorKey: const ValueKey('feed_pull_indicator'),
      useSliverInset: true,
      onRefresh: timeline.refresh,
      onScroll: _onScroll,
      child: CustomScrollView(
        key: PageStorageKey((timeline.tab, timeline.account.generation)),
        controller: widget.controller,
        physics: PullRefresh.physics,
        scrollCacheExtent: const ScrollCacheExtent.pixels(160),
        slivers: [
          PinnedHeaderSliver(child: widget.header),
          const SliverPullRefreshGap(),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              media.left + 16,
              0,
              media.right + 16,
              0,
            ),
            sliver: _FeedRows(timeline: timeline, visible: widget.visible),
          ),
          BlocSelector<FeedCubit, FeedState, FeedFooter>(
            bloc: timeline,
            selector: (state) => state.footer,
            builder: _footer,
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, FeedFooter state) {
    final timeline = widget.timeline;
    final l10n = context.l10n;
    final failure = state.failure;
    final empty = state.empty;
    Widget? content;
    if (state.loading || !state.loaded && failure == null) {
      content = const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (failure == FeedFailure.locationRequired) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.feedLocationRequired, textAlign: TextAlign.center),
          TextButton(
            onPressed: widget.onUpdateLocation,
            child: Text(l10n.nearbyLocationUpdate),
          ),
        ],
      );
    } else if (failure != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.feedLoadFailed, textAlign: TextAlign.center),
          TextButton(onPressed: timeline.retry, child: Text(l10n.feedRetry)),
        ],
      );
    } else if (state.canContinue) {
      content = TextButton(
        onPressed: timeline.loadMore,
        child: Text(l10n.feedLoadMore),
      );
    } else if (empty) {
      content = Text(l10n.feedEmpty, textAlign: TextAlign.center);
    }

    final body = Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, widget.bottomPadding),
      child: Center(child: content),
    );
    return empty
        ? SliverFillRemaining(hasScrollBody: false, child: body)
        : SliverToBoxAdapter(child: body);
  }
}

class _FeedRows extends StatefulWidget {
  const _FeedRows({required this.timeline, required this.visible});

  final FeedCubit timeline;
  final bool visible;

  @override
  State<_FeedRows> createState() => _FeedRowsState();
}

class _FeedRowsState extends State<_FeedRows> {
  // The delegate may revisit mounted children when its count changes.
  // Reuse their widget instances, while letting removed posts be collected.
  Expando<Widget> _cards = Expando();

  @override
  void didUpdateWidget(covariant _FeedRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _cards = Expando();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.timeline;
    return BlocSelector<FeedCubit, FeedState, FeedRows>(
      bloc: timeline,
      selector: (state) => state.rows,
      builder: (context, rows) => SliverList.builder(
        itemCount: rows.posts.length,
        addAutomaticKeepAlives: false,
        findChildIndexCallback: (key) =>
            rows.indexOf((key as ValueKey<String>).value),
        itemBuilder: (context, index) {
          final post = rows.posts[index];
          return _cards[post] ??= _FeedCard(
            key: ValueKey(post.id),
            post: post,
            timeline: timeline,
            visible: widget.visible,
          );
        },
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    super.key,
    required this.post,
    required this.timeline,
    required this.visible,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final date = post.createdAt.toLocal();
    final textStyle = context.textTheme.bodyLarge ?? const TextStyle();
    final body = feedPostText(post, textStyle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                post.authorName ?? context.l10n.feedUnknownAuthor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleMedium,
              ),
              Text(
                '${localizations.formatShortDate(date)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
                style: context.textTheme.bodySmall,
              ),
              if (post.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const collapsedLines = 5;
                    final painter = TextPainter(
                      text: body,
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: collapsedLines,
                    )..layout(maxWidth: constraints.maxWidth);
                    final canExpand = painter.didExceedMaxLines;
                    painter.dispose();
                    return BlocSelector<FeedCubit, FeedState, bool>(
                      bloc: timeline,
                      selector: (state) => state.expandedIds.contains(post.id),
                      builder: (context, expanded) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (post.formatting.isEmpty)
                            Text(
                              post.text,
                              style: textStyle,
                              maxLines: expanded ? null : collapsedLines,
                              overflow: expanded ? null : TextOverflow.ellipsis,
                            )
                          else
                            Text.rich(
                              body,
                              maxLines: expanded ? null : collapsedLines,
                              overflow: expanded ? null : TextOverflow.ellipsis,
                            ),
                          if (canExpand)
                            TextButton(
                              onPressed: () => timeline.toggleExpanded(post.id),
                              child: Text(
                                expanded
                                    ? context.l10n.feedShowLess
                                    : context.l10n.feedShowMore,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
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
                              child: visible
                                  ? _FeedThumbnail(
                                      key: ValueKey(photo.id),
                                      timeline: timeline,
                                      photo: photo,
                                      decodeSize:
                                          (size *
                                                  MediaQuery.devicePixelRatioOf(
                                                    context,
                                                  ))
                                              .ceil(),
                                    )
                                  : const _PhotoPlaceholder(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
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
  });

  final FeedCubit timeline;
  final FeedPhoto photo;
  final int decodeSize;

  @override
  State<_FeedThumbnail> createState() => _FeedThumbnailState();
}

class _FeedThumbnailState extends State<_FeedThumbnail> {
  ui.Image? _image;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _FeedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photo.thumbnailPath != oldWidget.photo.thumbnailPath ||
        widget.decodeSize != oldWidget.decodeSize) {
      _image?.dispose();
      _image = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final timeline = widget.timeline;
    final decodeSize = widget.decodeSize;
    bool isCurrent() =>
        mounted && generation == _generation && timeline.isCurrentAccount();
    try {
      final bytes = await timeline.repository.downloadThumbnail(
        widget.photo,
        account: timeline.account,
        stillNeeded: isCurrent,
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
    }
  }

  @override
  Widget build(BuildContext context) => _image == null
      ? const _PhotoPlaceholder()
      : RawImage(image: _image, fit: BoxFit.cover);

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
