import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  for (final kind in _kinds) {
    test(
      '$kind first-send limit refusal preserves reply and timeline; retries',
      () async {
        final h = _Harness();
        await h.start();
        var atLimit = true;
        h.chats.create = (_) async {
          if (atLimit) throw const ChatLimitReachedException();
          return _createdChat;
        };
        final original = h.bloc.state;

        // Repeated refusals must produce separate UI signals even though the
        // payload, reply, timeline and status have not otherwise changed.
        for (var attempt = 1; attempt <= 2; attempt++) {
          expect(await h.bloc.submit(_outgoing(kind)), isFalse);
          expect(h.bloc.state.chatLimitRefusalCount, attempt);
          expect(h.bloc.state.status, original.status);
          expect(h.bloc.state.replyToMessage, same(h.reply));
          expect(h.bloc.state.chatId, original.chatId);
          expect(h.bloc.state.resolvedChat, isNull);
          expect(h.bloc.state.hasMoreMessages, original.hasMoreMessages);
          expect(h.bloc.state.initialMessageIds, original.initialMessageIds);
          expect(h.bloc.state.messages, original.messages);
          expect(
            h.bloc.state.audioSendFailureCount,
            kind == 'audio' ? attempt : 0,
          );
          expect(h.messages.calls, isEmpty);
          expect(h.messages.enqueued, isEmpty);
          expect(h.messages.streamRequests, isEmpty);
          expect(h.chats.creationPeers, List.filled(attempt, _peer));
          expect(
            h.chats.peerListeners,
            1,
            reason: 'refusal restores the observer',
          );
        }
        await _flush();
        expect(
          h.states.map((state) => state.chatLimitRefusalCount).toSet(),
          containsAll([0, 1, 2]),
        );
        expect(
          h.states.any((state) => state.status == ChatStatus.failure),
          isFalse,
        );

        atLimit = false;
        expect(await h.bloc.submit(_outgoing(kind)), isTrue);
        expect(h.chats.creationPeers, [_peer, _peer, _peer]);
        expect(h.messages.calls, hasLength(1));
        _expectCall(
          h.messages.calls.single,
          _outgoing(kind),
          replyId: h.reply.id,
        );
        expect(h.messages.enqueued, h.messages.calls);
        expect(h.messages.streamRequests, [_createdChat.id]);
        expect(h.bloc.state.resolvedChat, _createdChat);
        expect(h.bloc.state.replyToMessage, isNull);
        expect(h.bloc.state.messages, original.messages);
        expect(h.bloc.state.chatLimitRefusalCount, 2);
      },
    );

    test(
      '$kind legacy add sends through creation and consumes the reply',
      () async {
        final h = _Harness();
        await h.start();
        h.bloc.add(_outgoing(kind));
        await _until(() => h.messages.enqueued.length == 1);
        await _until(() => h.bloc.state.replyToMessage == null);
        expect(h.chats.creationPeers, [_peer]);
        _expectCall(
          h.messages.calls.single,
          _outgoing(kind),
          replyId: h.reply.id,
        );
        expect(h.bloc.state.chatLimitRefusalCount, 0);
      },
    );

    test('$kind existing chat enqueues without any creation attempt', () async {
      final h = _Harness(draft: false);
      h.chats.create = (_) =>
          throw StateError('must not create an existing chat');
      await h.start();
      expect(await h.bloc.submit(_outgoing(kind)), isTrue);
      expect(h.chats.creationPeers, isEmpty);
      expect(h.chats.watchedPeers, isEmpty);
      expect(h.messages.streamRequests, [_createdChat.id]);
      _expectCall(
        h.messages.calls.single,
        _outgoing(kind),
        replyId: h.reply.id,
      );
      expect(h.bloc.state.replyToMessage, isNull);
    });

    test('$kind duplicate payloads share one pending local enqueue', () async {
      final h = _Harness();
      await h.start();
      final creation = h.holdCreation();
      final enqueue = h.enqueueGate();
      h.messages.enqueue = (_) => enqueue.future;
      final first = h.bloc.submit(_outgoing(kind));
      final duplicate = h.bloc.submit(_outgoing(kind));
      final receipts = <bool>[];
      unawaited(first.then((value) => receipts.add(value)));
      unawaited(duplicate.then((value) => receipts.add(value)));
      await _until(() => h.chats.creationPeers.isNotEmpty);
      expect(h.chats.creationPeers, [_peer]);
      expect(h.messages.calls, isEmpty);
      expect(receipts, isEmpty);

      creation.complete(_createdChat);
      await _until(() => h.messages.calls.length == 1);
      final duringEnqueue = h.bloc.submit(_outgoing(kind));
      await _flush();
      expect(receipts, isEmpty, reason: 'creation alone is not acceptance');
      expect(h.messages.calls, hasLength(1));
      expect(h.messages.enqueued, isEmpty);
      expect(h.bloc.state.replyToMessage, h.reply);
      enqueue.complete();
      expect(await Future.wait([first, duplicate, duringEnqueue]), [
        true,
        true,
        true,
      ]);
      expect(h.messages.enqueued, hasLength(1));
      expect(h.bloc.state.replyToMessage, isNull);

      // Dedupe lasts only for the pending operation, not for all future sends.
      expect(await h.bloc.submit(_outgoing(kind)), isTrue);
      expect(h.messages.enqueued, hasLength(2));
      expect(h.messages.calls.last.replyId, isNull);
      expect(h.chats.creationPeers, [_peer]);
    });

    for (final failure in ['creation', 'network', 'local enqueue']) {
      test(
        '$kind $failure error is not a typed limit refusal and retains reply',
        () async {
          final h = _Harness();
          await h.start();
          final original = h.bloc.state;
          if (failure == 'local enqueue') {
            h.messages.enqueue = (_) async {
              throw const FileSystemException('outbox is full');
            };
          } else {
            h.chats.create = (_) async {
              if (failure == 'network') throw const SocketException('offline');
              // A textual resemblance must not trigger the typed refusal signal.
              throw StateError('chat limit reached during creation');
            };
          }

          expect(await h.bloc.submit(_outgoing(kind)), isFalse);
          expect(h.bloc.state.status, ChatStatus.failure);
          expect(h.bloc.state.chatLimitRefusalCount, 0);
          expect(h.bloc.state.audioSendFailureCount, kind == 'audio' ? 1 : 0);
          expect(h.bloc.state.replyToMessage, same(h.reply));
          expect(h.bloc.state.messages, original.messages);
          expect(h.bloc.state.initialMessageIds, original.initialMessageIds);
          expect(h.messages.enqueued, isEmpty);
          expect(
            h.messages.calls,
            hasLength(failure == 'local enqueue' ? 1 : 0),
          );
          expect(
            h.messages.streamRequests,
            failure == 'local enqueue' ? [_createdChat.id] : isEmpty,
          );
          expect(
            h.bloc.state.resolvedChat,
            failure == 'local enqueue' ? _createdChat : isNull,
          );

          h.chats.create = (_) async => _createdChat;
          h.messages.enqueue = (_) async {};
          expect(await h.bloc.submit(_outgoing(kind)), isTrue);
          expect(h.messages.enqueued, hasLength(1));
          _expectCall(
            h.messages.enqueued.single,
            _outgoing(kind),
            replyId: h.reply.id,
          );
          expect(h.bloc.state.replyToMessage, isNull);
          expect(h.bloc.state.chatLimitRefusalCount, 0);
          expect(
            h.chats.creationPeers,
            List.filled(failure == 'local enqueue' ? 1 : 2, _peer),
          );
        },
      );
    }
  }

  test(
    'legacy add reports a typed refusal without message repository calls',
    () async {
      final h = _Harness();
      await h.start();
      h.chats.create = (_) async => throw const ChatLimitReachedException();
      for (var index = 0; index < _kinds.length; index++) {
        h.bloc.add(_outgoing(_kinds[index]));
        await _until(() => h.bloc.state.chatLimitRefusalCount == index + 1);
        expect(h.messages.calls, isEmpty);
        expect(h.messages.streamRequests, isEmpty);
        expect(h.bloc.state.replyToMessage, h.reply);
        expect(h.bloc.state.messages, h.timeline);
      }
    },
  );

  test(
    'mixed concurrent submits and legacy add wait for one creation in order',
    () async {
      final h = _Harness();
      await h.start();
      final creation = h.holdCreation();
      final events = [
        _outgoing('text'),
        _outgoing('images'),
        _outgoing('audio'),
        _outgoing('location'),
        const ChatMessageSent('legacy tail'),
      ];
      final gates = List.generate(events.length, (_) => h.enqueueGate());
      h.messages.enqueue = (_) => gates[h.messages.calls.length - 1].future;
      final receipts = <Future<bool>>[];
      final completed = <int>[];
      for (var index = 0; index < events.length - 1; index++) {
        final receipt = h.bloc.submit(events[index]);
        receipts.add(receipt);
        final receiptIndex = index;
        unawaited(receipt.then((_) => completed.add(receiptIndex)));
      }
      h.bloc.add(events.last);
      await _until(() => h.chats.creationPeers.isNotEmpty);
      await _flush();
      expect(h.chats.creationPeers, [_peer]);
      expect(h.messages.calls, isEmpty);
      expect(completed, isEmpty);

      creation.complete(_createdChat);
      for (var index = 0; index < events.length; index++) {
        await _until(() => h.messages.calls.length == index + 1);
        await _flush();
        expect(h.messages.enqueued, hasLength(index));
        expect(completed, List.generate(index, (value) => value));
        _expectCall(
          h.messages.calls[index],
          events[index],
          replyId: index == 0 ? h.reply.id : null,
        );
        gates[index].complete();
      }
      expect(await Future.wait(receipts), everyElement(isTrue));
      await _until(() => h.messages.enqueued.length == events.length);
      expect(h.messages.calls.map((call) => call.event), events);
      expect(h.messages.enqueued, h.messages.calls);
      expect(h.chats.creationPeers, [_peer]);
      expect(h.messages.streamRequests, [_createdChat.id]);
      expect(h.bloc.state.replyToMessage, isNull);
    },
  );

  test(
    'queued text captures reply A before waiting and preserves later reply B',
    () async {
      final h = _Harness();
      await h.start();
      h.bloc.add(const ChatReplyCleared());
      await _until(() => h.bloc.state.replyToMessage == null);
      final firstGate = h.enqueueGate();
      final queuedGate = h.enqueueGate();
      h.messages.enqueue = (call) {
        if (call.event == const ChatMessageSent('held first')) {
          return firstGate.future;
        }
        if (call.event == const ChatMessageSent('queued text')) {
          return queuedGate.future;
        }
        return Future<void>.value();
      };
      final first = h.bloc.submit(const ChatMessageSent('held first'));
      await _until(() => h.messages.calls.length == 1);
      expect(h.messages.calls.single.replyId, isNull);

      h.bloc.add(ChatReplySelected(h.reply));
      await _until(() => h.bloc.state.replyToMessage == h.reply);
      final queued = h.bloc.submit(const ChatMessageSent('queued text'));
      await _flush();
      expect(h.messages.calls, hasLength(1));
      final replyB = h.timeline.last;
      h.bloc.add(ChatReplySelected(replyB));
      await _until(() => h.bloc.state.replyToMessage == replyB);

      firstGate.complete();
      expect(await first, isTrue);
      await _until(() => h.messages.calls.length == 2);
      _expectCall(
        h.messages.calls.last,
        const ChatMessageSent('queued text'),
        replyId: h.reply.id,
      );
      expect(h.bloc.state.replyToMessage, same(replyB));
      queuedGate.complete();
      expect(await queued, isTrue);
      expect(h.bloc.state.replyToMessage, same(replyB));

      expect(await h.bloc.submit(const ChatMessageSent('consume B')), isTrue);
      expect(h.messages.calls.last.replyId, replyB.id);
      expect(h.bloc.state.replyToMessage, isNull);
      expect(h.chats.creationPeers, [_peer]);
      expect(h.messages.enqueued, h.messages.calls);
    },
  );

  for (final legacy in [false, true]) {
    for (final edit in ['original reply', 'different reply', 'away and back']) {
      test('partial images legacy=$legacy keep reply intent: $edit', () async {
        final h = _Harness();
        await h.start();
        final partialGate = h.enqueueGate();
        final tailGate = h.enqueueGate();
        final cause = StateError('second image batch could not enqueue');
        final partial = PartialImageSendException(
          queuedPaths: ['one.png', 'two.png'],
          remainingPaths: ['three.png'],
          cause: cause,
        );
        const images = ChatMessageImagesSent([
          'one.png',
          'two.png',
          'three.png',
        ]);
        const tail = ChatMessageSent('queued after partial');
        h.messages.enqueue = (call) async {
          if (call.event == images) {
            await partialGate.future;
            throw partial;
          }
          if (call.event == tail) await tailGate.future;
        };

        final errors = <Future<void>>[];
        if (legacy) {
          h.bloc.add(images);
        } else {
          // Observe both errors immediately, before releasing the enqueue gate.
          // Duplicate submitters must receive the same typed progress once.
          errors.add(
            expectLater(h.bloc.submit(images), throwsA(same(partial))),
          );
          errors.add(
            expectLater(
              h.bloc.submit(ChatMessageImagesSent(List.of(images.imagePaths))),
              throwsA(same(partial)),
            ),
          );
        }
        await _until(() => h.messages.calls.length == 1);
        _expectCall(h.messages.calls.single, images, replyId: h.reply.id);

        ChatMessage? expectedReply;
        if (edit != 'original reply') {
          final replyB = h.timeline.last;
          h.bloc.add(ChatReplySelected(replyB));
          await _until(() => h.bloc.state.replyToMessage == replyB);
          expectedReply = replyB;
          if (edit == 'away and back') {
            final newA = h.reply.copyWith(text: 'newly selected reply A');
            h.bloc.add(ChatReplySelected(newA));
            await _until(() => identical(h.bloc.state.replyToMessage, newA));
            expectedReply = newA;
          }
        }
        final queuedTail = h.bloc.submit(tail);
        await _flush();
        expect(h.messages.calls, hasLength(1));
        partialGate.complete();
        await Future.wait(errors);
        await _until(() => h.messages.calls.length == 2);
        expect(h.bloc.state.status, ChatStatus.failure);
        expect(h.bloc.state.chatLimitRefusalCount, 0);
        expect(h.bloc.state.audioSendFailureCount, 0);
        expect(h.bloc.state.messages, h.timeline);
        expect(h.bloc.state.replyToMessage, same(expectedReply));
        expect(partial.queuedPaths, ['one.png', 'two.png']);
        expect(partial.remainingPaths, ['three.png']);
        expect(partial.cause, same(cause));
        expect(h.messages.enqueued, hasLength(1));
        _expectCall(
          h.messages.enqueued.single,
          const ChatMessageImagesSent(['one.png', 'two.png']),
          replyId: h.reply.id,
        );
        _expectCall(h.messages.calls.last, tail, replyId: expectedReply?.id);

        tailGate.complete();
        expect(await queuedTail, isTrue);
        expect(h.bloc.state.replyToMessage, isNull);
        // The sheet retries just the retained remainder, without attaching the
        // already consumed original reply or duplicating the accepted batch.
        final remainder = ChatMessageImagesSent(partial.remainingPaths);
        expect(await h.bloc.submit(remainder), isTrue);
        _expectCall(h.messages.calls.last, remainder);
        expect(h.messages.enqueued.map((call) => call.event), [
          const ChatMessageImagesSent(['one.png', 'two.png']),
          tail,
          remainder,
        ]);
        expect(h.messages.calls, hasLength(3));
        expect(h.chats.creationPeers, [_peer]);
        expect(h.messages.streamRequests, [_createdChat.id]);
      });
    }
  }

  for (final phase in ['creation', 'enqueue']) {
    for (final edit in ['different reply', 'clear reply', 'away and back']) {
      test('reply edited during $phase is retained: $edit', () async {
        final h = _Harness();
        await h.start();
        final creation = phase == 'creation' ? h.holdCreation() : null;
        final enqueue = h.enqueueGate();
        h.messages.enqueue = (_) => enqueue.future;
        final receipt = h.bloc.submit(_outgoing('text'));
        if (creation != null) {
          await _until(() => h.chats.creationPeers.isNotEmpty);
        } else {
          await _until(() => h.messages.calls.isNotEmpty);
        }

        final alternate = h.timeline.last;
        if (edit == 'clear reply') {
          h.bloc.add(const ChatReplyCleared());
          await _until(() => h.bloc.state.replyToMessage == null);
        } else {
          h.bloc.add(ChatReplySelected(alternate));
          await _until(() => h.bloc.state.replyToMessage == alternate);
          if (edit == 'away and back') {
            final newA = h.reply.copyWith(text: 'newly selected reply A');
            h.bloc.add(ChatReplySelected(newA));
            await _until(() => identical(h.bloc.state.replyToMessage, newA));
          }
        }
        final editedReply = h.bloc.state.replyToMessage;
        creation?.complete(_createdChat);
        await _until(() => h.messages.calls.isNotEmpty);
        expect(
          h.messages.calls.single.replyId,
          h.reply.id,
          reason: 'the queued message retains its original reply snapshot',
        );
        enqueue.complete();
        expect(await receipt, isTrue);
        // Returning to A's ID is a new selection, even during A's original send.
        expect(h.bloc.state.replyToMessage, same(editedReply));
      });
    }

    for (final lateError in [false, true]) {
      test(
        'close during $phase rejects receipts; late error=$lateError is safe',
        () async {
          final h = _Harness();
          await h.start();
          final creation = phase == 'creation' ? h.holdCreation() : null;
          final enqueue = h.enqueueGate();
          h.messages.enqueue = (_) => enqueue.future;
          final first = h.bloc.submit(_outgoing('text'));
          final duplicate = h.bloc.submit(_outgoing('text'));
          final queued = h.bloc.submit(_outgoing('images'));
          await _until(
            () => phase == 'creation'
                ? h.chats.creationPeers.isNotEmpty
                : h.messages.calls.isNotEmpty,
          );
          final state = h.bloc.state;
          await _flush();
          final emissions = h.states.length;
          final watches = h.chats.watchedPeers.length;
          final subscriptions = h.messages.streamRequests.length;
          final calls = h.messages.calls.length;
          final closing = h.close();
          expect(
            await Future.wait([
              first,
              duplicate,
              queued,
            ]).timeout(const Duration(seconds: 2)),
            [false, false, false],
          );
          expect(await h.bloc.submit(_outgoing('location')), isFalse);

          if (creation != null) {
            if (lateError) {
              creation.completeError(StateError('late creation failure'));
            } else {
              creation.complete(_createdChat);
            }
            enqueue.complete();
          } else if (lateError) {
            enqueue.completeError(StateError('late enqueue failure'));
          } else {
            enqueue.complete();
          }
          await closing.timeout(const Duration(seconds: 2));
          h.chats.peers.add(_createdChat);
          h.messages.updates.add([_message('late inbound')]);
          await _flush();
          expect(h.bloc.isClosed, isTrue);
          expect(h.bloc.state, state);
          expect(h.states, hasLength(emissions));
          expect(h.chats.watchedPeers, hasLength(watches));
          expect(h.messages.streamRequests, hasLength(subscriptions));
          expect(h.messages.calls, hasLength(calls));
          expect(h.chats.peerListeners, 0);
          expect(h.messages.listeners, 0);
        },
      );
    }
  }

  test(
    'inbound draft resolution during creation is ignored; result is accepted',
    () async {
      final h = _Harness();
      await h.start();
      final creation = h.holdCreation();
      final receipt = h.bloc.submit(_outgoing('text'));
      await _until(() => h.chats.creationPeers.isNotEmpty);
      final inbound = _createdChat.copyWith(id: 'inbound-conversation');
      // This represents an event already queued when the peer observer cancelled.
      h.bloc.add(ChatDraftResolved(peerId: _peer, chat: inbound));
      h.chats.peers.add(inbound);
      await _flush();
      expect(h.bloc.state.chatId, h.initialChat.id);
      expect(h.bloc.state.resolvedChat, isNull);
      expect(h.messages.calls, isEmpty);
      expect(h.messages.streamRequests, isEmpty);
      creation.complete(_createdChat);
      expect(await receipt, isTrue);
      expect(h.bloc.state.resolvedChat, _createdChat);
      expect(h.messages.streamRequests, [_createdChat.id]);
      _expectCall(
        h.messages.calls.single,
        _outgoing('text'),
        replyId: h.reply.id,
      );
      expect(h.chats.creationPeers, [_peer]);
    },
  );

  test(
    'submit snapshots mutable image and waveform payloads before queueing',
    () async {
      final h = _Harness();
      await h.start();
      final creation = h.holdCreation();
      final images = ['first.png', 'second.png'];
      final waveform = [0.2, 0.8];
      final imageReceipt = h.bloc.submit(ChatMessageImagesSent(images));
      final audioReceipt = h.bloc.submit(
        ChatMessageAudioSent(
          audioPath: 'voice.m4a',
          duration: const Duration(seconds: 3),
          waveform: waveform,
        ),
      );
      images.clear();
      waveform[0] = 1;
      await _until(() => h.chats.creationPeers.isNotEmpty);
      creation.complete(_createdChat);
      expect(await Future.wait([imageReceipt, audioReceipt]), [true, true]);
      expect(
        h.messages.calls.first.event,
        const ChatMessageImagesSent(['first.png', 'second.png']),
      );
      expect(
        h.messages.calls.last.event,
        const ChatMessageAudioSent(
          audioPath: 'voice.m4a',
          duration: Duration(seconds: 3),
          waveform: [0.2, 0.8],
        ),
      );
    },
  );
}

const _peer = 'submission-peer';
const _kinds = ['text', 'images', 'audio', 'location'];
final _createdChat = Chat(
  id: 'created-conversation',
  peerId: _peer,
  peerUsername: 'peer',
  userName: 'Peer',
  lastMessage: '',
  lastMessageTime: DateTime.utc(2026, 10, 27),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);

// Fresh equal instances exercise payload equality rather than object identity.
ChatOutgoingEvent _outgoing(String kind) => switch (kind) {
  // ignore: prefer_const_constructors
  'text' => ChatMessageSent('send this text'),
  // ignore: prefer_const_constructors
  'images' => ChatMessageImagesSent(['one.png', 'two.png']),
  // ignore: prefer_const_constructors
  'audio' => ChatMessageAudioSent(
    audioPath: 'voice.m4a',
    duration: const Duration(seconds: 3),
    waveform: [0.2, 0.8],
  ),
  // ignore: prefer_const_constructors
  'location' => ChatLocationSent(latitude: 55.75, longitude: 37.62),
  _ => throw ArgumentError.value(kind),
};

ChatMessage _message(String id) => ChatMessage(
  id: id,
  chatId: _createdChat.id,
  senderId: _peer,
  text: 'message $id',
  timestamp: DateTime.utc(2026, 10, 27),
  isMine: false,
);

void _expectCall(
  _EnqueueCall call,
  ChatOutgoingEvent event, {
  String? replyId,
}) {
  expect(call.chatId, _createdChat.id);
  expect(call.event, event);
  expect(call.replyId, replyId);
}

class _Harness {
  _Harness({bool draft = true}) {
    initialChat = draft
        ? Chat.directDraft(
            peerId: _peer,
            peerUsername: 'peer',
            peerDisplayName: 'Peer',
          )
        : _createdChat;
    bloc = ChatBloc(
      chatRepository: messages,
      chatsRepository: chats,
      initialChat: initialChat,
    );
    _statesSubscription = bloc.stream.listen(states.add);
    addTearDown(() async {
      for (final release in _releases) {
        release();
      }
      await close();
      await _statesSubscription.cancel();
      await messages.updates.close();
      await chats.peers.close();
    });
  }

  final chats = _Chats();
  final messages = _Messages();
  final timeline = [_message('reply-original'), _message('reply-alternate')];
  final states = <ChatState>[];
  final _releases = <void Function()>[];
  late final Chat initialChat;
  late final ChatBloc bloc;
  late final StreamSubscription<ChatState> _statesSubscription;
  Future<void>? _closing;
  ChatMessage get reply => timeline.first;

  Future<void> start() async {
    bloc.add(ChatStarted(initialChat.id));
    await _until(
      () => initialChat.isDraft
          ? chats.peerListeners == 1
          : messages.listeners == 1,
    );
    bloc.add(ChatMessagesReceived(timeline));
    bloc.add(ChatReplySelected(reply));
    await _until(
      () =>
          bloc.state.replyToMessage == reply &&
          bloc.state.messages.length == timeline.length,
    );
    await _flush();
  }

  Completer<Chat> holdCreation() {
    final gate = Completer<Chat>();
    chats.create = (_) => gate.future;
    _releases.add(() {
      if (!gate.isCompleted) gate.complete(_createdChat);
    });
    return gate;
  }

  Completer<void> enqueueGate() {
    final gate = Completer<void>();
    _releases.add(() {
      if (!gate.isCompleted) gate.complete();
    });
    return gate;
  }

  Future<void> close() => _closing ??= bloc.close();
}

class _Chats extends MockChatsRepository implements IChatsPeerRepository {
  _Chats() {
    peers = StreamController<Chat?>.broadcast(
      onListen: () => peerListeners++,
      onCancel: () => peerListeners--,
    );
  }

  late final StreamController<Chat?> peers;
  final creationPeers = <String>[];
  final watchedPeers = <String>[];
  int peerListeners = 0;
  Future<Chat> Function(String) create = (_) async => _createdChat;

  @override
  Future<Chat> ensureDirectChat(String peerId) {
    creationPeers.add(peerId);
    return create(peerId);
  }

  @override
  Stream<Chat?> watchChatByPeerId(String peerId) {
    watchedPeers.add(peerId);
    return peers.stream;
  }
}

class _EnqueueCall {
  const _EnqueueCall(this.chatId, this.event, this.replyId);

  final String chatId;
  final ChatOutgoingEvent event;
  final String? replyId;
}

class _Messages extends MockChatRepository {
  _Messages() {
    updates = StreamController<List<ChatMessage>>.broadcast(
      onListen: () => listeners++,
      onCancel: () => listeners--,
    );
  }

  late final StreamController<List<ChatMessage>> updates;
  final streamRequests = <String>[];
  final calls = <_EnqueueCall>[];
  final enqueued = <_EnqueueCall>[];
  int listeners = 0;
  Future<void> Function(_EnqueueCall) enqueue = (_) async {};

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    streamRequests.add(chatId);
    return updates.stream;
  }

  Future<void> _record(
    String id,
    ChatOutgoingEvent event,
    String? replyId,
  ) async {
    final call = _EnqueueCall(id, event, replyId);
    calls.add(call);
    try {
      await enqueue(call);
    } on PartialImageSendException catch (error) {
      // Model the accepted batch separately from the incomplete selection.
      enqueued.add(
        _EnqueueCall(id, ChatMessageImagesSent(error.queuedPaths), replyId),
      );
      rethrow;
    }
    enqueued.add(call);
  }

  @override
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToMessageId,
  }) => _record(chatId, ChatMessageSent(text), replyToMessageId);

  @override
  Future<void> sendImages(
    String chatId,
    List<String> imagePaths, {
    String? replyToMessageId,
  }) => _record(
    chatId,
    ChatMessageImagesSent(List.of(imagePaths)),
    replyToMessageId,
  );

  @override
  Future<void> sendAudio(
    String chatId,
    String audioPath,
    Duration duration,
    List<double> waveform, {
    String? replyToMessageId,
  }) => _record(
    chatId,
    ChatMessageAudioSent(
      audioPath: audioPath,
      duration: duration,
      waveform: List.of(waveform),
    ),
    replyToMessageId,
  );

  @override
  Future<void> sendLocation(
    String chatId,
    double latitude,
    double longitude, {
    String? replyToMessageId,
  }) => _record(
    chatId,
    ChatLocationSent(latitude: latitude, longitude: longitude),
    replyToMessageId,
  );
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for send state');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _flush() async {
  for (var turn = 0; turn < 5; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}
