import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
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
            builder: (context, state) {
              final post = state.post;
              if (post != null && actions.canShow(post)) {
                return _Publication(
                  post: post,
                  timeline: timeline,
                  actions: actions,
                  confirmed: state.confirmed,
                  refreshing: state.loading,
                  failed: state.failed,
                  onRetry: details.load,
                  headerHeight: top,
                );
              }
              if (state.loading && post == null) {
                final safe = MediaQuery.paddingOf(context);
                const gutter = PrimaryHeaderGeometry.horizontalPadding;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    safe.left + gutter,
                    top + gutter,
                    safe.right + gutter,
                    0,
                  ),
                  child: const Align(
                    alignment: Alignment.topCenter,
                    child: _PublicationPlaceholder(),
                  ),
                );
              }
              if (state.failed && post == null) {
                return Center(
                  child: RetryPillButton(
                    onPressed: details.load,
                    label: context.l10n.feedRetry,
                  ),
                );
              }
              return _unavailable(context);
            },
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
    required this.post,
    required this.timeline,
    required this.actions,
    required this.confirmed,
    required this.refreshing,
    required this.failed,
    required this.onRetry,
    required this.headerHeight,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final FeedActionsCubit actions;
  final bool confirmed;
  final bool refreshing;
  final bool failed;
  final VoidCallback onRetry;
  final double headerHeight;

  @override
  State<_Publication> createState() => _PublicationState();
}

class _PublicationState extends State<_Publication> {
  final _controller = ScrollController();
  final _focus = FocusNode();
  FeedCommentsCubit? _comments;
  String? _submitError;
  FeedComment? _replyTo;
  double? _composerHeight;

  @override
  void initState() {
    super.initState();
    final repository = widget.timeline.repository;
    if (repository is IFeedPublicationRepository) {
      _comments = FeedCommentsCubit(
        repository as IFeedPublicationRepository,
        widget.actions,
        widget.post,
      );
      _comments!.updatePost(widget.post, confirmed: widget.confirmed);
      _controller.addListener(_maybeLoadMore);
    }
  }

  @override
  void didUpdateWidget(covariant _Publication oldWidget) {
    super.didUpdateWidget(oldWidget);
    _comments?.updatePost(widget.post, confirmed: widget.confirmed);
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
        !_controller.hasClients ||
        comments.state.failed ||
        _controller.position.extentAfter > 350) {
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
    final composerHeight = _composerHeight ?? (70 + media.viewPadding.bottom);
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: widget.headerHeight)),
              SliverToBoxAdapter(child: card),
              if (widget.failed)
                SliverToBoxAdapter(
                  child: Center(
                    child: RetryPillButton(
                      onPressed: widget.onRetry,
                      label: context.l10n.feedRetry,
                    ),
                  ),
                ),
              if (comments != null && widget.confirmed)
                FeedCommentsSliver(
                  comments: comments,
                  timeline: widget.timeline,
                  onReply: _reply,
                )
              else if (widget.refreshing)
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: PullRefreshIndicator(
                        opacity: 1,
                        progress: 1,
                        spinning: true,
                        size: 22,
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: comments != null
                      ? composerHeight + keyboard + 12
                      : media.viewPadding.bottom,
                ),
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
                    if (mounted && _composerHeight != size.height) {
                      setState(() => _composerHeight = size.height);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_replyTo case final target?)
                        Padding(
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
    _controller.dispose();
    _focus.dispose();
    unawaited(_comments?.close());
    super.dispose();
  }
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
