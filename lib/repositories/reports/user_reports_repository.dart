import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/reports/data/data.dart';
import 'package:yap_chat/repositories/reports/abstract_user_reports_repository.dart';
import 'package:yap_chat/repositories/reports/user_reports_cache_data_source.dart';
import 'package:yap_chat/repositories/reports/user_reports_remote_data_source.dart';

class UserReportsRepository implements IUserReportsRepository {
  UserReportsRepository({
    required UserReportsRemoteDataSource remote,
    required UserReportsCacheDataSource cache,
    required AccountSessionController accountSessionController,
  }) : _remote = remote,
       _cache = cache,
       _accountSessionController = accountSessionController;

  final UserReportsRemoteDataSource _remote;
  final UserReportsCacheDataSource _cache;
  final AccountSessionController _accountSessionController;
  final Set<String> _pendingKeys = <String>{};

  @override
  Future<void> submitReport({
    required String targetUserId,
    required UserReportReason reason,
  }) async {
    final scope = _accountSessionController.capture();
    final normalizedTargetId = targetUserId.trim();
    final pendingKey = '${scope.userId}:$normalizedTargetId';
    if (normalizedTargetId.isEmpty) {
      throw const UserReportRateLimitException();
    }
    if (!_pendingKeys.add(pendingKey)) {
      throw const UserReportActionInProgressException();
    }
    try {
      final cached = await _cache.read(scope.userId);
      _accountSessionController.ensureCurrent(scope);
      _assertLocalQuota(cached, normalizedTargetId);
      final createdAt = await _remote.submit(
        targetUserId: normalizedTargetId,
        reason: reason,
      );
      _accountSessionController.ensureCurrent(scope);
      await _accountSessionController.commit(scope, () async {
        try {
          await _cache.record(scope.userId, normalizedTargetId, createdAt);
        } catch (_) {
          // The accepted server report remains valid even if local storage is
          // unavailable; the database quota remains authoritative.
        }
      });
    } on PostgrestException catch (error) {
      if (error.message.contains('user_report_target_rate_limited') ||
          error.message.contains('user_report_daily_rate_limited')) {
        throw const UserReportRateLimitException();
      }
      rethrow;
    } finally {
      _pendingKeys.remove(pendingKey);
    }
  }

  @override
  Future<void> clearUserCache(String userId) => _cache.clearUser(userId);

  void _assertLocalQuota(Map<String, DateTime> reports, String targetUserId) {
    final now = DateTime.now().toUtc();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    if (reports[targetUserId]?.isAfter(sevenDaysAgo) ?? false) {
      throw const UserReportRateLimitException();
    }
    final dayStart = DateTime.utc(now.year, now.month, now.day);
    final todayTargets = reports.entries
        .where((entry) => !entry.value.isBefore(dayStart))
        .map((entry) => entry.key)
        .toSet();
    if (!todayTargets.contains(targetUserId) && todayTargets.length >= 5) {
      throw const UserReportRateLimitException();
    }
  }
}
