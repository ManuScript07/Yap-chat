import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';

import 'feed_post_card.dart';

Future<void> openFeedPost(
  BuildContext context,
  FeedCubit timeline,
  String id, {
  bool fromDetail = false,
}) async {
  final actions = timeline.actions;
  if (actions == null ||
      !actions.active ||
      ModalRoute.isCurrentOf(context) == false) {
    return;
  }
  if (!fromDetail && !actions.beginDetail()) return;
  try {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => _FeedPostDetails(timeline: timeline, id: id),
      ),
    );
  } finally {
    if (!fromDetail) actions.endDetail();
  }
}

class _FeedPostDetails extends StatefulWidget {
  const _FeedPostDetails({required this.timeline, required this.id});

  final FeedCubit timeline;
  final String id;

  @override
  State<_FeedPostDetails> createState() => _FeedPostDetailsState();
}

class _FeedPostDetailsState extends State<_FeedPostDetails> {
  late Future<FeedPost?> _post = _load();
  FeedPost? _visiblePost;

  Future<FeedPost?> _load() => widget.timeline.actions!.repository.getPost(
    widget.id,
    widget.timeline.account,
  );

  @override
  Widget build(BuildContext context) {
    final accounts = context.read<AccountSessionController?>();
    if (accounts == null) return _buildPage(context);
    return ValueListenableBuilder(
      valueListenable: accounts.generationChanges,
      builder: (context, _, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.feedPublication)),
    body: !widget.timeline.isCurrentAccount()
        ? Center(child: Text(context.l10n.feedPostUnavailable))
        : BlocConsumer<FeedActionsCubit, FeedActionsState>(
            bloc: widget.timeline.actions,
            listenWhen: (_, state) {
              final post = _visiblePost;
              final author = state.revokedAuthor;
              return author != null &&
                  (post == null ||
                      post.authorId == author ||
                      post.original?.authorId == author);
            },
            listener: (context, _) => setState(() {
              _visiblePost = null;
              _post = _load();
            }),
            builder: (context, state) => FutureBuilder(
              future: _post,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() => _post = _load()),
                      child: Text(context.l10n.feedRetry),
                    ),
                  );
                }
                final post = snapshot.data;
                if (post == null || !widget.timeline.actions!.canShow(post)) {
                  return Center(child: Text(context.l10n.feedPostUnavailable));
                }
                _visiblePost = post;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FeedPostCard(
                      post: post,
                      timeline: widget.timeline,
                      visible: true,
                      details: true,
                      onOpenPost: (id) => openFeedPost(
                        context,
                        widget.timeline,
                        id,
                        fromDetail: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
  );
}
