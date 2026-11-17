import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_text.dart';

class FeedPostHeader extends StatelessWidget {
  const FeedPostHeader({
    super.key,
    required this.post,
    required this.timeline,
    required this.visible,
    required this.details,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool visible;
  final bool details;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = timeline.actions;
    final own = post.authorId == timeline.account.userId;
    final repository = timeline.repository;
    final path = post.avatarPath;
    final name = post.authorName ?? l10n.feedUnknownAuthor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.repostedBy case final username?)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('↻ @$username', style: context.textTheme.bodySmall),
          ),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: own
                    ? null
                    : () => openViewedProfile(context, userId: post.authorId),
                child: Row(
                  children: [
                    UserAvatar(
                      size: 40,
                      avatarUrl: visible && path == null
                          ? post.avatarUrl
                          : null,
                      avatarRevision: post.avatarRevision,
                      preferAvatarLoader: path != null,
                      avatarLoader:
                          visible &&
                              path != null &&
                              repository is FeedRepository
                          ? () => repository.loadAvatar(path, timeline.account)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleMedium,
                          ),
                          Text(
                            '${_postTime(context, post.createdAt)}${post.edited ? ' · ${l10n.feedEdited}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (actions != null && !own)
              BlocSelector<
                FeedActionsCubit,
                FeedActionsState,
                (FeedFollowState?, bool)
              >(
                bloc: actions,
                selector: (state) => (
                  actions.followFor(post),
                  state.busy.contains('author:${post.authorId}'),
                ),
                builder: (context, selected) {
                  final (follow, busy) = selected;
                  if (follow == null ||
                      !follow.canFollow && !follow.following) {
                    return const SizedBox.shrink();
                  }
                  return Tooltip(
                    message: follow.following
                        ? l10n.feedUnfollow
                        : l10n.feedFollow,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: busy
                          ? null
                          : () => _perform(
                              context,
                              () => actions.toggleFollow(post),
                            ),
                      child: Icon(
                        follow.following
                            ? Icons.check
                            : Icons.person_add_alt_1_outlined,
                        size: 18,
                      ),
                    ),
                  );
                },
              ),
            IconButton(
              tooltip: l10n.feedPostOptions,
              icon: const Icon(Icons.more_horiz),
              onPressed: () => _showOptions(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    final l10n = context.l10n;
    final actions = timeline.actions;
    final blocks = context.read<IBlocklistRepository?>();
    final own = post.authorId == timeline.account.userId;
    final selected = await _options(context, [
      (Icons.link, l10n.feedCopyLink, 'copy'),
      if (actions != null && !own)
        (Icons.flag_outlined, l10n.feedReport, 'report'),
      if (actions != null &&
          !own &&
          !details &&
          timeline.tab == FeedTab.forYou &&
          post.delivery?.expiresAt.isAfter(DateTime.now()) == true)
        (Icons.visibility_off_outlined, l10n.feedLessSimilar, 'less'),
      if (blocks != null && !own) (Icons.block, l10n.feedBlock, 'block'),
    ]);
    if (!context.mounted || !timeline.isCurrentAccount()) return;
    switch (selected) {
      case 'copy':
        await _perform(
          context,
          () => Clipboard.setData(
            ClipboardData(text: _postLink(post).toString()),
          ),
        );
      case 'report':
        final reason = await _options(context, [
          (Icons.flag_outlined, l10n.feedSpam, FeedReportReason.spam),
          (Icons.flag_outlined, l10n.feedScam, FeedReportReason.scam),
          (
            Icons.flag_outlined,
            l10n.feedPornography,
            FeedReportReason.pornography,
          ),
          (Icons.flag_outlined, l10n.feedOther, FeedReportReason.other),
        ]);
        if (reason != null && context.mounted) {
          await _perform(context, () => actions!.report(post, reason));
        }
      case 'less':
        await _perform(context, () => actions!.act(post, lessSimilar: true));
      case 'block':
        final confirmed = await _options(context, [
          (Icons.block, l10n.feedConfirmBlock, true),
        ]);
        if (confirmed == true &&
            context.mounted &&
            timeline.isCurrentAccount()) {
          await _perform(
            context,
            () => blocks!.blockUser(
              BlockedUser(
                id: post.authorId,
                username: post.username ?? '',
                displayName: post.authorName ?? '',
                blockedAt: DateTime.now(),
                avatarUrl: post.avatarUrl,
                avatarStoragePath: post.avatarPath,
              ),
            ),
          );
        }
    }
  }
}

class FeedPostLocation extends StatelessWidget {
  const FeedPostLocation({super.key, required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final point = post.coordinates;
    if (point == null) return Text(context.l10n.feedNearYou);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        icon: const Icon(Icons.place_outlined, size: 16),
        label: Text(context.l10n.feedPostLocation),
        onPressed: () => _perform(context, () async {
          final coordinates = '${point.latitude},${point.longitude}';
          final uri = Uri.parse('geo:$coordinates?q=$coordinates');
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            throw StateError('Could not open map');
          }
        }),
      ),
    );
  }
}

class FeedQuotePreview extends StatelessWidget {
  const FeedQuotePreview({
    super.key,
    required this.post,
    required this.timeline,
    required this.onOpenPost,
  });

  final FeedPost? post;
  final FeedCubit timeline;
  final ValueChanged<String> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final original = post;
    final actions = timeline.actions;
    if (original != null && actions != null) {
      return BlocSelector<FeedActionsCubit, FeedActionsState, bool>(
        bloc: actions,
        selector: (_) => actions.canShow(original),
        builder: (context, visible) =>
            _preview(context, visible ? original : null),
      );
    }
    return _preview(context, original);
  }

  Widget _preview(BuildContext context, FeedPost? original) {
    return Card.outlined(
      margin: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: original == null ? null : () => onOpenPost(original.id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: original == null
              ? Text(context.l10n.feedPostUnavailable)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      original.authorName ?? context.l10n.feedUnknownAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text.rich(
                      feedPostText(
                        original,
                        context.textTheme.bodyMedium ?? const TextStyle(),
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class FeedPostFooter extends StatelessWidget {
  const FeedPostFooter({
    super.key,
    required this.post,
    required this.timeline,
    required this.onOpenPost,
    required this.details,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final ValueChanged<String> onOpenPost;
  final bool details;

  @override
  Widget build(BuildContext context) {
    final actions = timeline.actions;
    if (actions == null) return _buttons(context, post.reaction, false, null);
    return BlocSelector<
      FeedActionsCubit,
      FeedActionsState,
      (FeedReaction, bool, int?)
    >(
      bloc: actions,
      selector: (state) => (
        actions.reactionFor(post),
        state.busy.contains(post.id),
        state.reposts[post.id],
      ),
      builder: (context, value) =>
          _buttons(context, value.$1, value.$2, value.$3),
    );
  }

  Widget _buttons(
    BuildContext context,
    FeedReaction reaction,
    bool busy,
    int? repostCount,
  ) {
    final l10n = context.l10n;
    final actions = timeline.actions;
    final format = NumberFormat.compact(
      locale: Localizations.localeOf(context).toString(),
    );
    Widget button(
      IconData icon,
      String label,
      int? count,
      VoidCallback? onPressed,
    ) => TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      onPressed: onPressed,
      child: Tooltip(
        message: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19),
            if (count != null) Text(' ${format.format(count).toLowerCase()}'),
          ],
        ),
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        button(
          reaction.liked ? Icons.favorite : Icons.favorite_border,
          l10n.feedLike,
          reaction.likes,
          actions != null && !busy && post.delivery != null
              ? () => _perform(context, () => actions.act(post))
              : null,
        ),
        button(
          Icons.chat_bubble_outline,
          l10n.feedComments,
          post.commentCount,
          actions != null && !details ? () => onOpenPost(post.id) : null,
        ),
        button(
          Icons.repeat,
          l10n.feedRepost,
          repostCount ?? post.repostCount,
          actions != null && !busy && !post.reposted && repostCount == null
              ? () async {
                  final confirmed = await _options(context, [
                    (Icons.repeat, l10n.feedRepost, true),
                  ]);
                  if (confirmed == true && context.mounted) {
                    await _perform(context, () => actions.repost(post));
                  }
                }
              : null,
        ),
        Tooltip(
          message: l10n.feedViews,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_outlined, size: 19),
                Text(' ${format.format(post.viewCount).toLowerCase()}'),
              ],
            ),
          ),
        ),
        button(
          Icons.share_outlined,
          l10n.feedShare,
          null,
          () => _perform(context, () async {
            final box = context.findRenderObject() as RenderBox?;
            await SharePlus.instance.share(
              ShareParams(
                uri: _postLink(post),
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              ),
            );
          }),
        ),
      ],
    );
  }
}

Uri _postLink(FeedPost post) =>
    Uri.https(ProfileShareLink.host, '/post/${post.id}');

String _postTime(BuildContext context, DateTime createdAt) {
  final elapsed = DateTime.now().difference(createdAt);
  final l10n = context.l10n;
  if (elapsed.inMinutes < 1) return l10n.timeJustNow.toLowerCase();
  if (elapsed.inHours < 1) return l10n.feedMinutesAgo(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.feedHoursAgo(elapsed.inHours);
  if (elapsed.inDays < 7) return l10n.feedDaysAgo(elapsed.inDays);
  return MaterialLocalizations.of(context).formatShortDate(createdAt.toLocal());
}

Future<T?> _options<T>(
  BuildContext context,
  List<(IconData, String, T)> options,
) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (icon, label, value) in options)
          ListTile(
            leading: Icon(icon),
            title: Text(label, style: context.textTheme.titleMedium),
            onTap: () => Navigator.pop(context, value),
          ),
      ],
    ),
  ),
);

Future<void> _perform(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.feedActionFailed,
        type: SnackBarType.error,
      );
    }
  }
}
