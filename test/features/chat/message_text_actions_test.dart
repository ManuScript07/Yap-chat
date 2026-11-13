import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/message_text_entity.dart';
import 'package:yap_chat/features/chat/view/message_text_actions.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/friends/abstract_friends_repository.dart';
import 'package:yap_chat/repositories/profile/abstract_profile_repository.dart';

const _candidate = FriendCandidate(
  id: 'peer',
  username: 'alice',
  displayName: 'Alice',
  relationship: FriendRelationship.none,
);

void main() {
  late _Friends friends;
  late _Profiles profiles;
  late MessageTextActions actions;
  late List<String> opened;
  late List<Object> errors;
  late bool active;
  setUp(() {
    friends = _Friends();
    profiles = _Profiles();
    opened = [];
    errors = [];
    active = true;
    actions = MessageTextActions(
      friends: friends,
      profiles: profiles,
      currentUserId: 'me',
      isActive: () => active,
      openLink: (uri) async {
        opened.add(uri.toString());
        return true;
      },
      openProfile: (id) async => opened.add(id),
      onError: (e, _) => errors.add(e),
    );
  });
  test(
    'username uses exact existing search, not shared-link privacy bypass',
    () async {
      expect(
        await actions.activate(_entity('@alice')),
        MessageTextActionResult.opened,
      );
      expect(friends.queries, ['@alice']);
      expect(profiles.queries, isEmpty);
      expect(opened, ['peer']);
    },
  );
  test('phone uses normalized existing phone match only', () async {
    expect(
      await actions.activate(_entity('+7 (999) 123-45-67')),
      MessageTextActionResult.opened,
    );
    expect(friends.phones, ['+79991234567']);
    expect(opened, ['peer']);
  });
  test('external link has no profile/discovery requests', () async {
    expect(
      await actions.activate(_entity('example.com')),
      MessageTextActionResult.opened,
    );
    expect(opened, ['https://example.com']);
    expect(friends.queries, isEmpty);
    expect(friends.phones, isEmpty);
    expect(profiles.queries, isEmpty);
  });
  test(
    'own app link reuses shared profile resolver without browser roundtrip',
    () async {
      expect(
        await actions.activate(_entity('https://links.yapchat.ru/alice')),
        MessageTextActionResult.opened,
      );
      expect(profiles.queries, ['alice']);
      expect(friends.queries, isEmpty);
      expect(opened, ['peer']);
    },
  );
  test(
    'fast taps during and after lookup never duplicate requests or navigation',
    () async {
      friends.pending = Completer<List<FriendCandidate>>();
      final first = actions.activate(_entity('@alice'));
      expect(
        await actions.activate(_entity('@alice')),
        MessageTextActionResult.ignored,
      );
      friends.pending!.complete([_candidate]);
      expect(await first, MessageTextActionResult.opened);
      expect(
        await actions.activate(_entity('@alice')),
        MessageTextActionResult.ignored,
      );
      expect(friends.queries, ['@alice']);
      expect(opened, ['peer']);
    },
  );
  test(
    'closing route or switching account during lookup cancels navigation',
    () async {
      friends.pending = Completer<List<FriendCandidate>>();
      final first = actions.activate(_entity('@alice'));
      active = false;
      friends.pending!.complete([_candidate]);
      expect(await first, MessageTextActionResult.ignored);
      expect(opened, isEmpty);
    },
  );
  test(
    'hidden/blocked/not-found phone does not navigate from an old cache',
    () async {
      friends.phoneFound = false;
      expect(
        await actions.activate(_entity('+79991234567')),
        MessageTextActionResult.unavailable,
      );
      expect(opened, isEmpty);
    },
  );
  test('prefix result is rejected', () async {
    expect(
      await actions.activate(_entity('@alic')),
      MessageTextActionResult.unavailable,
    );
    expect(opened, isEmpty);
  });
  test('self profile is not opened', () async {
    profiles.result = 'me';
    expect(
      await actions.activate(_entity('https://links.yapchat.ru/alice')),
      MessageTextActionResult.unavailable,
    );
    expect(opened, isEmpty);
  });
  test('offline failure is reported, with no navigation', () async {
    friends.error = StateError('offline');
    expect(
      await actions.activate(_entity('@alice')),
      MessageTextActionResult.failed,
    );
    expect(errors, hasLength(1));
    expect(opened, isEmpty);
  });
  test('timeout releases action; late response never opens profile', () async {
    friends.pending = Completer<List<FriendCandidate>>();
    actions = MessageTextActions(
      friends: friends,
      profiles: profiles,
      currentUserId: 'me',
      isActive: () => active,
      timeout: Duration.zero,
      openLink: (_) async => true,
      openProfile: (id) async => opened.add(id),
      onError: (e, _) => errors.add(e),
    );
    expect(
      await actions.activate(_entity('@alice')),
      MessageTextActionResult.failed,
    );
    friends.pending!.complete([_candidate]);
    await Future<void>.delayed(Duration.zero);
    expect(opened, isEmpty);
  });
}

MessageTextEntity _entity(String text) => MessageTextParser.parse(text).single;

class _Friends implements IFriendsRepository {
  final queries = <String>[];
  final phones = <String>[];
  Completer<List<FriendCandidate>>? pending;
  Object? error;
  bool phoneFound = true;
  @override
  Future<List<FriendCandidate>> searchUsers(String query) async {
    queries.add(query);
    if (error != null) throw error!;
    return pending == null ? [_candidate] : await pending!.future;
  }

  @override
  Future<ContactMatchSnapshot> refreshPhoneMatch(String phone) async {
    phones.add(phone);
    return ContactMatchSnapshot(matches: phoneFound ? {phone: _candidate} : {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements IProfileRepository {
  final queries = <String>[];
  String? result = 'peer';
  @override
  Future<String?> resolveSharedProfileUsername(String username) async {
    queries.add(username);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
