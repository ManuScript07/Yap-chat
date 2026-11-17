import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_card.dart';
import 'feed_post_details.dart';

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
          return _cards[post] ??= FeedPostCard(
            key: ValueKey(post.id),
            post: post,
            timeline: timeline,
            visible: widget.visible,
            onOpenPost: (id) => openFeedPost(this.context, timeline, id),
          );
        },
      ),
    );
  }
}
