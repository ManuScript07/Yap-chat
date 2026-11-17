import 'package:yap_chat/repositories/feed/feed.dart';

class FeedRows {
  const FeedRows.empty() : posts = const [], _indexes = const {};

  FeedRows(Iterable<FeedPost> posts, Map<String, int> indexes)
    : posts = List.unmodifiable(posts),
      _indexes = Map.unmodifiable(indexes);

  final List<FeedPost> posts;
  final Map<String, int> _indexes;

  int? indexOf(String id) => _indexes[id];
}

typedef FeedFooter = ({
  bool loading,
  bool loaded,
  bool empty,
  bool canContinue,
  Object? failure,
});

class FeedState {
  const FeedState({
    this.rows = const FeedRows.empty(),
    this.expandedIds = const {},
    this.loading = false,
    this.appending = false,
    this.loaded = false,
    this.canContinue = false,
    this.failure,
  });

  final FeedRows rows;
  final Set<String> expandedIds;
  final bool loading;
  final bool appending;
  final bool loaded;
  final bool canContinue;
  final Object? failure;

  FeedFooter get footer => (
    loading: appending,
    loaded: loaded,
    empty: rows.posts.isEmpty,
    canContinue: canContinue,
    failure: failure,
  );
}
