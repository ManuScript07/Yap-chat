import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/repositories/repositories.dart';

void main() {
  test('loads contacts and attaches registered profiles by phone', () async {
    final contacts = _FakeContactsRepository();
    final friends = MockFriendsRepository();
    final cubit = ContactDiscoveryCubit(
      contactsRepository: contacts,
      friendsRepository: friends,
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, ContactDiscoveryStatus.success);
    expect(cubit.state.entries, hasLength(2));
    expect(cubit.state.entries.first.candidate?.displayName, 'Максим');
    expect(cubit.state.entries.last.candidate, isNull);
  });

  test('optimistically marks a contact request as sent', () async {
    final cubit = ContactDiscoveryCubit(
      contactsRepository: _FakeContactsRepository(),
      friendsRepository: MockFriendsRepository(),
    );
    addTearDown(cubit.close);
    await cubit.load();

    await cubit.sendRequest(cubit.state.entries.first);

    expect(
      cubit.state.entries
          .singleWhere((entry) => entry.contact.id == 'contact-1:0')
          .candidate
          ?.relationship,
      FriendRelationship.outgoing,
    );
  });

  test('filters by both profile and address-book names', () {
    final entries = [
      _entry(
        'registered',
        contactName: 'Макс из контактов',
        profileName: 'Максим Профиль',
        relationship: FriendRelationship.none,
      ),
      _entry('unregistered', contactName: 'Анна Телефон'),
    ];

    expect(
      ContactDiscoveryState(
        entries: entries,
        query: 'профиль',
      ).visibleEntries.single.contact.id,
      'registered',
    );
    expect(
      ContactDiscoveryState(
        entries: entries,
        query: 'телефон',
      ).visibleEntries.single.contact.id,
      'unregistered',
    );
  });

  test('keeps cached matches visible when refresh fails offline', () async {
    final friends = _OfflineFriendsRepository(
      cached: ContactMatchSnapshot(
        matches: const {
          '+79990000001': FriendCandidate(
            id: 'candidate-3',
            username: 'max',
            displayName: 'Максим',
            relationship: FriendRelationship.none,
          ),
        },
        checkedPhoneNumbers: const {'+79990000001', '+79990000002'},
      ),
    );
    final cubit = ContactDiscoveryCubit(
      contactsRepository: _FakeContactsRepository(),
      friendsRepository: friends,
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, ContactDiscoveryStatus.success);
    expect(cubit.state.refreshFailed, isTrue);
    expect(cubit.state.isRefreshing, isFalse);
    expect(cubit.state.entries, hasLength(2));
    expect(cubit.state.entries.first.candidate?.displayName, 'Максим');
    expect(cubit.state.entries.last.matchStatus, ContactMatchStatus.notRegistered);
  });

  test('does not mark an unchecked offline contact as unregistered', () async {
    final cubit = ContactDiscoveryCubit(
      contactsRepository: _FakeContactsRepository(),
      friendsRepository: _OfflineFriendsRepository(
        cached: const ContactMatchSnapshot(),
      ),
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, ContactDiscoveryStatus.success);
    expect(cubit.state.refreshFailed, isTrue);
    expect(
      cubit.state.entries.map((entry) => entry.matchStatus),
      everyElement(ContactMatchStatus.unknown),
    );
  });

  test('reconciles only a newly added friend with address-book contacts',
      () async {
    final friends = _NewFriendRepository();
    final cubit = ContactDiscoveryCubit(
      contactsRepository: _FakeContactsRepository(),
      friendsRepository: friends,
    );
    addTearDown(() async {
      await cubit.close();
      await friends.close();
    });

    await cubit.load();
    friends.addFriend(
      Friend(
        id: 'new-friend',
        username: 'anna',
        displayName: 'Анна',
        friendsSince: DateTime.utc(2026, 8, 30),
      ),
    );
    await pumpEventQueue();

    expect(friends.contactRefreshCalls, 1);
    expect(friends.newFriendRefreshes, hasLength(1));
    expect(
      friends.newFriendRefreshes.single.phoneNumbers,
      const ['+79990000001', '+79990000002'],
    );
    expect(friends.newFriendRefreshes.single.friendIds, {'new-friend'});
    expect(
      cubit.state.entries
          .singleWhere((entry) => entry.contact.id == 'contact-2:0')
          .candidate
          ?.relationship,
      FriendRelationship.friend,
    );
  });
}

ContactDiscoveryEntry _entry(
  String id, {
  String? contactName,
  String? profileName,
  FriendRelationship? relationship,
}) => ContactDiscoveryEntry(
  contact: DeviceContactPhone(
    id: id,
    displayName: contactName ?? id,
    normalizedPhone: id == 'registered' ? '+79990000001' : '+79990000002',
  ),
  matchStatus: relationship == null
      ? ContactMatchStatus.notRegistered
      : ContactMatchStatus.matched,
  candidate: relationship == null
      ? null
      : FriendCandidate(
          id: 'user-$id',
          username: id,
          displayName: profileName ?? id,
          relationship: relationship,
        ),
);

class _FakeContactsRepository implements IContactsRepository {
  @override
  Future<ContactsPermissionStatus> requestPermission() async =>
      ContactsPermissionStatus.granted;

  @override
  Future<List<DeviceContactPhone>> readPhoneContacts() async => const [
    DeviceContactPhone(
      id: 'contact-2:0',
      displayName: 'Anna in contacts',
      normalizedPhone: '+79990000002',
    ),
    DeviceContactPhone(
      id: 'contact-1:0',
      displayName: 'Max in contacts',
      normalizedPhone: '+79990000001',
    ),
  ];

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> shareInvitation(String text) async {}
}

class _OfflineFriendsRepository extends MockFriendsRepository {
  _OfflineFriendsRepository({required this.cached});

  final ContactMatchSnapshot cached;

  @override
  Future<ContactMatchSnapshot> readCachedContactMatches(
    List<String> phoneNumbers,
  ) async => cached;

  @override
  Future<ContactMatchSnapshot> refreshContactMatches(
    List<String> phoneNumbers,
  ) => Future.error(const _OfflineError());
}

class _OfflineError implements Exception {
  const _OfflineError();
}

class _NewFriendRepository extends MockFriendsRepository {
  final _friends = StreamController<List<Friend>>.broadcast(sync: true);
  int contactRefreshCalls = 0;
  final List<({List<String> phoneNumbers, Set<String> friendIds})>
  newFriendRefreshes = [];

  @override
  Stream<List<Friend>> watchFriends() async* {
    yield const [];
    yield* _friends.stream;
  }

  @override
  Future<ContactMatchSnapshot> refreshContactMatches(
    List<String> phoneNumbers,
  ) async {
    contactRefreshCalls++;
    return super.refreshContactMatches(phoneNumbers);
  }

  @override
  Future<ContactMatchSnapshot> refreshNewFriendContactMatches(
    List<String> phoneNumbers,
    Set<String> friendIds,
  ) async {
    newFriendRefreshes.add((
      phoneNumbers: List.unmodifiable(phoneNumbers),
      friendIds: Set.unmodifiable(friendIds),
    ));
    return ContactMatchSnapshot(
      matches: const {
        '+79990000002': FriendCandidate(
          id: 'new-friend',
          username: 'anna',
          displayName: 'Анна',
          relationship: FriendRelationship.friend,
        ),
      },
      checkedPhoneNumbers: phoneNumbers.toSet(),
    );
  }

  void addFriend(Friend friend) => _friends.add([friend]);

  Future<void> close() => _friends.close();
}
