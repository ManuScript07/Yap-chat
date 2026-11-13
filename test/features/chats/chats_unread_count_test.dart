import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  test(
    'global badge survives partial list, search, mute preview and count errors',
    () async {
      final repository = _Repository();
      final bloc = ChatsBloc(chatsRepository: repository);
      addTearDown(() async {
        await bloc.close();
        await repository.rows.close();
        await repository.counts.close();
      });
      bloc.add(const ChatsLoadStarted());
      await _until(
        () => repository.rows.hasListener && repository.counts.hasListener,
      );
      repository.rows.add([_chat('a', 1), _chat('b', 2)]);
      repository.counts.add(1005);
      await _until(
        () =>
            bloc.state.status == ChatsStatus.success &&
            bloc.state.unreadCount == 1005,
      );
      bloc.add(const ChatsSearchChanged('a'));
      await _until(() => bloc.state.filteredChats.length == 1);
      expect(bloc.state.unreadCount, 1005);
      repository.rows.add([_chat('a', 0)]);
      await _until(() => bloc.state.chats.length == 1);
      expect(bloc.state.unreadCount, 1005);
      repository.counts.addError(StateError('offline'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.status, ChatsStatus.success);
      expect(bloc.state.unreadCount, 1005);
      repository.counts.add(0);
      await _until(() => bloc.state.unreadCount == 0);
      repository.counts.add(null);
      await _until(() => bloc.state.unreadTotal == null);
      expect(repository.listSubscriptions, 1);
      expect(repository.countSubscriptions, 1);
    },
  );

  test(
    'legacy badge still sums unmuted chats only; confirmed zero is not unknown',
    () {
      final rows = [_chat('a', 3), _chat('b', 7).copyWith(isMuted: true)];
      expect(ChatsState(chats: rows).unreadCount, 3);
      expect(ChatsState(chats: rows, unreadTotal: 0).unreadCount, 0);
    },
  );

  test('closing list bloc cancels both local observers', () async {
    final repository = _Repository();
    final bloc = ChatsBloc(chatsRepository: repository);
    bloc.add(const ChatsLoadStarted());
    await _until(
      () => repository.rows.hasListener && repository.counts.hasListener,
    );
    await bloc.close();
    expect(repository.rows.hasListener, false);
    expect(repository.counts.hasListener, false);
    await repository.rows.close();
    await repository.counts.close();
  });
}

class _Repository extends MockChatsRepository
    implements IChatsUnreadRepository {
  final rows = StreamController<List<Chat>>.broadcast();
  final counts = StreamController<int?>.broadcast();
  int listSubscriptions = 0, countSubscriptions = 0;
  @override
  Stream<List<Chat>> watchChats() {
    listSubscriptions++;
    return rows.stream;
  }

  @override
  Stream<int?> watchUnreadCount() {
    countSubscriptions++;
    return counts.stream;
  }
}

Chat _chat(String id, int unread) => Chat(
  id: id,
  userName: id,
  lastMessage: 'text',
  lastMessageTime: DateTime.utc(2026),
  unreadCount: unread,
  isOnline: false,
  isLastMessageFromMe: false,
);

Future<void> _until(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Expected chat state was not emitted');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
