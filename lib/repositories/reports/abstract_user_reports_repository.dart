import 'package:yap_chat/features/reports/data/data.dart';

abstract interface class IUserReportsRepository {
  Future<void> submitReport({
    required String targetUserId,
    required UserReportReason reason,
  });

  Future<void> clearUserCache(String userId);
}

class UserReportRateLimitException implements Exception {
  const UserReportRateLimitException();
}

class UserReportActionInProgressException implements Exception {
  const UserReportActionInProgressException();
}
