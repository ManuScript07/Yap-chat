enum AccountDeletionReason {
  ads,
  newAccount,
  safety,
  fewPeople,
  noLongerChat,
  technicalProblems,
  other;

  String get apiValue => switch (this) {
    AccountDeletionReason.ads => 'ads',
    AccountDeletionReason.newAccount => 'new_account',
    AccountDeletionReason.safety => 'safety',
    AccountDeletionReason.fewPeople => 'few_people',
    AccountDeletionReason.noLongerChat => 'no_longer_chat',
    AccountDeletionReason.technicalProblems => 'technical_problems',
    AccountDeletionReason.other => 'other',
  };
}

class AccountDeletionSurvey {
  const AccountDeletionSurvey({required this.reasons, this.feedback});

  final List<AccountDeletionReason> reasons;
  final String? feedback;

  List<String> get apiReasons =>
      reasons.map((reason) => reason.apiValue).toList(growable: false);
}
