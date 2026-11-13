import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/friends/bloc/friend_search_cubit.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/friends.dart';

class _CountingFriendsRepository extends MockFriendsRepository {
  final List<String> searchCalls = [];
  Completer<List<FriendCandidate>>? blockedSearch;

  @override
  Future<List<FriendCandidate>> searchUsers(String query) {
    searchCalls.add(query);
    final blocker = blockedSearch;
    if (blocker != null && searchCalls.length == 1) return blocker.future;
    return Future.value(const []);
  }
}

void main() {
  test('rapid typing is coalesced into one RPC for the latest query', () async {
    final repository = _CountingFriendsRepository();
    final cubit = FriendSearchCubit(repository: repository);
    addTearDown(cubit.close);

    cubit.queryChanged('мак');
    cubit.queryChanged('макс');
    cubit.queryChanged('макси');

    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(repository.searchCalls, ['макси']);
  });

  test('only the latest query is queued while an RPC is in flight', () async {
    final repository = _CountingFriendsRepository()
      ..blockedSearch = Completer<List<FriendCandidate>>();
    final cubit = FriendSearchCubit(repository: repository);
    addTearDown(cubit.close);

    cubit.queryChanged('мак');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(repository.searchCalls, ['мак']);

    cubit.queryChanged('макс');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cubit.queryChanged('макси');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    repository.blockedSearch!.complete(const []);
    await Future<void>.delayed(Duration.zero);

    expect(repository.searchCalls, ['мак', 'макси']);
  });
}
