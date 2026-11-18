import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_controls.dart';

class FeedCommentsSliver extends StatelessWidget {
  const FeedCommentsSliver({
    super.key,
    required this.comments,
    required this.timeline,
    required this.onReply,
  });

  final FeedCommentsCubit comments;
  final FeedCubit timeline;
  final ValueChanged<FeedComment> onReply;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<FeedCommentsCubit, FeedCommentsState>(
    bloc: comments,
    builder: (context, state) {
      final l10n = context.l10n;
      final padding = MediaQuery.paddingOf(context);
      String label(FeedCommentSort sort) => switch (sort) {
        FeedCommentSort.popular => l10n.feedCommentsPopular,
        FeedCommentSort.newFirst => l10n.feedCommentsNew,
        FeedCommentSort.old => l10n.feedCommentsOld,
      };
      final rows = <(Key, Widget Function())>[];
      for (final root in state.rows) {
        final replies = comments.replies(root);
        final expanded = state.expandedRoot == root.id;
        final hasBranch = root.replyCount > 0 || replies.isNotEmpty;
        void add(
          FeedComment comment, {
          required bool before,
          required bool after,
        }) {
          rows.add((
            ValueKey(comment.id),
            () => _CommentRow(
              comment: comment,
              comments: comments,
              timeline: timeline,
              onReply: onReply,
              before: before,
              after: after,
            ),
          ));
        }

        add(root, before: false, after: hasBranch);
        for (final reply in replies) {
          add(reply, before: true, after: reply != replies.last);
        }
        if (hasBranch) {
          final status = comments.threadStatus(root.id);
          rows.add((
            ValueKey(('thread', root.id)),
            () => Padding(
              padding: EdgeInsetsDirectional.only(
                start:
                    (Directionality.of(context) == TextDirection.ltr
                        ? padding.left
                        : padding.right) +
                    60,
                bottom: 4,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (expanded && status.loading) const _CommentProgress(),
                  if (expanded &&
                      !status.loading &&
                      (status.more || status.failed))
                    TextButton(
                      onPressed: () => comments.nextReplies(root.id),
                      child: Text(
                        status.failed ? l10n.feedRetry : l10n.feedLoadMore,
                      ),
                    ),
                  if (expanded ||
                      root.replyCount > replies.length ||
                      replies.isEmpty)
                    TextButton(
                      onPressed: () => comments.expand(root.id),
                      child: Text(
                        expanded ? l10n.feedHideReplies : l10n.feedShowReplies,
                      ),
                    ),
                ],
              ),
            ),
          ));
        }
        rows.add((
          ValueKey(('divider', root.id)),
          () => const Divider(height: 1),
        ));
      }
      final positions = {for (final (i, row) in rows.indexed) row.$1: i};
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                left: padding.left + 14,
                right: padding.right + 14,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: PopupMenuButton<FeedCommentSort>(
                  tooltip: l10n.feedCommentsSort,
                  initialValue: state.sort,
                  onSelected: comments.selectSort,
                  itemBuilder: (_) => [
                    for (final sort in FeedCommentSort.values)
                      PopupMenuItem(value: sort, child: Text(label(sort))),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label(state.sort),
                          style: AppTextStyles.chatName.copyWith(fontSize: 15),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: rows.length,
            findChildIndexCallback: (key) => positions[key],
            itemBuilder: (_, index) =>
                KeyedSubtree(key: rows[index].$1, child: rows[index].$2()),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: state.loading
                    ? const _CommentProgress()
                    : state.failed || state.hasMore
                    ? TextButton(
                        onPressed: comments.next,
                        child: Text(
                          state.failed ? l10n.feedRetry : l10n.feedLoadMore,
                        ),
                      )
                    : state.rows.isEmpty
                    ? EmptyChatState(message: l10n.feedNoComments)
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _CommentProgress extends StatelessWidget {
  const _CommentProgress();

  @override
  Widget build(BuildContext context) => const PullRefreshIndicator(
    opacity: 1,
    progress: 1,
    spinning: true,
    size: 22,
    strokeWidth: 2.5,
  );
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
    required this.comment,
    required this.comments,
    required this.timeline,
    required this.onReply,
    required this.before,
    required this.after,
  });

  final FeedComment comment;
  final FeedCommentsCubit comments;
  final FeedCubit timeline;
  final ValueChanged<FeedComment> onReply;
  final bool before, after;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  bool _flying = false;
  bool _menuOpen = false;

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
    final canOpen =
        available && item.authorId != comments.actions.account.userId;
    final canAct = available && !comments.busy(item);
    final target = item.replyTo;
    const avatar = 36.0;
    return Padding(
      padding: EdgeInsets.only(
        left: padding.left + 14,
        right: padding.right + 14,
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
            padding: const EdgeInsets.only(top: 12, bottom: 7),
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (available)
                        Row(
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: canOpen ? _openProfile : null,
                                child: Text(
                                  author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.chatName.copyWith(
                                    fontSize: 16,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            if (date != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                feedRelativeTime(context, date),
                                maxLines: 1,
                                style: AppTextStyles.metadata.copyWith(
                                  color: colors.outline,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (available &&
                                target != null &&
                                target.id != item.threadId &&
                                !comments.actions.commentHidden(target.id))
                              TextSpan(
                                text: '@${target.username} ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary,
                                ),
                              ),
                            TextSpan(
                              text: available
                                  ? item.text!
                                  : l10n.feedCommentUnavailable,
                            ),
                          ],
                        ),
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: available ? colors.onSurface : colors.outline,
                        ),
                      ),
                      if (available)
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            IconButton(
                              tooltip: l10n.feedReplyComment,
                              iconSize: 20,
                              onPressed: () => widget.onReply(item),
                              icon: Icon(
                                Icons.chat_bubble_outline,
                                color: colors.outline,
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: reaction.liked
                                    ? colors.primary
                                    : colors.outline,
                              ),
                              onPressed: canAct
                                  ? () => unawaited(
                                      _perform(() => comments.toggleLike(item)),
                                    )
                                  : null,
                              icon: Icon(
                                reaction.liked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 20,
                              ),
                              label: Text(
                                NumberFormat.compact(
                                  locale: Localizations.localeOf(
                                    context,
                                  ).toString(),
                                ).format(reaction.likes).toLowerCase(),
                                semanticsLabel: reaction.liked
                                    ? l10n.feedUnlike
                                    : l10n.feedLike,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (canOpen)
                  IconButton(
                    tooltip: l10n.feedCommentMenu,
                    iconSize: 20,
                    onPressed: canAct ? _report : null,
                    icon: Icon(Icons.more_vert, color: colors.outline),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
