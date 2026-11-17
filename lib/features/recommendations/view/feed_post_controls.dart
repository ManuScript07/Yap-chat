import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_text.dart';

class FeedPostAuthorAvatar extends StatelessWidget {
  const FeedPostAuthorAvatar({
    super.key,
    required this.post,
    required this.timeline,
    required this.visible,
    required this.size,
    required this.heroEnabled,
    this.onOpenProfile,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool visible;
  final double size;
  final bool heroEnabled;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final path = post.avatarPath;
    final repository = timeline.repository;
    // The feed stops being current during a push. Keep both the selected
    // Hero and its image available to the Navigator for the whole transition.
    final showAvatar = visible || heroEnabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpenProfile ?? () {},
      excludeFromSemantics: onOpenProfile == null,
      child: HeroMode(
        enabled: heroEnabled,
        child: ProfileAvatarHero(
          profileId: heroEnabled ? post.authorId : null,
          avatarUrl: post.avatarUrl,
          avatarStoragePath: path,
          child: UserAvatar(
            size: size,
            avatarUrl: showAvatar && path == null ? post.avatarUrl : null,
            avatarRevision: post.avatarRevision,
            preferAvatarLoader: path != null,
            avatarLoader:
                showAvatar && path != null && repository is FeedRepository
                ? () => repository.loadAvatar(path, timeline.account)
                : null,
          ),
        ),
      ),
    );
  }
}

class FeedPostHeader extends StatelessWidget {
  const FeedPostHeader({
    super.key,
    required this.post,
    required this.timeline,
    required this.details,
    required this.avatar,
    this.onOpenProfile,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final bool details;
  final Widget avatar;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = timeline.actions;
    final own = post.authorId == timeline.account.userId;
    final name = post.authorName ?? l10n.feedUnknownAuthor;
    final metadata = _metadataStyle(context);
    final time = _postTime(context, post.createdAt);
    final timestamp = post.edited ? '$time · ${l10n.feedEdited}' : time;
    final authorName = GestureDetector(
      onTap: onOpenProfile ?? () {},
      excludeFromSemantics: onOpenProfile == null,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.chatName.copyWith(
          fontSize: 16,
          color: context.colorScheme.onSurface,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.repostedBy case final username?)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('↻ @$username', style: context.textTheme.bodySmall),
          ),
        Row(
          crossAxisAlignment: details
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      crossAxisAlignment: details
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(child: authorName),
                        const SizedBox(width: 6),
                        if (details)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * .55,
                            ),
                            child: FittedBox(
                              alignment: AlignmentDirectional.centerStart,
                              fit: BoxFit.scaleDown,
                              child: Text(
                                timestamp,
                                maxLines: 1,
                                style: metadata,
                              ),
                            ),
                          )
                        else
                          _FeedTimestamp(
                            timestamp: timestamp,
                            style: metadata.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxWidth: constraints.maxWidth * .55,
                          ),
                      ],
                    ),
                  ),
                  if (post.coordinates != null || post.nearby)
                    FeedPostLocation(
                      post: post,
                      actions: actions,
                      inFeed: !details,
                    ),
                ],
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
                  return Padding(
                    padding: EdgeInsetsDirectional.only(start: details ? 0 : 4),
                    child: Tooltip(
                      message: follow.following
                          ? l10n.feedUnfollow
                          : l10n.feedFollow,
                      child: PrimaryIconButton(
                        width: 44,
                        height: 36,
                        iconSize: 20,
                        icon: follow.following
                            ? Icons.how_to_reg_rounded
                            : Icons.person_add_rounded,
                        muted: follow.following,
                        busy: busy,
                        onTap: () =>
                            _changeFollow(context, actions, follow.following),
                      ),
                    ),
                  );
                },
              ),
            IconButton(
              tooltip: l10n.feedPostOptions,
              alignment: details ? null : AlignmentDirectional.centerEnd,
              padding: details ? null : EdgeInsets.zero,
              constraints: details
                  ? null
                  : const BoxConstraints.tightFor(width: 36, height: 36),
              style: details
                  ? null
                  : const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showOptions(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _changeFollow(
    BuildContext context,
    FeedActionsCubit actions,
    bool following,
  ) async {
    if (following) {
      final l10n = context.l10n;
      final confirmed = await showConfirmationDialog(
        context,
        title: l10n.feedUnfollow,
        content: l10n.feedConfirmUnfollow,
        confirmLabel: l10n.feedUnfollow,
        cancelLabel: l10n.cancel.toLowerCase(),
      );
      if (confirmed != true || !context.mounted) return;
    }
    if (actions.followFor(post)?.following != following) return;
    await _perform(context, () => actions.toggleFollow(post));
  }

  Future<void> _showOptions(BuildContext context) async {
    final l10n = context.l10n;
    final actions = timeline.actions;
    final blocks = context.read<IBlocklistRepository?>();
    final own = post.authorId == timeline.account.userId;
    final selected = await _options(context, [
      (Icons.link_rounded, l10n.feedCopyLink, 'copy'),
      if (actions != null && !own)
        (Icons.flag_rounded, l10n.feedReport, 'report'),
      if (actions != null &&
          !own &&
          !details &&
          timeline.tab == FeedTab.forYou &&
          post.delivery?.expiresAt.isAfter(DateTime.now()) == true)
        (Icons.visibility_off_rounded, l10n.feedLessSimilar, 'less'),
      if (blocks != null && !own)
        (Icons.block_rounded, l10n.feedBlock, 'block'),
    ]);
    if (!context.mounted ||
        !timeline.isCurrentAccount() ||
        actions?.canShow(post) == false) {
      return;
    }
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
        if (reason == null ||
            !context.mounted ||
            !timeline.isCurrentAccount()) {
          return;
        }
        final confirmed = await showConfirmationDialog(
          context,
          title: l10n.feedReport,
          content: l10n.feedConfirmReport,
          confirmLabel: l10n.feedReport,
          cancelLabel: l10n.cancel.toLowerCase(),
        );
        if (confirmed == true && context.mounted) {
          await _perform(context, () => actions!.report(post, reason));
        }
      case 'less':
        await _perform(context, () => actions!.act(post, lessSimilar: true));
      case 'block':
        final confirmed = await showConfirmationDialog(
          context,
          title: l10n.viewedProfileBlockTitle.toLowerCase(),
          content: l10n.viewedProfileBlockContent(
            post.authorName ?? l10n.feedUnknownAuthor,
          ),
          confirmLabel: l10n.feedBlock,
          cancelLabel: l10n.cancel.toLowerCase(),
        );
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

class _FeedTimestamp extends StatelessWidget {
  const _FeedTimestamp({
    required this.timestamp,
    required this.style,
    required this.maxWidth,
  });

  final String timestamp;
  final TextStyle style;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final painter = TextPainter(
      text: TextSpan(
        text: timestamp,
        style: MediaQuery.boldTextOf(context)
            ? effectiveStyle.merge(const TextStyle(fontWeight: FontWeight.bold))
            : effectiveStyle,
      ),
      textDirection: Directionality.of(context),
      locale: Localizations.localeOf(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    final fontSize = style.fontSize!;
    final fit = width > maxWidth
        ? TextScaler.linear(
            scaler.scale(fontSize) / fontSize * maxWidth / width,
          )
        : scaler;
    // Use a real text baseline even when the full date needs to scale down.
    return Text(
      timestamp,
      maxLines: 1,
      softWrap: false,
      textScaler: fit,
      style: style,
    );
  }
}

class FeedPostLocation extends StatelessWidget {
  const FeedPostLocation({
    super.key,
    required this.post,
    required this.actions,
    required this.inFeed,
  });

  final FeedPost post;
  final FeedActionsCubit? actions;
  final bool inFeed;

  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    if (actions == null || post.coordinates == null) {
      return _location(context, post.coordinates);
    }
    return BlocSelector<FeedActionsCubit, FeedActionsState, FeedCoordinates?>(
      bloc: actions,
      selector: (_) => actions.coordinatesFor(post),
      builder: _location,
    );
  }

  Widget _location(BuildContext context, FeedCoordinates? point) {
    final colorScheme = context.colorScheme;
    final metadata = _metadataStyle(context);
    if (point == null) {
      if (!post.nearby) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(top: inFeed ? 2 : 0),
        child: Text(context.l10n.feedNearYou, style: metadata),
      );
    }
    final locationLabel = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.place_rounded),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            context.l10n.feedPostLocation,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: metadata.copyWith(
              color: colorScheme.primary,
              fontWeight: inFeed ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: inFeed ? .25 : null,
            ),
          ),
        ),
      ],
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: Size(0, inFeed ? 0 : 28),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          iconSize: 19,
          alignment: inFeed ? AlignmentDirectional.centerStart : null,
          overlayColor: inFeed ? Colors.transparent : null,
        ),
        // Compensate for the pin glyph's own inset without moving the hit box.
        child: inFeed
            ? Transform.translate(
                offset: Offset(
                  Directionality.of(context) == TextDirection.ltr ? -3 : 3,
                  0,
                ),
                transformHitTests: false,
                child: locationLabel,
              )
            : locationLabel,
        onPressed: () => _perform(context, () async {
          final actions = this.actions;
          final current = actions == null
              ? point
              : actions.coordinatesFor(post);
          if (current == null) return;
          final coordinates = '${current.latitude},${current.longitude}';
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
      color: context.scaffoldBackgroundColor,
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
    required this.bottomSpacing,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final ValueChanged<String> onOpenPost;
  final bool details;
  final double bottomSpacing;
  static final _thousandsSuffix = RegExp(r'[\s\u00a0]*тыс\.?$');

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
    final locale = Localizations.localeOf(context).toString();
    final compact = NumberFormat.compact(locale: locale);
    final complete = NumberFormat.decimalPattern(locale);
    final colorScheme = context.colorScheme;
    const shareWidth = 44.0;
    const buttonHeight = 44.0;
    final iconSize = details ? 19.0 : 22.0;
    final counterSize = details ? 12.0 : 14.0;
    final counterGap = details ? 3.0 : 5.0;

    Widget item(
      IconData icon,
      String label,
      int? count,
      VoidCallback? onPressed, {
      required bool stacked,
      bool active = false,
      bool readOnly = false,
    }) {
      final color = active ? colorScheme.primary : colorScheme.outline;
      final alignment = details
          ? Alignment.center
          : count == null
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart;
      final glyph = Icon(icon, size: iconSize, color: color);
      final counter = count == null
          ? null
          : Text(
              compact
                  .format(count)
                  .toLowerCase()
                  .replaceFirst(_thousandsSuffix, 'к'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.metadata.copyWith(
                fontSize: counterSize,
                fontWeight: details ? null : FontWeight.w600,
                color: color,
              ),
            );
      final content = counter == null
          ? glyph
          : stacked
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: details
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [glyph, counter],
            )
          : Row(
              mainAxisSize: details ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: details
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                glyph,
                SizedBox(width: counterGap),
                Flexible(child: counter),
              ],
            );
      return Semantics(
        label: label,
        value: count == null ? null : complete.format(count),
        child: Tooltip(
          excludeFromSemantics: true,
          message: label,
          child: readOnly
              ? Align(
                  alignment: alignment,
                  child: ExcludeSemantics(child: content),
                )
              : TextButton(
                  style: TextButton.styleFrom(
                    alignment: alignment,
                    minimumSize: const Size(0, buttonHeight),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    overlayColor: Colors.transparent,
                  ),
                  onPressed: onPressed,
                  child: ExcludeSemantics(child: content),
                ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledCounterSize = MediaQuery.textScalerOf(
          context,
        ).scale(counterSize);
        final stacked =
            (constraints.maxWidth - shareWidth) / 4 <
            iconSize + counterGap + scaledCounterSize * (details ? 3 : 2);
        final row = Row(
          children: [
            Expanded(
              child: item(
                reaction.liked ? Icons.favorite : Icons.favorite_border,
                l10n.feedLike,
                reaction.likes,
                actions != null && !busy && post.delivery != null
                    ? () => _perform(context, () => actions.act(post))
                    : null,
                stacked: stacked,
                active: reaction.liked,
              ),
            ),
            Expanded(
              child: item(
                Icons.chat_bubble_outline,
                l10n.feedComments,
                post.commentCount,
                actions != null && !details ? () => onOpenPost(post.id) : null,
                stacked: stacked,
              ),
            ),
            Expanded(
              child: item(
                Icons.repeat,
                l10n.feedRepost,
                repostCount ?? post.repostCount,
                actions != null &&
                        !busy &&
                        !post.reposted &&
                        repostCount == null
                    ? () async {
                        final confirmed = await showConfirmationDialog(
                          context,
                          title: l10n.feedRepost,
                          content: l10n.feedConfirmRepost,
                          confirmLabel: l10n.feedRepost,
                          cancelLabel: l10n.cancel.toLowerCase(),
                        );
                        if (confirmed == true && context.mounted) {
                          await _perform(context, () => actions.repost(post));
                        }
                      }
                    : null,
                stacked: stacked,
              ),
            ),
            Expanded(
              child: item(
                Icons.visibility_outlined,
                l10n.feedViews,
                post.viewCount,
                null,
                stacked: stacked,
                readOnly: true,
              ),
            ),
            SizedBox(
              width: shareWidth,
              child: item(
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
                stacked: false,
              ),
            ),
          ],
        );
        if (bottomSpacing == 0) return row;
        final counterHeight =
            scaledCounterSize * (AppTextStyles.metadata.height ?? 1);
        final contentHeight = stacked
            ? iconSize + counterHeight
            : math.max(iconSize, counterHeight);
        final tapTargetInset = math.max(
          0.0,
          (buttonHeight - contentHeight) / 2,
        );
        return Padding(
          padding: EdgeInsets.only(
            bottom: math.max(0.0, bottomSpacing - tapTargetInset),
          ),
          child: row,
        );
      },
    );
  }
}

Uri _postLink(FeedPost post) => FeedPostLink.create(post.id);

TextStyle _metadataStyle(BuildContext context) => AppTextStyles.metadata
    .copyWith(color: context.colorScheme.onSurfaceVariant, fontSize: 12);

String _postTime(BuildContext context, DateTime createdAt) {
  final elapsed = DateTime.now().difference(createdAt);
  final l10n = context.l10n;
  if (elapsed.isNegative || elapsed.inDays >= 7) {
    return MaterialLocalizations.of(
      context,
    ).formatCompactDate(createdAt.toLocal());
  }
  if (elapsed.inMinutes < 1) return l10n.timeJustNow.toLowerCase();
  if (elapsed.inHours < 1) return l10n.feedMinutesAgo(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.feedHoursAgo(elapsed.inHours);
  return l10n.feedDaysAgo(elapsed.inDays);
}

Future<T?> _options<T>(
  BuildContext context,
  List<(IconData, String, T)> options,
) => showProfileActionSheet<T>(
  context,
  builder: (context) => ProfileActionSheetContent(
    children: [
      for (final (icon, label, value) in options)
        ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () => Navigator.pop(context, value),
        ),
    ],
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
