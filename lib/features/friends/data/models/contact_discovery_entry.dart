import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/friends/data/models/device_contact_phone.dart';
import 'package:yap_chat/features/friends/data/models/friend_candidate.dart';

enum ContactMatchStatus { unknown, notRegistered, matched }

class ContactDiscoveryEntry extends Equatable {
  const ContactDiscoveryEntry({
    required this.contact,
    required this.matchStatus,
    this.candidate,
  });

  final DeviceContactPhone contact;
  final ContactMatchStatus matchStatus;
  final FriendCandidate? candidate;

  ContactDiscoveryEntry copyWith({
    FriendCandidate? candidate,
    ContactMatchStatus? matchStatus,
    bool clearCandidate = false,
  }) {
    final nextCandidate = clearCandidate ? null : candidate ?? this.candidate;
    return ContactDiscoveryEntry(
      contact: contact,
      matchStatus: nextCandidate != null
          ? ContactMatchStatus.matched
          : matchStatus ?? this.matchStatus,
      candidate: nextCandidate,
    );
  }

  @override
  List<Object?> get props => [contact, matchStatus, candidate];
}
