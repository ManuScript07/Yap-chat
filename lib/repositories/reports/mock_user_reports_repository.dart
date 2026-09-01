import 'package:yap_chat/features/reports/data/data.dart';
import 'package:yap_chat/repositories/reports/abstract_user_reports_repository.dart';

class MockUserReportsRepository implements IUserReportsRepository {
  const MockUserReportsRepository();

  @override
  Future<void> submitReport({
    required String targetUserId,
    required UserReportReason reason,
  }) async {}

  @override
  Future<void> clearUserCache(String userId) async {}
}
