import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/repositories/presence/presence.dart';

void main() {
  testWidgets('replaces and removes one stable route scope', (tester) async {
    final repository = _RecordingPresenceRepository();
    final ids = ValueNotifier<Set<String>>({'first'});

    await tester.pumpWidget(
      RepositoryProvider<IPresenceRepository>.value(
        value: repository,
        child: ValueListenableBuilder<Set<String>>(
          valueListenable: ids,
          builder: (context, value, _) => PresenceWatchScope(
            scopeName: 'test',
            userIds: value,
            child: const MaterialApp(home: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(repository.scopes.values.single, {'first'});
    final scopeId = repository.scopes.keys.single;

    ids.value = {'second', 'third'};
    await tester.pump();
    expect(repository.scopes[scopeId], {'second', 'third'});

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repository.removedScopes, [scopeId]);
  });
}

class _RecordingPresenceRepository
    implements IPresenceRepository, IPresenceWatchRepository {
  final Map<String, Set<String>> scopes = {};
  final List<String> removedScopes = [];

  @override
  Future<void> connect(String userId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> removeWatchScope(String scopeId) async {
    removedScopes.add(scopeId);
    scopes.remove(scopeId);
  }

  @override
  Future<void> setWatchScope(String scopeId, Iterable<String> userIds) async {
    scopes[scopeId] = Set.unmodifiable(userIds);
  }

  @override
  Stream<Set<String>> watchOnlineUserIds() => const Stream.empty();
}
