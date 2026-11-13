import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  test(
    'selection stops at 50 but allows deselection and replacement',
    () async {
      final bloc = ChatsBloc(chatsRepository: _Repository());
      addTearDown(bloc.close);
      final chats = [for (var i = 0; i < 51; i++) _chat('$i', false)];
      final ready = bloc.stream.firstWhere((state) => state.chats.length == 51);
      bloc.add(ChatsSubscriptionUpdated(chats));
      await ready;
      final full = bloc.stream.firstWhere(
        (state) => state.selectedChatIds.length == 50,
      );
      for (var i = 0; i < 50; i++) {
        bloc.add(ChatSelectionToggled('$i'));
      }
      await full;
      bloc.add(const ChatSelectionToggled('50'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.selectedChatIds, hasLength(50));
      expect(bloc.state.selectedChatIds, isNot(contains('50')));
      final removed = bloc.stream.firstWhere(
        (state) => state.selectedChatIds.length == 49,
      );
      bloc.add(const ChatSelectionToggled('0'));
      await removed;
      final replaced = bloc.stream.firstWhere(
        (state) => state.selectedChatIds.contains('50'),
      );
      bloc.add(const ChatSelectionToggled('50'));
      await replaced;
      expect(bloc.state.selectedChatIds, hasLength(50));
    },
  );

  test(
    'read completion does not erase a newer realtime unread count',
    () async {
      final repository = _Repository()..gate = Completer<void>();
      final bloc = ChatsBloc(chatsRepository: repository);
      addTearDown(bloc.close);
      await _select(bloc, [_chat('a', false)]);
      final busy = bloc.stream.firstWhere(
        (state) => state.isBulkActionInProgress,
      );
      bloc.add(const ChatsMarkedAsRead());
      await busy;
      final updated = bloc.stream.firstWhere(
        (state) => state.chats.single.unreadCount == 2,
      );
      bloc.add(
        ChatsSubscriptionUpdated([
          _chat(
            'a',
            false,
          ).copyWith(lastMessageId: 'new-message', unreadCount: 2),
        ]),
      );
      await updated;
      final done = bloc.stream.firstWhere((state) => state.feedback != null);
      repository.gate!.complete();
      expect((await done).chats.single.unreadCount, 2);
    },
  );

  for (final muted in [
    [false, false],
    [true, true],
    [false, true],
    [true, false],
  ]) {
    test('normalizes selection $muted and sends only different IDs', () async {
      final repository = _Repository();
      final bloc = ChatsBloc(chatsRepository: repository);
      addTearDown(bloc.close);
      await _select(bloc, [_chat('a', muted[0]), _chat('b', muted[1])]);
      final target = !muted.any((value) => value);
      final done = bloc.stream.firstWhere((state) => state.feedback != null);
      bloc.add(const ChatsMuteToggled());
      final result = await done;
      expect(repository.calls, hasLength(1));
      expect(repository.calls.single.isMuted, target);
      expect(repository.calls.single.ids, {
        if (muted[0] != target) 'a',
        if (muted[1] != target) 'b',
      });
      expect(result.chats.map((chat) => chat.isMuted), everyElement(target));
      expect(result.feedbackIsMuted, target);
      expect(result.selectedChatIds, isEmpty);
    });
  }

  test(
    'realtime completion does not invert the accepted state again',
    () async {
      final repository = _Repository()..gate = Completer<void>();
      final bloc = ChatsBloc(chatsRepository: repository);
      addTearDown(bloc.close);
      await _select(bloc, [_chat('a', false), _chat('b', true)]);
      final busy = bloc.stream.firstWhere(
        (state) => state.isBulkActionInProgress,
      );
      bloc.add(const ChatsMuteToggled());
      await busy;
      bloc.add(const ChatsMuteToggled());
      bloc.add(const ChatSelectionCleared());
      bloc.add(const ChatSelectionToggled('b'));
      final refreshed = bloc.stream.firstWhere(
        (state) => state.chats.every((chat) => !chat.isMuted),
      );
      bloc.add(
        ChatsSubscriptionUpdated([_chat('a', false), _chat('b', false)]),
      );
      await refreshed;
      expect(bloc.state.selectedChatIds, {'a', 'b'});
      final done = bloc.stream.firstWhere((state) => state.feedback != null);
      repository.gate!.complete();
      final result = await done;
      expect(repository.calls, hasLength(1));
      expect(result.chats.every((chat) => !chat.isMuted), isTrue);
      expect(result.feedbackIsMuted, false);
    },
  );

  test('failure retains selection/state and a later retry succeeds', () async {
    final repository = _Repository()..fail = true;
    final bloc = ChatsBloc(chatsRepository: repository);
    addTearDown(bloc.close);
    await _select(bloc, [_chat('a', false), _chat('b', true)]);
    final failed = bloc.stream.firstWhere((state) => state.feedback != null);
    bloc.add(const ChatsMuteToggled());
    expect((await failed).feedback, ChatsBulkActionFeedback.failure);
    expect(bloc.state.selectedChatIds, {'a', 'b'});
    expect(bloc.state.chats.map((chat) => chat.isMuted), [false, true]);
    repository.fail = false;
    final done = bloc.stream.firstWhere(
      (state) => state.feedback == ChatsBulkActionFeedback.success,
    );
    bloc.add(const ChatsMuteToggled());
    await done;
    expect(repository.calls, hasLength(2));
    expect(bloc.state.chats.every((chat) => !chat.isMuted), isTrue);
  });

  test(
    'empty selection does not write and aggregate follows any selected row',
    () async {
      final repository = _Repository();
      final bloc = ChatsBloc(chatsRepository: repository);
      addTearDown(bloc.close);
      bloc.add(const ChatsMuteToggled());
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, isEmpty);
      await _select(bloc, [_chat('a', false), _chat('b', false)]);
      expect(bloc.state.hasMutedSelection, false);
      final updated = bloc.stream.firstWhere(
        (state) => state.hasMutedSelection,
      );
      bloc.add(ChatsSubscriptionUpdated([_chat('a', false), _chat('b', true)]));
      await updated;
      final reordered = bloc.stream.firstWhere(
        (state) => state.chats.first.id == 'b',
      );
      bloc.add(ChatsSubscriptionUpdated([_chat('b', true), _chat('a', false)]));
      expect((await reordered).hasMutedSelection, true);
    },
  );
}

Future<void> _select(ChatsBloc bloc, List<Chat> chats) async {
  final ready = bloc.stream.firstWhere(
    (state) => state.selectedChatIds.length == chats.length,
  );
  bloc.add(ChatsSubscriptionUpdated(chats));
  for (final chat in chats) {
    bloc.add(ChatSelectionToggled(chat.id));
  }
  await ready;
}

Chat _chat(String id, bool isMuted) => Chat(
  id: id,
  userName: id,
  lastMessage: 'preview',
  lastMessageTime: DateTime(2026),
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
  isMuted: isMuted,
);

class _Repository extends MockChatsRepository {
  final calls = <({Set<String> ids, bool isMuted})>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> markAsRead(Set<String> ids) async {
    await gate?.future;
  }

  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {
    calls.add((ids: Set.of(ids), isMuted: isMuted));
    if (fail) throw StateError('offline');
    await gate?.future;
  }
}
