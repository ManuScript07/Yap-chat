import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/bloc/chat_bloc.dart';
import 'package:yap_chat/features/chat/bloc/chat_event.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/mock_chat_repository.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  test(
    'draft resolves through the peer observer without consuming list pages',
    () async {
      final repository = _PeerChatsRepository();
      final bloc = ChatBloc(
        chatRepository: MockChatRepository(),
        chatsRepository: repository,
        initialChat: Chat.directDraft(
          peerId: 'peer-1',
          peerUsername: 'peer',
          peerDisplayName: 'Peer',
        ),
      )..add(const ChatStarted('direct-draft:peer-1'));
      addTearDown(() async {
        await bloc.close();
        await repository.peers.close();
      });
      await _waitUntil(() => repository.watchedPeer == 'peer-1');
      repository.peers.add(_chat('wrong', 'other'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.resolvedChat, isNull);
      repository.peers.add(_chat('outside-first-page', 'peer-1'));
      await _waitUntil(() => bloc.state.chatId == 'outside-first-page');
      expect(bloc.state.hasMoreMessages, true);
      expect(repository.listCalls, 0);
    },
  );
  test(
    'promotes an open draft when its chat reaches the shared cache',
    () async {
      final chatsRepository = _DraftChatsRepository();
      final bloc = ChatBloc(
        chatRepository: MockChatRepository(),
        chatsRepository: chatsRepository,
        initialChat: Chat.directDraft(
          peerId: 'peer-1',
          peerUsername: 'peer',
          peerDisplayName: 'Peer',
        ),
      )..add(const ChatStarted('direct-draft:peer-1'));
      addTearDown(() async {
        await bloc.close();
        await chatsRepository.dispose();
      });

      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.resolvedChat, isNull);

      final resolved = _chat('conversation-1', 'peer-1');
      chatsRepository.emit([resolved]);
      await _waitUntil(() => bloc.state.resolvedChat?.id == resolved.id);

      expect(bloc.state.chatId, resolved.id);
      expect(bloc.state.hasMoreMessages, isTrue);
    },
  );
}

class _DraftChatsRepository extends MockChatsRepository {
  final StreamController<List<Chat>> _chats =
      StreamController<List<Chat>>.broadcast();

  @override
  Stream<List<Chat>> watchChats() => _chats.stream;

  void emit(List<Chat> chats) => _chats.add(chats);

  Future<void> dispose() => _chats.close();
}

class _PeerChatsRepository extends MockChatsRepository
    implements IChatsPeerRepository {
  final peers = StreamController<Chat?>.broadcast();
  String? watchedPeer;
  int listCalls = 0;
  @override
  Stream<Chat?> watchChatByPeerId(String id) {
    watchedPeer = id;
    return peers.stream;
  }

  @override
  Stream<List<Chat>> watchChats() {
    listCalls++;
    throw StateError('A draft must not observe list pages');
  }
}

Chat _chat(String id, String peerId) => Chat(
  id: id,
  peerId: peerId,
  peerUsername: 'peer',
  userName: 'Peer',
  lastMessage: '',
  lastMessageTime: DateTime.utc(2026, 9, 8),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the draft to resolve');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
