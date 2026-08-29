import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

enum ContactDiscoveryStatus { initial, loading, success, failure }

class ContactDiscoveryState extends Equatable {
  const ContactDiscoveryState({
    this.status = ContactDiscoveryStatus.initial,
    this.entries = const [],
    this.query = '',
    this.isRefreshing = false,
    this.refreshFailed = false,
    this.actionError,
  });

  final ContactDiscoveryStatus status;
  final List<ContactDiscoveryEntry> entries;
  final String query;
  final bool isRefreshing;
  final bool refreshFailed;
  final Object? actionError;

  List<ContactDiscoveryEntry> get visibleEntries {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return entries;
    return entries
        .where((entry) {
          final profileName = entry.candidate?.displayName.toLowerCase();
          final contactName = entry.contact.displayName.toLowerCase();
          return contactName.contains(normalizedQuery) ||
              (profileName?.contains(normalizedQuery) ?? false);
        })
        .toList(growable: false);
  }

  ContactDiscoveryState copyWith({
    ContactDiscoveryStatus? status,
    List<ContactDiscoveryEntry>? entries,
    String? query,
    bool? isRefreshing,
    bool? refreshFailed,
    Object? actionError,
    bool clearActionError = false,
  }) => ContactDiscoveryState(
    status: status ?? this.status,
    entries: entries ?? this.entries,
    query: query ?? this.query,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailed: refreshFailed ?? this.refreshFailed,
    actionError: clearActionError ? null : actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [
    status,
    entries,
    query,
    isRefreshing,
    refreshFailed,
    actionError,
  ];
}

class ContactDiscoveryCubit extends Cubit<ContactDiscoveryState> {
  ContactDiscoveryCubit({
    required IContactsRepository contactsRepository,
    required IFriendsRepository friendsRepository,
  }) : _contactsRepository = contactsRepository,
       _friendsRepository = friendsRepository,
       super(const ContactDiscoveryState());

  final IContactsRepository _contactsRepository;
  final IFriendsRepository _friendsRepository;
  StreamSubscription<List<Friend>>? _friendsSubscription;
  Set<String>? _knownFriendIds;
  final Set<String> _pendingNewFriendIds = {};
  int _loadGeneration = 0;
  bool _friendMatchRefreshRunning = false;

  Future<void> load() async {
    _ensureFriendSubscription();
    final generation = ++_loadGeneration;
    emit(const ContactDiscoveryState(status: ContactDiscoveryStatus.loading));
    try {
      final contacts = await _contactsRepository.readPhoneContacts();
      if (isClosed || generation != _loadGeneration) return;
      final phoneNumbers = contacts
          .map((contact) => contact.normalizedPhone)
          .toList(growable: false);
      ContactMatchSnapshot cached;
      try {
        cached = await _friendsRepository.readCachedContactMatches(
          phoneNumbers,
        );
      } catch (_) {
        cached = const ContactMatchSnapshot();
      }
      if (isClosed || generation != _loadGeneration) return;
      emit(
        ContactDiscoveryState(
          status: ContactDiscoveryStatus.success,
          entries: _entriesFromSnapshot(contacts, cached),
          isRefreshing: phoneNumbers.isNotEmpty,
        ),
      );
      if (phoneNumbers.isEmpty) return;
      try {
        final refreshed = await _friendsRepository.refreshContactMatches(
          phoneNumbers,
        );
        if (isClosed || generation != _loadGeneration) return;
        emit(
          state.copyWith(
            entries: _entriesFromSnapshot(contacts, refreshed),
            isRefreshing: false,
            refreshFailed: false,
          ),
        );
        _refreshNewFriendMatchesIfNeeded();
      } catch (_) {
        if (!isClosed && generation == _loadGeneration) {
          emit(state.copyWith(isRefreshing: false, refreshFailed: true));
          _refreshNewFriendMatchesIfNeeded();
        }
      }
    } catch (_) {
      if (!isClosed && generation == _loadGeneration) {
        emit(
          const ContactDiscoveryState(status: ContactDiscoveryStatus.failure),
        );
      }
    }
  }

  Future<void> sendRequest(ContactDiscoveryEntry entry) async {
    final candidate = entry.candidate;
    if (candidate == null ||
        candidate.relationship != FriendRelationship.none) {
      return;
    }
    await _optimisticCandidateAction(
      entry,
      candidate.copyWith(relationship: FriendRelationship.outgoing),
      () => _friendsRepository.sendRequest(candidate),
    );
  }

  Future<void> respondToIncoming(
    ContactDiscoveryEntry entry, {
    required bool accept,
  }) async {
    final candidate = entry.candidate;
    final requestId = candidate?.requestId;
    if (candidate == null ||
        requestId == null ||
        candidate.relationship != FriendRelationship.incoming) {
      return;
    }
    await _optimisticCandidateAction(
      entry,
      candidate.copyWith(
        relationship: accept
            ? FriendRelationship.friend
            : FriendRelationship.none,
        clearRequestId: true,
      ),
      () => _friendsRepository.respondToRequest(requestId, accept: accept),
    );
  }

  Future<void> invite(String text) async {
    try {
      await _contactsRepository.shareInvitation(text);
    } catch (error) {
      if (!isClosed) emit(state.copyWith(actionError: error));
    }
  }

  void queryChanged(String query) => emit(state.copyWith(query: query));

  Future<void> _optimisticCandidateAction(
    ContactDiscoveryEntry entry,
    FriendCandidate optimisticCandidate,
    Future<void> Function() action,
  ) async {
    final index = state.entries.indexOf(entry);
    if (index < 0) return;
    final previous = state.entries;
    final optimistic = [...previous];
    optimistic[index] = entry.copyWith(candidate: optimisticCandidate);
    emit(
      state.copyWith(entries: _sortEntries(optimistic), clearActionError: true),
    );
    try {
      await action();
    } catch (error) {
      if (!isClosed) {
        emit(state.copyWith(entries: previous, actionError: error));
      }
    }
  }

  void clearActionError() => emit(state.copyWith(clearActionError: true));

  void _ensureFriendSubscription() {
    _friendsSubscription ??= _friendsRepository.watchFriends().listen(
      _handleFriendsChanged,
    );
  }

  void _handleFriendsChanged(List<Friend> friends) {
    final currentIds = friends.map((friend) => friend.id).toSet();
    final previousIds = _knownFriendIds;
    _knownFriendIds = currentIds;
    if (previousIds == null) {
      // A contact cache entry can have been written before this friendship was
      // created (for example, while this page was closed). Reconcile the
      // initial local friends snapshot through the narrow friends-only RPC.
      // It never repeats the broad address-book lookup.
      _pendingNewFriendIds.addAll(currentIds);
    } else {
      _pendingNewFriendIds.addAll(currentIds.difference(previousIds));
    }
    _refreshNewFriendMatchesIfNeeded();
  }

  void _refreshNewFriendMatchesIfNeeded() {
    if (isClosed ||
        _friendMatchRefreshRunning ||
        _pendingNewFriendIds.isEmpty ||
        state.status != ContactDiscoveryStatus.success ||
        state.isRefreshing) {
      return;
    }
    final friendIds = Set<String>.from(_pendingNewFriendIds);
    _pendingNewFriendIds.clear();
    final generation = _loadGeneration;
    final contacts = state.entries
        .map((entry) => entry.contact)
        .toList(growable: false);
    if (contacts.isEmpty) return;
    _friendMatchRefreshRunning = true;
    var failed = false;
    unawaited(
      _friendsRepository
          .refreshNewFriendContactMatches(
            contacts.map((contact) => contact.normalizedPhone).toList(),
            friendIds,
          )
          .then((snapshot) {
            if (isClosed || generation != _loadGeneration) return;
            emit(
              state.copyWith(
                entries: _entriesFromSnapshot(contacts, snapshot),
                refreshFailed: false,
              ),
            );
          })
          .catchError((_) {
            // The ordinary cached contacts view remains valid on a transient
            // refresh error. Keep this narrow operation queued for the next
            // page load or friends update, but do not spin in an offline
            // retry loop.
            failed = true;
            _pendingNewFriendIds.addAll(friendIds);
          })
          .whenComplete(() {
            _friendMatchRefreshRunning = false;
            if (!failed) _refreshNewFriendMatchesIfNeeded();
          }),
    );
  }

  @override
  Future<void> close() async {
    await _friendsSubscription?.cancel();
    return super.close();
  }

  static List<ContactDiscoveryEntry> _sortEntries(
    Iterable<ContactDiscoveryEntry> entries,
  ) {
    final sorted = entries.toList();
    sorted.sort((left, right) {
      final byGroup = _sortGroup(left).compareTo(_sortGroup(right));
      if (byGroup != 0) return byGroup;
      final leftName = left.candidate?.displayName ?? left.contact.displayName;
      final rightName =
          right.candidate?.displayName ?? right.contact.displayName;
      final byName = leftName.toLowerCase().compareTo(rightName.toLowerCase());
      return byName != 0 ? byName : left.contact.id.compareTo(right.contact.id);
    });
    return List.unmodifiable(sorted);
  }

  static int _sortGroup(ContactDiscoveryEntry entry) {
    final candidate = entry.candidate;
    if (candidate?.relationship == FriendRelationship.none) return 0;
    if (entry.matchStatus == ContactMatchStatus.notRegistered) return 1;
    if (entry.matchStatus == ContactMatchStatus.unknown) return 2;
    if (candidate == null) return 2;
    return switch (candidate.relationship) {
      FriendRelationship.incoming => 3,
      FriendRelationship.outgoing => 4,
      FriendRelationship.friend => 5,
      FriendRelationship.none => 0,
    };
  }

  static List<ContactDiscoveryEntry> _entriesFromSnapshot(
    List<DeviceContactPhone> contacts,
    ContactMatchSnapshot snapshot,
  ) => _sortEntries(
    contacts.map((contact) {
      final candidate = snapshot.matches[contact.normalizedPhone];
      return ContactDiscoveryEntry(
        contact: contact,
        matchStatus: candidate != null
            ? ContactMatchStatus.matched
            : snapshot.checkedPhoneNumbers.contains(contact.normalizedPhone)
            ? ContactMatchStatus.notRegistered
            : ContactMatchStatus.unknown,
        candidate: candidate,
      );
    }),
  );
}
