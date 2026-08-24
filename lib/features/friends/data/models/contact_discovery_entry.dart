import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/friends/data/models/device_contact_phone.dart';
import 'package:yap_chat/features/friends/data/models/friend_candidate.dart';

class ContactDiscoveryEntry extends Equatable {
  const ContactDiscoveryEntry({required this.contact, this.candidate});

  final DeviceContactPhone contact;
  final FriendCandidate? candidate;

  ContactDiscoveryEntry copyWith({
    FriendCandidate? candidate,
    bool clearCandidate = false,
  }) => ContactDiscoveryEntry(
    contact: contact,
    candidate: clearCandidate ? null : candidate ?? this.candidate,
  );

  @override
  List<Object?> get props => [contact, candidate];
}
