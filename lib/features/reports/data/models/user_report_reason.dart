enum UserReportReason {
  spam,
  scam,
  pornography,
  other;

  String get databaseValue => name;
}
