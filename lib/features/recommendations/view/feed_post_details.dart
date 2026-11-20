import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart' show SizeReporter;
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_card.dart';
import 'feed_comments_sliver.dart';

Future<void> openFeedPost(
  BuildContext context,
  FeedCubit timeline,
  String id, {
  bool fromDetail = false,
  FeedPost? initial,
}) async {
  final actions = timeline.actions;
  final router = StackRouterScope.of(
    context,
  )?.controller.root.innerRouterOf<StackRouter>(AuthGateRoute.name);
  if (actions == null ||
      !actions.active ||
      router == null ||
      router.current.name == FeedPostDetailsRoute.name &&
          router.current.argsAs<FeedPostDetailsRouteArgs>().id == id ||
      ModalRoute.isCurrentOf(context) == false) {
    return;
  }
  if (!fromDetail && !actions.beginDetail()) return;
  try {
    final preview =
        initial != null && initial.id == id && actions.canShow(initial)
        ? FeedPostDetailsPreview(initial, timeline.account)
        : null;
    await router.push<void>(FeedPostDetailsRoute(id: id, preview: preview));
  } finally {
    if (!fromDetail) actions.endDetail();
  }
}

@immutable
class FeedPostDetailsPreview {
  const FeedPostDetailsPreview(this.post, this.account);
  final FeedPost post;
  final AccountSessionSnapshot account;
}

@RoutePage()
class FeedPostDetailsPage extends StatefulWidget {
  const FeedPostDetailsPage({
    super.key,
    @PathParam('id') required this.id,
    this.preview,
  });

  final String id;
  final FeedPostDetailsPreview? preview;

  @override
  State<FeedPostDetailsPage> createState() => _FeedPostDetailsPageState();
}

class _FeedPostDetailsPageState extends State<FeedPostDetailsPage> {
  FeedCubit? _timeline;
  late final AccountSessionController? _accounts;
  FeedPostDetailsCubit? _details;
  final _publication = GlobalKey<_PublicationState>();

  Future<void> _refresh() => _details!.load(
    visibleThreads: _publication.currentState?.visibleThreads() ?? const {},
  );

  @override
  void initState() {
    super.initState();
    _accounts = context.read<AccountSessionController?>();
    final accounts = _accounts;
    final repository = context.read<IFeedRepository?>();
    final scope = context.read<FeedAccountScope?>();
    if (accounts == null ||
        accounts.userId == null ||
        repository == null ||
        scope == null ||
        !FeedPostLink.isValidId(widget.id)) {
      return;
    }
    final account = accounts.capture();
    final actions = scope.actionsFor(account);
    if (actions == null) return;
    _timeline = FeedCubit(
      tab: FeedTab.forYou,
      repository: repository,
      isCurrentAccount: () => accounts.isCurrent(account),
      account: account,
      actions: actions,
    );
    final preview = widget.preview;
    final initial =
        preview != null &&
            accounts.isCurrent(preview.account) &&
            preview.post.id == widget.id &&
            actions.canShow(preview.post)
        ? preview.post
        : null;
    final details = _details = FeedPostDetailsCubit(
      widget.id,
      actions,
      initial,
      publicationRepository: repository is IFeedPublicationRepository
          ? repository as IFeedPublicationRepository
          : null,
      networkAvailability: context
          .read<AppConnectionStatus?>()
          ?.networkAvailability,
    );
    unawaited(details.load());
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    final padding = MediaQuery.paddingOf(context);
    const toolbar = 64.0;
    const gutter = PrimaryHeaderGeometry.horizontalPadding;
    final top = padding.top + toolbar;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          accounts == null
              ? _unavailable(context)
              : ValueListenableBuilder(
                  valueListenable: accounts.generationChanges,
                  builder: (context, _, _) => _body(context, top),
                ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.scaffoldBackgroundColor.withValues(alpha: .88),
                    context.scaffoldBackgroundColor.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  padding.left + gutter,
                  padding.top,
                  padding.right + gutter,
                  0,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MediaGalleryHeader.buttonSize + 12,
                      ),
                      child: Text(
                        context.l10n.feedPublication,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: 0,
                      child: Tooltip(
                        message: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip.toLowerCase(),
                        child: MediaGalleryHeader.backButton(
                          () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unavailable(BuildContext context) => EmptyChatState(
    message: context.l10n.feedPostUnavailable,
    showImage: false,
  );

  Widget _body(BuildContext context, double top) {
    final timeline = _timeline;
    final actions = timeline?.actions;
    if (timeline == null || actions == null || !actions.active) {
      return _unavailable(context);
    }
    final details = _details!;
    return BlocBuilder<FeedActionsCubit, FeedActionsState>(
      bloc: actions,
      buildWhen: (previous, current) =>
          previous.blocked != current.blocked ||
          previous.accessVersion != current.accessVersion ||
          previous.hidden.length != current.hidden.length,
      builder: (context, _) =>
          BlocBuilder<FeedPostDetailsCubit, FeedPostDetailsState>(
            bloc: details,
            builder: (context, state) => ValueListenableBuilder(
              valueListenable: details.refreshProgress,
              builder: (context, refreshing, _) {
                Widget body;
                final post = state.post;
                if (post != null && actions.canShow(post)) {
                  body = _Publication(
                    key: _publication,
                    post: post,
                    timeline: timeline,
                    actions: actions,
                    comments: details.comments,
                    confirmed: state.confirmed,
                    failed: state.failed,
                    onRetry: _refresh,
                    refreshing: refreshing,
                    headerHeight: top,
                  );
                } else if (state.loading || state.failed) {
                  final safe = MediaQuery.paddingOf(context);
                  body = CustomScrollView(
                    physics: PullRefresh.physics,
                    slivers: [
                      SliverToBoxAdapter(child: SizedBox(height: top)),
                      const SliverPullRefreshGap(),
                      if (state.failed)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: _PublicationRetry(
                              refreshing: refreshing,
                              onPressed: _refresh,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            safe.left + PrimaryHeaderGeometry.horizontalPadding,
                            PrimaryHeaderGeometry.horizontalPadding,
                            safe.right +
                                PrimaryHeaderGeometry.horizontalPadding,
                            0,
                          ),
                          sliver: const SliverToBoxAdapter(
                            child: _PublicationPlaceholder(),
                          ),
                        ),
                    ],
                  );
                } else {
                  return _unavailable(context);
                }
                return PullRefresh(
                  indicatorTop: top,
                  onRefresh: _refresh,
                  refreshing: refreshing,
                  useSliverInset: true,
                  showExternalProgress: true,
                  reserveExternalSpace: true,
                  child: body,
                );
              },
            ),
          ),
    );
  }

  @override
  void dispose() {
    unawaited(_timeline?.close());
    unawaited(_details?.close());
    super.dispose();
  }
}

class _Publication extends StatefulWidget {
  const _Publication({
    super.key,
    required this.post,
    required this.timeline,
    required this.actions,
    required this.confirmed,
    required this.failed,
    required this.onRetry,
    required this.headerHeight,
    required this.comments,
    required this.refreshing,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final FeedActionsCubit actions;
  final bool confirmed;
  final bool failed;
  final bool refreshing;
  final FeedCommentsCubit? comments;
  final VoidCallback onRetry;
  final double headerHeight;

  @override
  State<_Publication> createState() => _PublicationState();
}

class _PublicationState extends State<_Publication> {
  final _controller = ScrollController();
  final _focus = FocusNode();
  final _composerHeight = ValueNotifier<double?>(null);
  final _commentList = GlobalKey<FeedCommentsSliverState>();
  FeedCommentsCubit? get _comments => widget.comments;
  String? _submitError;
  FeedComment? _replyTo;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
    _comments?.visibleAnchors = _visibleAnchors;
  }

  @override
  void didUpdateWidget(covariant _Publication oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comments != _comments) {
      oldWidget.comments?.visibleAnchors = null;
      _comments?.visibleAnchors = _visibleAnchors;
    }
  }

  Map<String?, String> _visibleAnchors() => mounted
      ? _commentList.currentState?.visibleAnchors() ?? const {}
      : const {};

  Rect _commentBounds() {
    final media = MediaQuery.of(context);
    final bottom =
        media.size.height -
        math.max(media.viewInsets.bottom, media.viewPadding.bottom) -
        (_composerHeight.value ?? 0);
    return Rect.fromLTRB(0, widget.headerHeight, media.size.width, bottom);
  }

  Rect? _readingViewport() =>
      ModalRoute.isCurrentOf(context) == false ||
          !_controller.hasClients ||
          _controller.position.pixels <=
              _controller.position.minScrollExtent + 1
      ? null
      : _commentBounds();

  Set<String> visibleThreads() {
    final bounds = _commentBounds();
    return _commentList.currentState?.visibleThreads(
          top: bounds.top,
          bottom: bounds.bottom,
        ) ??
        const {};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _focus.unfocus();
  }

  void _showKeyboard() {
    if (ModalRoute.isCurrentOf(context) == false) return;
    final editor = _focus.context?.findAncestorStateOfType<EditableTextState>();
    if (editor == null) {
      _focus.requestFocus();
    } else {
      editor.requestKeyboard();
    }
  }

  void _maybeLoadMore() {
    final comments = _comments;
    if (comments == null ||
        !widget.confirmed ||
        widget.refreshing ||
        !_controller.hasClients ||
        comments.state.failed) {
      return;
    }
    final position = _controller.position;
    if (position.userScrollDirection != ScrollDirection.reverse ||
        position.outOfRange ||
        position.extentAfter > 350) {
      return;
    }
    unawaited(comments.next());
  }

  Future<bool> _submit(String text) async {
    final comments = _comments;
    if (comments == null ||
        !widget.confirmed ||
        !widget.actions.canShow(widget.post)) {
      return false;
    }
    if (text.runes.length > 200) {
      setState(() => _submitError = context.l10n.feedCommentTooLong);
      return false;
    }
    final target = _replyTo;
    if (target != null && !comments.available(target)) {
      setState(() {
        _replyTo = null;
        _submitError = context.l10n.feedCommentUnavailable;
      });
      return false;
    }
    if (_submitError != null) setState(() => _submitError = null);
    try {
      final accepted = await comments.submit(text, replyTo: target);
      if (accepted && target != null && mounted && _replyTo?.id == target.id) {
        setState(() => _replyTo = null);
      }
      return accepted;
    } catch (_) {
      if (mounted && widget.actions.canShow(widget.post)) {
        setState(() => _submitError = context.l10n.feedActionFailed);
      }
      return false;
    }
  }

  void _reply(FeedComment comment) {
    if (_comments?.available(comment) != true) return;
    setState(() => _replyTo = comment);
    _showKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    final card = FeedPostCard(
      post: widget.post,
      timeline: widget.timeline,
      visible: true,
      details: true,
      onComments: _comments == null ? null : _showKeyboard,
      onOpenPost: (id) => openFeedPost(
        context,
        widget.timeline,
        id,
        fromDetail: true,
        initial: widget.post.original,
      ),
    );
    final comments = _comments;
    final media = MediaQuery.of(context);
    final composerInsets = EdgeInsets.only(
      left: media.viewPadding.left + MessageInputBar.horizontalGutter,
      right: media.viewPadding.right + MessageInputBar.horizontalGutter,
    );
    final keyboard = math.max(
      0.0,
      media.viewInsets.bottom - media.viewPadding.bottom,
    );
    return BlocListener<FeedActionsCubit, FeedActionsState>(
      bloc: widget.actions,
      listenWhen: (previous, current) => previous.blocked != current.blocked,
      listener: (_, _) {
        comments?.invalidateAccess();
        final target = _replyTo;
        if (target != null && comments?.available(target) != true) {
          setState(() => _replyTo = null);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomScrollView(
            controller: _controller,
            physics: PullRefresh.physics,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: widget.headerHeight)),
              const SliverPullRefreshGap(preserveOffscreenPosition: true),
              SliverToBoxAdapter(child: card),
              if (widget.failed)
                SliverToBoxAdapter(
                  child: _PublicationRetry(
                    refreshing: widget.refreshing,
                    onPressed: widget.onRetry,
                  ),
                ),
              if (comments != null)
                FeedCommentsSliver(
                  key: _commentList,
                  comments: comments,
                  timeline: widget.timeline,
                  onReply: _reply,
                  onRetryPublication: widget.onRetry,
                  refreshing: widget.refreshing,
                  postFailed: widget.failed,
                  viewport: _readingViewport,
                ),
              if (comments != null)
                ValueListenableBuilder(
                  valueListenable: _composerHeight,
                  builder: (_, height, _) => SliverToBoxAdapter(
                    child: SizedBox(
                      height:
                          (height ?? 70 + media.viewPadding.bottom) +
                          keyboard +
                          12,
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: SizedBox(height: media.viewPadding.bottom),
                ),
            ],
          ),
          if (comments != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboard,
              child: MediaQuery(
                data: media.copyWith(viewInsets: EdgeInsets.zero),
                child: SizeReporter(
                  onSizeChanged: (size) {
                    if (mounted) _composerHeight.value = size.height;
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ComposerReplyTransition(
                        fadeOutInPlace: true,
                        child: switch (_replyTo) {
                          final target? => Padding(
                            key: const ValueKey('feed_reply_preview'),
                            padding: composerInsets,
                            child: ChatGlassSurface(
                              borderRadius: 16,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        start: 12,
                                      ),
                                      child: Text(
                                        context.l10n.feedReplyingTo(
                                          target.authorName ??
                                              context.l10n.feedUnknownAuthor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: context.l10n.cancel.toLowerCase(),
                                    icon: const Icon(Icons.close),
                                    onPressed: () =>
                                        setState(() => _replyTo = null),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          null => null,
                        },
                      ),
                      if (_submitError case final error?)
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: composerInsets,
                            child: Text(
                              error,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: context.colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      MessageInputBar(
                        onSend: (_) {},
                        onSubmit: _submit,
                        onDraftAccepted: _focus.unfocus,
                        focusNode: _focus,
                        showAttachmentButton: false,
                        hintText: context.l10n.feedWriteComment,
                        sendTooltip: context.l10n.feedSendComment,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _comments?.visibleAnchors = null;
    _controller.dispose();
    _focus.dispose();
    _composerHeight.dispose();
    super.dispose();
  }
}

class _PublicationRetry extends StatelessWidget {
  const _PublicationRetry({required this.refreshing, required this.onPressed});

  final bool refreshing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Center(
      heightFactor: 1,
      child: ExcludeSemantics(
        excluding: refreshing,
        child: IgnorePointer(
          ignoring: refreshing,
          child: AnimatedOpacity(
            opacity: refreshing ? 0 : 1,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: RetryPillButton(
              label: context.l10n.feedRetry,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    ),
  );
}

class _PublicationPlaceholder extends StatelessWidget {
  const _PublicationPlaceholder();

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurface.withValues(alpha: .10);
    Widget shape(double width, double height, double radius) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              shape(40, 40, 16),
              const SizedBox(width: 10),
              shape(110, 16, 6),
            ],
          ),
          const SizedBox(height: 20),
          shape(double.infinity, 16, 6),
          const SizedBox(height: 8),
          shape(156, 16, 6),
        ],
      ),
    );
  }
}
