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
    required this.headerExtent,
    required this.onHeaderScroll,
    required this.bottomPadding,
    required this.visible,
    required this.onUpdateLocation,
  });

  final FeedCubit timeline;
  final ScrollController controller;
  final double headerExtent;
  final void Function(double pixels, double delta) onHeaderScroll;
  final double bottomPadding;
  final bool visible;
  final VoidCallback? onUpdateLocation;

  @override
  State<FeedTabView> createState() => _FeedTabViewState();
}

class _FeedTabViewState extends State<FeedTabView>
    with AutomaticKeepAliveClientMixin<FeedTabView> {
  bool _scrollingTowardEnd = false;
  late bool _visited = widget.visible;

  // Retain the visited viewport across horizontal swipes. Its vertical sliver
  // still disposes cards outside the viewport and scroll cache.
  @override
  bool get wantKeepAlive => _visited;

  @override
  void didUpdateWidget(covariant FeedTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_visited && widget.visible) {
      _visited = true;
      updateKeepAlive();
    }
  }

  void _onScroll(ScrollNotification notification) {
    if (!widget.visible ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return;
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _scrollingTowardEnd = false;
    }
    if (notification case ScrollUpdateNotification(
      :final metrics,
      :final scrollDelta?,
    )) {
      // Overscroll and its rebound move the refresh content, not the header.
      final before = (metrics.pixels - scrollDelta).clamp(
        metrics.minScrollExtent,
        metrics.maxScrollExtent,
      );
      final after = metrics.pixels.clamp(
        metrics.minScrollExtent,
        metrics.maxScrollExtent,
      );
      widget.onHeaderScroll(after - metrics.minScrollExtent, after - before);
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
          if (mounted && widget.visible) unawaited(timeline.loadMore());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final timeline = widget.timeline;
    if (timeline.tab != FeedTab.nearby) return _scroll();
    return BlocSelector<FeedCubit, FeedState, bool>(
      bloc: timeline,
      selector: (state) => state.failure == FeedFailure.locationRequired,
      builder: (context, requiresLocation) => Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: requiresLocation,
            child: ExcludeSemantics(
              excluding: requiresLocation,
              child: AbsorbPointer(
                absorbing: requiresLocation,
                child: _scroll(requiresLocation: requiresLocation),
              ),
            ),
          ),
          if (requiresLocation) ...[
            const ClipRect(child: LocationRequiredBackdrop()),
            LocationRequiredOverlay(
              bottomInset: widget.bottomPadding,
              onRetry: widget.onUpdateLocation,
            ),
          ],
        ],
      ),
    );
  }

  Widget _scroll({bool requiresLocation = false}) {
    final timeline = widget.timeline;
    return BlocSelector<FeedCubit, FeedState, bool>(
      bloc: timeline,
      selector: (state) =>
          widget.visible &&
          !requiresLocation &&
          !state.loaded &&
          state.rows.posts.isEmpty &&
          state.failure == null,
      builder: (context, initialLoad) => PullRefresh(
        refreshing: initialLoad,
        showExternalProgress: true,
        indicatorTop: widget.headerExtent,
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
            SliverToBoxAdapter(child: SizedBox(height: widget.headerExtent)),
            const SliverPullRefreshGap(),
            _FeedRows(
              timeline: timeline,
              visible: widget.visible && !requiresLocation,
            ),
            BlocSelector<FeedCubit, FeedState, FeedFooter>(
              bloc: timeline,
              selector: (state) => state.footer,
              builder: _footer,
            ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                // Even an empty tab must be able to scroll past the header.
                final remaining =
                    constraints.viewportMainAxisExtent +
                    widget.headerExtent -
                    constraints.precedingScrollExtent;
                return remaining > 0
                    ? SliverToBoxAdapter(child: SizedBox(height: remaining))
                    : const SliverToBoxAdapter();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, FeedFooter state) {
    final timeline = widget.timeline;
    final l10n = context.l10n;
    final failure = state.failure;
    final empty = state.empty;
    if (failure == FeedFailure.locationRequired) {
      return const SliverToBoxAdapter();
    }
    Widget? content;
    if (empty && !state.loaded && failure == null) {
      return const SliverToBoxAdapter();
    }
    if (state.loading) {
      content = const Padding(
        padding: EdgeInsets.all(16),
        child: PullRefreshIndicator(
          opacity: 1,
          progress: 1,
          spinning: true,
          size: 24,
          strokeWidth: 3,
        ),
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
      content = EmptyChatState(message: l10n.feedEmpty);
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
            onOpenPost: (id) => openFeedPost(
              this.context,
              timeline,
              id,
              initial: post.id == id ? post : post.original,
            ),
          );
        },
      ),
    );
  }
}
