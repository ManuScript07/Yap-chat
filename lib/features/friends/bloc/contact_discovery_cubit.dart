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
    this.actionError,
  });

  final ContactDiscoveryStatus status;
  final List<ContactDiscoveryEntry> entries;
  final String query;
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
    Object? actionError,
    bool clearActionError = false,
  }) => ContactDiscoveryState(
    status: status ?? this.status,
    entries: entries ?? this.entries,
    query: query ?? this.query,
    actionError: clearActionError ? null : actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [status, entries, query, actionError];
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

  Future<void> load() async {
    emit(const ContactDiscoveryState(status: ContactDiscoveryStatus.loading));
    try {
      final contacts = await _contactsRepository.readPhoneContacts();
      final matches = await _friendsRepository.matchContactPhones(
        contacts.map((contact) => contact.normalizedPhone).toList(),
      );
      if (isClosed) return;
      emit(
        ContactDiscoveryState(
          status: ContactDiscoveryStatus.success,
          entries: _sortEntries(
            contacts.map(
              (contact) => ContactDiscoveryEntry(
                contact: contact,
                candidate: matches[contact.normalizedPhone],
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (!isClosed) {
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
    if (candidate == null) return 1;
    return switch (candidate.relationship) {
      FriendRelationship.incoming => 2,
      FriendRelationship.outgoing => 3,
      FriendRelationship.friend => 4,
      FriendRelationship.none => 0,
    };
  }
}
