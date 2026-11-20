import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_controls.dart';
import 'feed_comment_motion.dart';

typedef _CommentListItem = ({
  Key key,
  Widget Function() build,
  String? expandedThread,
  FeedComment? comment,
});

class FeedCommentsSliver extends StatefulWidget {
  const FeedCommentsSliver({
    super.key,
    required this.comments,
    required this.timeline,
    required this.onReply,
    required this.onRetryPublication,
    required this.refreshing,
    required this.postFailed,
    required this.viewport,
  });

  final FeedCommentsCubit comments;
  final FeedCubit timeline;
  final ValueChanged<FeedComment> onReply;
  final VoidCallback onRetryPublication;
  final bool refreshing;
  final bool postFailed;
  final Rect? Function() viewport;

  @override
  State<FeedCommentsSliver> createState() => FeedCommentsSliverState();
}

class FeedCommentsSliverState extends State<FeedCommentsSliver> {
  final _list = GlobalKey();
  List<_CommentListItem> _rows = const [];
  final _entering = <Key>{};
  Timer? _entryWindow;
  FeedCommentSort? _presentedSort;
  bool _presentedHead = false;

  Iterable<(_CommentListItem, double)> _visibleRows(
    double top,
    double bottom,
  ) sync* {
    final list = _list.currentContext?.findRenderObject();
    if (list is! RenderSliverMultiBoxAdaptor || !list.attached) return;
    for (var row = list.firstChild; row != null; row = list.childAfter(row)) {
      final index = list.indexOf(row);
      if (index >= _rows.length || !row.hasSize) continue;
      final start = row.localToGlobal(Offset.zero).dy;
      final offset = list.childScrollOffset(row);
      if (offset != null && start < bottom && start + row.size.height > top) {
        yield (_rows[index], offset - list.constraints.scrollOffset);
      }
    }
  }

  Set<String> visibleThreads({required double top, required double bottom}) => {
    for (final (row, _) in _visibleRows(top, bottom)) ?row.expandedThread,
  };

  Map<String?, String> visibleAnchors() {
    final viewport = widget.viewport();
    if (viewport == null) return {};
    final anchors = <String?, String>{};
    for (final (row, _) in _visibleRows(viewport.top, viewport.bottom)) {
      final comment = row.comment;
      if (comment == null) continue;
      anchors.putIfAbsent(null, () => comment.threadId);
      if (comment.id != comment.threadId) {
        anchors.putIfAbsent(comment.threadId, () => comment.id);
      }
    }
    return anchors;
  }

  FeedCommentScrollAnchor? _updateRows(
    List<_CommentListItem> rows,
    Map<Key, int> positions,
    FeedCommentsState state,
  ) {
    final sameSort = _presentedSort == state.sort;
    final changed =
        rows.length != _rows.length ||
        rows.indexed.any((item) => item.$2.key != _rows[item.$1].key);
    FeedCommentScrollAnchor? anchor;
    if (sameSort && changed) {
      final viewport = widget.viewport();
      if (viewport != null) {
        for (final (row, offset) in _visibleRows(
          viewport.top,
          viewport.bottom,
        )) {
          if (row.comment == null) continue;
          if (positions[row.key] case final index?) {
            anchor = (index: index, offset: offset);
            break;
          }
        }
      }
      if (_presentedHead && !MediaQuery.disableAnimationsOf(context)) {
        final previous = {for (final item in _rows) item.key};
        for (final row in rows) {
          if (row.comment != null && !previous.contains(row.key)) {
            _entering.add(row.key);
          }
        }
        if (_entering.isNotEmpty) {
          _entryWindow?.cancel();
          _entryWindow = Timer(feedCommentMotionDuration, _entering.clear);
        }
      }
    } else if (!sameSort) {
      _entering.clear();
    }
    _presentedSort = state.sort;
    _presentedHead = state.loaded;
    _rows = rows;
    return anchor;
  }

  @override
  void dispose() {
    _entryWindow?.cancel();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<FeedCommentsCubit, FeedCommentsState>(
    bloc: widget.comments,
    builder: (context, state) {
      final comments = widget.comments;
      if (!comments.canDisplay) return const SliverToBoxAdapter();
      final l10n = context.l10n;
      final padding = MediaQuery.paddingOf(context);
      final locale = Localizations.localeOf(context).toString();
      final compactCount = NumberFormat.compact(locale: locale);
      final fullCount = NumberFormat.decimalPattern(locale);
      final rows = <_CommentListItem>[];
      for (final (index, root) in state.rows.indexed) {
        final replies = comments.replies(root);
        final expanded = comments.isExpanded(root.id);
        final hasBranch = root.replyCount > 0 || replies.isNotEmpty;
        void add(
          FeedComment comment, {
          required bool before,
          required bool after,
        }) {
          rows.add((
            key: ValueKey(comment.id),
            build: () => _CommentRow(
              comment: comment,
              comments: comments,
              timeline: widget.timeline,
              onReply: widget.onReply,
              compactCount: compactCount,
              fullCount: fullCount,
              before: before,
              after: after,
            ),
            expandedThread: expanded ? root.id : null,
            comment: comment,
          ));
        }

        add(root, before: false, after: hasBranch);
        for (final reply in replies) {
          add(reply, before: true, after: reply != replies.last);
        }
        final status = comments.threadStatus(root.id);
        final canExpand = !expanded && root.replyCount > replies.length;
        if (canExpand || expanded) {
          rows.add((
            key: ValueKey(('thread', root.id)),
            build: () => Padding(
              padding: EdgeInsetsDirectional.only(
                start:
                    (Directionality.of(context) == TextDirection.ltr
                        ? padding.left
                        : padding.right) +
                    _CommentRow.contentInset,
              ),
              child: _ThreadFeedback(
                loading: expanded && status.loading && !widget.refreshing,
                retry:
                    expanded &&
                        !status.loading &&
                        status.failed &&
                        !widget.refreshing &&
                        !widget.postFailed
                    ? RetryPillButton(
                        label: l10n.feedRetry,
                        onPressed: comments.canMutate
                            ? () => comments.nextReplies(root.id)
                            : widget.onRetryPublication,
                      )
                    : null,
                action:
                    expanded &&
                        !status.loading &&
                        !status.failed &&
                        status.more &&
                        !widget.refreshing
                    ? TextButton(
                        onPressed: () => comments.nextReplies(root.id),
                        child: Text(l10n.feedLoadMore),
                      )
                    : canExpand
                    ? TextButton(
                        onPressed: () => comments.expand(root.id),
                        style:
                            FeedActionButton.style(
                              AlignmentDirectional.centerStart,
                            ).copyWith(
                              textStyle: WidgetStatePropertyAll(
                                context.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        child: Text(l10n.feedShowReplies),
                      )
                    : null,
              ),
            ),
            expandedThread: expanded ? root.id : null,
            comment: null,
          ));
        }
        if (index + 1 < state.rows.length) {
          rows.add((
            key: ValueKey(('divider', root.id)),
            build: FeedDivider.new,
            expandedThread: null,
            comment: null,
          ));
        }
      }
      final positions = {for (final (i, row) in rows.indexed) row.key: i};
      final anchor = _updateRows(rows, positions, state);
      return _CommentRefreshScope(
        refreshing: widget.refreshing,
        child: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(
                  left: padding.left + PrimaryHeaderGeometry.horizontalPadding,
                  right:
                      padding.right + PrimaryHeaderGeometry.horizontalPadding,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _CommentSortMenu(
                    selected: state.sort,
                    onSelected: comments.selectSort,
                  ),
                ),
              ),
            ),
            FeedCommentList(
              key: _list,
              anchor: anchor,
              delegate: SliverChildBuilderDelegate(
                (_, index) {
                  final row = rows[index];
                  return row.comment == null
                      ? KeyedSubtree(key: row.key, child: row.build())
                      : FeedCommentEntrance(
                          key: row.key,
                          animate: _entering.remove(row.key),
                          child: row.build(),
                        );
                },
                childCount: rows.length,
                findChildIndexCallback: (key) => positions[key],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  padding.left + PrimaryHeaderGeometry.horizontalPadding,
                  12,
                  padding.right + PrimaryHeaderGeometry.horizontalPadding,
                  12,
                ),
                child: _CommentLoadFeedback(
                  state: state,
                  refreshing: widget.refreshing,
                  postFailed: widget.postFailed,
                  onRequest:
                      state.failed &&
                          (!comments.canMutate || comments.needsHeadRetry)
                      ? widget.onRetryPublication
                      : comments.next,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ThreadFeedback extends StatelessWidget {
  const _ThreadFeedback({required this.loading, this.action, this.retry});

  final bool loading;
  final Widget? action;
  final Widget? retry;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : feedCommentMotionDuration;
    return IgnorePointer(
      ignoring: loading,
      child: AnimatedSize(
        duration: duration,
        alignment: AlignmentDirectional.topStart,
        curve: Curves.easeOutCubic,
        child: AnimatedStatusSwitcher(
          duration: duration,
          alignment: AlignmentDirectional.topStart,
          scaleTransition: false,
          child: switch ((loading, retry, action)) {
            (true, _, _) => const SizedBox(
              key: ValueKey('thread_loading'),
              height: 44,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: _CommentProgress(),
              ),
            ),
            (false, final button?, _) => KeyedSubtree(
              key: const ValueKey('thread_retry'),
              child: button,
            ),
            (false, null, final button?) => KeyedSubtree(
              key: const ValueKey('thread_action'),
              child: button,
            ),
            _ => const SizedBox.shrink(key: ValueKey('thread_idle')),
          },
        ),
      ),
    );
  }
}

class _CommentSortMenu extends StatefulWidget {
  const _CommentSortMenu({required this.selected, required this.onSelected});

  final FeedCommentSort selected;
  final ValueChanged<FeedCommentSort> onSelected;

  @override
  State<_CommentSortMenu> createState() => _CommentSortMenuState();
}

class _CommentSortMenuState extends State<_CommentSortMenu> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colorScheme;
    final textStyle = AppTextStyles.chatName.copyWith(fontSize: 15);
    const panelInset = 4.0;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final panelColor = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .08),
      context.scaffoldBackgroundColor,
    );
    String label(FeedCommentSort sort) => switch (sort) {
      FeedCommentSort.popular => l10n.feedCommentsPopular,
      FeedCommentSort.newFirst => l10n.feedCommentsNew,
      FeedCommentSort.old => l10n.feedCommentsOld,
    };

    return MenuAnchor(
      animated: animate,
      clipBehavior: Clip.antiAlias,
      crossAxisUnconstrained: false,
      onAnimationStatusChanged: (status) {
        final open = status.isForwardOrCompleted;
        if (_open != open) setState(() => _open = open);
      },
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomStart,
        backgroundColor: WidgetStatePropertyAll(panelColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(panelInset)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        for (final sort in FeedCommentSort.values)
          MenuItemButton(
            key: ValueKey(sort),
            clipBehavior: Clip.antiAlias,
            style:
                MenuItemButton.styleFrom(
                  foregroundColor: sort == widget.selected
                      ? colors.primary
                      : colors.onSurface,
                  textStyle: textStyle,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ).copyWith(
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return Colors.transparent;
                    }
                    return states.contains(WidgetState.focused) ||
                            states.contains(WidgetState.hovered)
                        ? colors.onSurface.withValues(alpha: .08)
                        : Colors.transparent;
                  }),
                ),
            onPressed: () => widget.onSelected(sort),
            child: Semantics(
              selected: sort == widget.selected,
              child: Text(label(sort)),
            ),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: l10n.feedCommentsSort,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: colors.onSurface,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            visualDensity: VisualDensity.standard,
            overlayColor: Colors.transparent,
            textStyle: textStyle,
          ),
          onPressed: () => _open ? controller.close() : controller.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label(widget.selected),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Transform.translate(
                offset: const Offset(0, 2),
                child: AnimatedRotation(
                  turns: _open ? .5 : 0,
                  duration: animate
                      ? const Duration(milliseconds: 180)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.expand_more_rounded, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentLoadFeedback extends StatefulWidget {
  const _CommentLoadFeedback({
    required this.state,
    required this.onRequest,
    required this.refreshing,
    required this.postFailed,
  });

  final FeedCommentsState state;
  final VoidCallback onRequest;
  final bool refreshing;
  final bool postFailed;

  @override
  State<_CommentLoadFeedback> createState() => _CommentLoadFeedbackState();
}

class _CommentLoadFeedbackState extends State<_CommentLoadFeedback> {
  Timer? _progressDelay;
  bool _showProgress = false;

  @override
  void initState() {
    super.initState();
    _updateProgress();
  }

  @override
  void didUpdateWidget(covariant _CommentLoadFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.loading != widget.state.loading ||
        oldWidget.refreshing != widget.refreshing ||
        oldWidget.state.sort != widget.state.sort) {
      _updateProgress();
    }
  }

  void _updateProgress() {
    _progressDelay?.cancel();
    _showProgress = false;
    if (widget.state.loading && !widget.refreshing) {
      _progressDelay = Timer(const Duration(milliseconds: 180), () {
        setState(() => _showProgress = true);
      });
    }
  }

  @override
  void dispose() {
    _progressDelay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l10n = context.l10n;
    final Widget content;
    if (widget.refreshing) {
      content = const SizedBox(height: 22, key: ValueKey('waiting'));
    } else if (state.loading) {
      content = _showProgress
          ? const _CommentProgress(key: ValueKey('loading'))
          : const SizedBox(height: 22, key: ValueKey('waiting'));
    } else if (state.failed) {
      content = Column(
        key: const ValueKey('failed'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.rows.isEmpty) ...[
            EmptyChatState(
              message: l10n.feedCommentsLoadFailed,
              showImage: false,
            ),
            if (!widget.postFailed) const SizedBox(height: 24),
          ],
          if (!widget.postFailed)
            RetryPillButton(label: l10n.feedRetry, onPressed: widget.onRequest),
        ],
      );
    } else if (!state.loaded) {
      content = const SizedBox.shrink(key: ValueKey('pending_head'));
    } else if (state.hasMore) {
      content = TextButton(
        key: const ValueKey('more'),
        onPressed: widget.onRequest,
        child: Text(l10n.feedLoadMore),
      );
    } else if (state.rows.isEmpty) {
      content = EmptyChatState(
        key: const ValueKey('empty'),
        message: l10n.feedNoComments,
        showImage: false,
      );
    } else {
      content = const SizedBox.shrink(key: ValueKey('finished'));
    }
    return ExcludeSemantics(
      excluding: widget.refreshing,
      child: IgnorePointer(
        ignoring: widget.refreshing,
        child: AnimatedStatusSwitcher(
          alignment: Alignment.topCenter,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          scaleTransition: false,
          child: content,
        ),
      ),
    );
  }
}

class _CommentRefreshScope extends InheritedWidget {
  const _CommentRefreshScope({required this.refreshing, required super.child});

  final bool refreshing;

  @override
  bool updateShouldNotify(_CommentRefreshScope oldWidget) =>
      refreshing != oldWidget.refreshing;
}

class _CommentProgress extends StatelessWidget {
  const _CommentProgress({super.key});

  @override
  Widget build(BuildContext context) {
    if (context
            .dependOnInheritedWidgetOfExactType<_CommentRefreshScope>()
            ?.refreshing ==
        true) {
      return const SizedBox.square(dimension: 22);
    }
    return const PullRefreshIndicator(
      opacity: 1,
      progress: 1,
      spinning: true,
      size: 22,
      strokeWidth: 2.5,
    );
  }
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
    required this.comment,
    required this.comments,
    required this.timeline,
    required this.onReply,
    required this.before,
    required this.after,
    required this.compactCount,
    required this.fullCount,
  });

  final FeedComment comment;
  final FeedCommentsCubit comments;
  final FeedCubit timeline;
  final ValueChanged<FeedComment> onReply;
  final bool before, after;
  final NumberFormat compactCount;
  final NumberFormat fullCount;
  static const avatarSize = 36.0;
  static const avatarGap = 10.0;
  static const contentInset =
      PrimaryHeaderGeometry.horizontalPadding + avatarSize + avatarGap;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  bool _flying = false;
  bool _menuOpen = false;
  TapGestureRecognizer? _mentionTap;

  Future<void> _openMention() async {
    final item = widget.comment;
    final target = item.replyTo;
    final actions = widget.comments.actions;
    final id = target?.userId;
    if (target == null ||
        id == null ||
        id == actions.account.userId ||
        !_current(item) ||
        actions.commentHidden(target.id) ||
        actions.state.blocked.contains(id) ||
        ModalRoute.isCurrentOf(context) == false ||
        !actions.beginProfile()) {
      return;
    }
    try {
      await openViewedProfile(context, userId: id, waitForClose: true);
    } finally {
      actions.endProfile();
    }
  }

  @override
  void dispose() {
    _mentionTap?.dispose();
    super.dispose();
  }

  bool _current(FeedComment item) =>
      mounted &&
      widget.comment.id == item.id &&
      widget.timeline.isCurrentAccount() &&
      widget.comments.available(item);

  Future<void> _openProfile() async {
    final item = widget.comment;
    final id = item.authorId;
    final actions = widget.comments.actions;
    if (id == null ||
        id == actions.account.userId ||
        !_current(item) ||
        ModalRoute.isCurrentOf(context) == false ||
        !actions.beginProfile()) {
      return;
    }
    setState(() => _flying = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !_current(item) ||
          ModalRoute.isCurrentOf(context) == false) {
        return;
      }
      await openViewedProfile(context, userId: id, waitForClose: true);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      actions.endProfile();
      if (mounted) setState(() => _flying = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted && widget.timeline.isCurrentAccount()) {
        showAppSnackBar(
          context,
          message: context.l10n.feedActionFailed,
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _report() async {
    final item = widget.comment;
    if (_menuOpen || !_current(item)) return;
    _menuOpen = true;
    try {
      final label = context.l10n.feedReport;
      final selected = await showProfileActionSheet<bool>(
        context,
        builder: (context) => ProfileActionSheetContent(
          children: [
            ListTile(
              leading: const Icon(Icons.flag_rounded),
              title: Text(label),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (!mounted || selected != true || !_current(item)) return;
      final reason = await showFeedReportReason(
        context,
        () => _current(item),
        comment: true,
      );
      if (reason != null && _current(item)) {
        await _perform(() => widget.comments.report(item, reason));
      }
    } finally {
      _menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.comment;
    final comments = widget.comments;
    final padding = MediaQuery.paddingOf(context);
    final colors = context.colorScheme;
    final l10n = context.l10n;
    final available = comments.available(item);
    final reaction = comments.reactionFor(item);
    final date = item.createdAt;
    final author = item.authorName ?? l10n.feedUnknownAuthor;
    final actions = comments.actions;
    final canOpen = available && item.authorId != actions.account.userId;
    final canAct = available && comments.canMutate && !comments.busy(item);
    final target = item.replyTo;
    final mention =
        available &&
            target != null &&
            target.id != item.threadId &&
            !actions.commentHidden(target.id) &&
            !actions.state.blocked.contains(target.userId)
        ? target
        : null;
    final mentionOpensProfile =
        mention?.userId != null && mention!.userId != actions.account.userId;
    const avatar = _CommentRow.avatarSize;
    const gutter = PrimaryHeaderGeometry.horizontalPadding;
    const actionInset =
        (FeedActionButton.buttonHeight - FeedActionButton.iconSize) / 2;
    return Padding(
      padding: EdgeInsets.only(
        left: padding.left + gutter,
        right: padding.right + gutter,
      ),
      child: Stack(
        children: [
          if (widget.before || widget.after)
            PositionedDirectional(
              start: avatar / 2 - 1,
              width: 2,
              top: widget.before ? 0 : 24,
              bottom: widget.after ? 0 : null,
              height: widget.after ? null : 24,
              child: ColoredBox(color: colors.outline.withValues(alpha: .4)),
            ),
          Padding(
            padding: EdgeInsets.only(
              top: FeedDivider.spacing,
              bottom: available
                  ? FeedDivider.spacing - actionInset
                  : FeedDivider.spacing,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FeedAuthorAvatar(
                  authorId: available ? item.authorId : null,
                  avatarUrl: available ? item.avatarUrl : null,
                  avatarPath: available ? item.avatarPath : null,
                  avatarRevision: available ? item.avatarRevision : null,
                  timeline: widget.timeline,
                  size: avatar,
                  heroEnabled: _flying && available,
                  onOpenProfile: canOpen ? _openProfile : null,
                ),
                const SizedBox(width: _CommentRow.avatarGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (available)
                        Stack(
                          alignment: AlignmentDirectional.topStart,
                          children: [
                            if (canOpen) const SizedBox(height: 28),
                            Padding(
                              padding: EdgeInsetsDirectional.only(
                                end: canOpen ? 36 : 0,
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) => Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Flexible(
                                      child: GestureDetector(
                                        onTap: canOpen ? _openProfile : null,
                                        child: Text(
                                          author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.chatName
                                              .copyWith(
                                                fontSize: 16,
                                                color: colors.onSurface,
                                              ),
                                        ),
                                      ),
                                    ),
                                    if (date != null) ...[
                                      const SizedBox(width: 6),
                                      FeedTimestamp(
                                        timestamp: feedRelativeTime(
                                          context,
                                          date,
                                        ),
                                        maxWidth: constraints.maxWidth * .55,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (canOpen)
                              PositionedDirectional(
                                top: 0,
                                end: 0,
                                child: IconButton(
                                  tooltip: l10n.feedCommentMenu,
                                  iconSize: 20,
                                  alignment: AlignmentDirectional.topEnd,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 28,
                                  ),
                                  style: const ButtonStyle(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: canAct ? _report : null,
                                  icon: Icon(
                                    Icons.more_vert,
                                    color: colors.outline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (mention != null)
                              TextSpan(
                                text: '@${mention.username}',
                                recognizer: mentionOpensProfile
                                    ? (_mentionTap ??= TapGestureRecognizer()
                                        ..onTap = _openMention)
                                    : null,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: mentionOpensProfile
                                      ? colors.primary
                                      : null,
                                ),
                              ),
                            TextSpan(
                              text: available
                                  ? '${mention == null ? '' : ' '}${item.text!}'
                                  : l10n.feedCommentUnavailable,
                            ),
                          ],
                        ),
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: available ? colors.onSurface : colors.outline,
                        ),
                      ),
                      if (available)
                        Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                  style:
                                      FeedActionButton.style(
                                        AlignmentDirectional.centerStart,
                                      ).copyWith(
                                        foregroundColor: WidgetStatePropertyAll(
                                          colors.outline,
                                        ),
                                        textStyle: WidgetStatePropertyAll(
                                          AppTextStyles.metadata.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  onPressed: () => widget.onReply(item),
                                  child: Text(l10n.feedReplyComment),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: FeedActionButton(
                                  icon: reaction.liked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  label: reaction.liked
                                      ? l10n.feedUnlike
                                      : l10n.feedLike,
                                  count: reaction.likes,
                                  active: reaction.liked,
                                  alignment: AlignmentDirectional.centerEnd,
                                  compact: widget.compactCount,
                                  complete: widget.fullCount,
                                  onPressed: canAct
                                      ? () => unawaited(
                                          _perform(
                                            () => comments.toggleLike(item),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
