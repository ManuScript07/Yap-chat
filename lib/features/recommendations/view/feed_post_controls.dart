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
  Widget build(BuildContext context) => FeedAuthorAvatar(
    authorId: post.authorId,
    avatarUrl: post.avatarUrl,
    avatarPath: post.avatarPath,
    avatarRevision: post.avatarRevision,
    timeline: timeline,
    visible: visible,
    size: size,
    heroEnabled: heroEnabled,
    onOpenProfile: onOpenProfile,
  );
}

class FeedAuthorAvatar extends StatelessWidget {
  const FeedAuthorAvatar({
    super.key,
    required this.authorId,
    this.avatarUrl,
    this.avatarPath,
    this.avatarRevision,
    required this.timeline,
    this.visible = true,
    required this.heroEnabled,
    required this.size,
    this.onOpenProfile,
  });

  final String? authorId, avatarUrl, avatarPath, avatarRevision;
  final FeedCubit timeline;
  final bool visible, heroEnabled;
  final double size;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final path = avatarPath;
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
          profileId: heroEnabled ? authorId : null,
          avatarUrl: avatarUrl,
          avatarStoragePath: path,
          child: UserAvatar(
            size: size,
            avatarUrl: showAvatar && path == null ? avatarUrl : null,
            avatarRevision: path ?? avatarUrl ?? avatarRevision,
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
    final time = feedRelativeTime(context, post.createdAt);
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (details)
                    authorName
                  else
                    LayoutBuilder(
                      builder: (context, constraints) => Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(child: authorName),
                          const SizedBox(width: 6),
                          FeedTimestamp(
                            timestamp: timestamp,
                            maxWidth: constraints.maxWidth * .55,
                          ),
                        ],
                      ),
                    ),
                  if (post.coordinates != null || post.nearby)
                    FeedPostLocation(post: post, actions: actions),
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
                    padding: const EdgeInsetsDirectional.only(start: 4),
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
              alignment: AlignmentDirectional.centerEnd,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              style: const ButtonStyle(
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
        final reason = await showFeedReportReason(
          context,
          timeline.isCurrentAccount,
        );
        if (reason != null && context.mounted) {
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

class FeedTimestamp extends StatelessWidget {
  const FeedTimestamp({
    super.key,
    required this.timestamp,
    required this.maxWidth,
  });

  final String timestamp;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final style = _metadataStyle(context).copyWith(fontWeight: FontWeight.w600);
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
  });

  final FeedPost post;
  final FeedActionsCubit? actions;

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
        padding: const EdgeInsets.only(top: 2),
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
              fontWeight: FontWeight.w700,
              letterSpacing: .25,
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
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          iconSize: 19,
          alignment: AlignmentDirectional.centerStart,
          overlayColor: Colors.transparent,
        ),
        // Compensate for the pin glyph's own inset without moving the hit box.
        child: Transform.translate(
          offset: Offset(
            Directionality.of(context) == TextDirection.ltr ? -3 : 3,
            0,
          ),
          transformHitTests: false,
          child: locationLabel,
        ),
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
    this.onComments,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final ValueChanged<String> onOpenPost;
  final bool details;
  final double bottomSpacing;
  final VoidCallback? onComments;

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
    const shareWidth = FeedActionButton.buttonHeight;
    const buttonHeight = FeedActionButton.buttonHeight;
    const iconSize = FeedActionButton.iconSize;
    const counterSize = FeedActionButton.counterSize;
    const counterGap = FeedActionButton.counterGap;

    Widget item(
      IconData icon,
      String label,
      int? count,
      VoidCallback? onPressed, {
      required bool stacked,
      bool active = false,
      bool readOnly = false,
    }) {
      return FeedActionButton(
        icon: icon,
        label: label,
        count: count,
        onPressed: onPressed,
        compact: compact,
        complete: complete,
        stacked: stacked,
        active: active,
        readOnly: readOnly,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledCounterSize = MediaQuery.textScalerOf(
          context,
        ).scale(counterSize);
        final stacked =
            (constraints.maxWidth - shareWidth) / 4 <
            iconSize + counterGap + scaledCounterSize * 2;
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
                details
                    ? onComments
                    : actions != null
                    ? () => onOpenPost(post.id)
                    : null,
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

class FeedDivider extends StatelessWidget {
  const FeedDivider({super.key});

  static const spacing = 14.0;

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    color: context.colorScheme.onSurface.withValues(alpha: .12),
  );
}

class FeedActionButton extends StatelessWidget {
  const FeedActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.onPressed,
    required this.compact,
    required this.complete,
    this.alignment,
    this.stacked = false,
    this.active = false,
    this.readOnly = false,
  });

  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback? onPressed;
  final NumberFormat compact;
  final NumberFormat complete;
  final AlignmentGeometry? alignment;
  final bool stacked;
  final bool active;
  final bool readOnly;

  static const buttonHeight = 44.0;
  static const iconSize = 22.0;
  static const counterSize = 14.0;
  static const counterGap = 5.0;
  static final _thousandsSuffix = RegExp(r'[\s\u00a0]*тыс\.?$');

  static ButtonStyle style(AlignmentGeometry alignment) => TextButton.styleFrom(
    alignment: alignment,
    minimumSize: const Size(0, buttonHeight),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    overlayColor: Colors.transparent,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final count = this.count;
    final color = active ? colorScheme.primary : colorScheme.outline;
    final align =
        alignment ??
        (count == null
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart);
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
              fontWeight: FontWeight.w600,
              color: color,
            ),
          );
    final content = counter == null
        ? glyph
        : stacked
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [glyph, counter],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
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
                alignment: align,
                child: ExcludeSemantics(child: content),
              )
            : TextButton(
                style: style(align),
                onPressed: onPressed,
                child: ExcludeSemantics(child: content),
              ),
      ),
    );
  }
}

Uri _postLink(FeedPost post) => FeedPostLink.create(post.id);

TextStyle _metadataStyle(BuildContext context) => AppTextStyles.metadata
    .copyWith(color: context.colorScheme.onSurfaceVariant, fontSize: 12);

String feedRelativeTime(BuildContext context, DateTime createdAt) {
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

Future<FeedReportReason?> showFeedReportReason(
  BuildContext context,
  bool Function() isCurrent, {
  bool comment = false,
}) async {
  final l10n = context.l10n;
  final reason = await _options(context, [
    (Icons.flag_outlined, l10n.feedSpam, FeedReportReason.spam),
    (Icons.flag_outlined, l10n.feedScam, FeedReportReason.scam),
    (Icons.flag_outlined, l10n.feedPornography, FeedReportReason.pornography),
    (Icons.flag_outlined, l10n.feedOther, FeedReportReason.other),
  ]);
  if (reason == null || !context.mounted || !isCurrent()) return null;
  final confirmed = await showConfirmationDialog(
    context,
    title: l10n.feedReport,
    content: comment ? l10n.feedConfirmCommentReport : l10n.feedConfirmReport,
    confirmLabel: l10n.feedReport,
    cancelLabel: l10n.cancel.toLowerCase(),
  );
  return confirmed == true && isCurrent() ? reason : null;
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
