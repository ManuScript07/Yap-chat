import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_post_card.dart';

Future<void> openFeedPost(
  BuildContext context,
  FeedCubit timeline,
  String id, {
  bool fromDetail = false,
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
    await router.push<void>(FeedPostDetailsRoute(id: id));
  } finally {
    if (!fromDetail) actions.endDetail();
  }
}

@RoutePage()
class FeedPostDetailsPage extends StatefulWidget {
  const FeedPostDetailsPage({super.key, @PathParam('id') required this.id});

  final String id;

  @override
  State<FeedPostDetailsPage> createState() => _FeedPostDetailsPageState();
}

class _FeedPostDetailsPageState extends State<FeedPostDetailsPage> {
  FeedCubit? _timeline;
  late final AccountSessionController? _accounts;
  Future<FeedPost?>? _request;
  Future<FeedPost?>? _inFlight;

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
    _request = _load();
  }

  Future<FeedPost?> _load() =>
      _inFlight ??= _readPost().whenComplete(() => _inFlight = null);

  Future<FeedPost?> _readPost() async {
    final actions = _timeline!.actions!;
    final requestedAt = actions.projectionVersion;
    final post = await actions.repository.getPost(widget.id, actions.account);
    if (!mounted || !actions.active || post == null) return null;
    actions.recordProjection(post, requestedAt);
    return post;
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.scaffoldBackgroundColor,
        foregroundColor: context.colorScheme.onSurface,
        scrolledUnderElevation: 0,
        title: Text(context.l10n.feedPublication),
      ),
      body: accounts == null
          ? _unavailable(context)
          : ValueListenableBuilder(
              valueListenable: accounts.generationChanges,
              builder: (context, _, _) => _body(context),
            ),
    );
  }

  Widget _unavailable(BuildContext context) =>
      Center(child: Text(context.l10n.feedPostUnavailable));

  Widget _body(BuildContext context) {
    final timeline = _timeline;
    final actions = timeline?.actions;
    if (timeline == null || actions == null || !actions.active) {
      return _unavailable(context);
    }
    return BlocBuilder<FeedActionsCubit, FeedActionsState>(
      bloc: actions,
      buildWhen: (previous, current) =>
          previous.blocked != current.blocked ||
          previous.accessVersion != current.accessVersion ||
          previous.hidden.length != current.hidden.length,
      builder: (context, _) => FutureBuilder(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _request = _load()),
                child: Text(context.l10n.feedRetry),
              ),
            );
          }
          final post = snapshot.data;
          if (post == null || !actions.canShow(post)) {
            return _unavailable(context);
          }
          return _Publication(post: post, timeline: timeline, actions: actions);
        },
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_timeline?.close());
    super.dispose();
  }
}

class _Publication extends StatefulWidget {
  const _Publication({
    required this.post,
    required this.timeline,
    required this.actions,
  });

  final FeedPost post;
  final FeedCubit timeline;
  final FeedActionsCubit actions;

  @override
  State<_Publication> createState() => _PublicationState();
}

class _PublicationState extends State<_Publication> {
  final _controller = ScrollController();
  FeedCommentsCubit? _comments;
  String? _submitError;

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
      unawaited(_comments!.next());
      _controller.addListener(_maybeLoadMore);
    }
  }

  void _maybeLoadMore() {
    final comments = _comments;
    if (comments == null ||
        comments.state.failed ||
        _controller.position.extentAfter > 350) {
      return;
    }
    unawaited(comments.next());
  }

  Future<bool> _submit(String text) async {
    final comments = _comments;
    if (comments == null || !widget.actions.canShow(widget.post)) return false;
    if (text.runes.length > 200) {
      setState(() => _submitError = context.l10n.feedCommentTooLong);
      return false;
    }
    if (_submitError != null) setState(() => _submitError = null);
    try {
      return await comments.submit(text);
    } catch (_) {
      if (mounted && widget.actions.canShow(widget.post)) {
        setState(() => _submitError = context.l10n.feedActionFailed);
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = FeedPostCard(
      post: widget.post,
      timeline: widget.timeline,
      visible: true,
      details: true,
      onOpenPost: (id) =>
          openFeedPost(context, widget.timeline, id, fromDetail: true),
    );
    final comments = _comments;
    if (comments == null) return ListView(children: [card]);
    return BlocListener<FeedActionsCubit, FeedActionsState>(
      bloc: widget.actions,
      listenWhen: (previous, current) => previous.blocked != current.blocked,
      listener: (_, _) => comments.invalidateAccess(),
      child: Column(
        children: [
          Expanded(
            child: BlocBuilder<FeedCommentsCubit, FeedCommentsState>(
              bloc: comments,
              builder: (context, state) {
                final blocked = widget.actions.state.blocked;
                final rows = state.rows;
                return ListView.builder(
                  controller: _controller,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: rows.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) return card;
                    if (index > rows.length) return _status(context, state);
                    final comment = rows[index - 1];
                    if (blocked.contains(comment.authorId)) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      key: ValueKey(comment.id),
                      title: comment.authorName == null
                          ? null
                          : Text(comment.authorName!),
                      subtitle: Text(
                        comment.text ?? context.l10n.feedCommentUnavailable,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_submitError case final error?)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
            showAttachmentButton: false,
            hintText: context.l10n.feedWriteComment,
            sendTooltip: context.l10n.feedSendComment,
          ),
        ],
      ),
    );
  }

  Widget _status(BuildContext context, FeedCommentsState state) {
    if (state.loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (state.failed || state.hasMore) {
      return Center(
        child: TextButton(
          onPressed: _comments!.next,
          child: Text(
            state.failed ? context.l10n.feedRetry : context.l10n.feedLoadMore,
          ),
        ),
      );
    }
    return state.rows.isEmpty
        ? Center(child: Text(context.l10n.feedNoComments))
        : const SizedBox.shrink();
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_comments?.close());
    super.dispose();
  }
}
