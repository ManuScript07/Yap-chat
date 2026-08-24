import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/friends/data/models/friend_candidate.dart';

class ContactMatchSnapshot extends Equatable {
  const ContactMatchSnapshot({
    this.matches = const {},
    this.checkedPhoneNumbers = const {},
  });

  final Map<String, FriendCandidate> matches;
  final Set<String> checkedPhoneNumbers;

  @override
  List<Object?> get props => [matches, checkedPhoneNumbers];
}
