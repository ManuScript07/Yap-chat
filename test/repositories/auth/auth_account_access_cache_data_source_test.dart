import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/repositories/auth/auth_account_access_cache_data_source.dart';

void main() {
  group('AuthAccountAccessCacheDataSource', () {
    test(
      'persists a pending deletion marker across data source instances',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final writer = AuthAccountAccessCacheDataSource(
          preferences: preferences,
          environment: 'local',
        );

        await writer.write(
          'account-a',
          const AuthAccountAccess(
            isBanned: false,
            isDeletionPending: true,
            username: 'user_a',
            supportEmail: 'support@example.test',
          ),
        );

        final reader = AuthAccountAccessCacheDataSource(
          preferences: preferences,
          environment: 'local',
        );
        expect(
          await reader.read('account-a'),
          const AuthAccountAccess(
            isBanned: false,
            isDeletionPending: true,
            username: 'user_a',
            supportEmail: 'support@example.test',
          ),
        );
      },
    );

    test(
      'clears a pending marker when server access becomes ordinary',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final source = AuthAccountAccessCacheDataSource(
          preferences: preferences,
          environment: 'local',
        );
        await source.write(
          'account-a',
          const AuthAccountAccess(isBanned: false, isDeletionPending: true),
        );

        await source.write(
          'account-a',
          const AuthAccountAccess(isBanned: false),
        );

        expect(await source.read('account-a'), isNull);
      },
    );

    test(
      'persists an expired deletion marker for offline access gating',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final source = AuthAccountAccessCacheDataSource(
          preferences: preferences,
          environment: 'local',
        );

        final scheduledFor = DateTime.utc(2026, 10, 11, 12);
        await source.write(
          'account-a',
          AuthAccountAccess(
            isBanned: false,
            isDeletionExpired: true,
            deletionScheduledFor: scheduledFor,
            username: 'user_a',
          ),
        );

        expect(
          await source.read('account-a'),
          AuthAccountAccess(
            isBanned: false,
            isDeletionExpired: true,
            deletionScheduledFor: scheduledFor,
            username: 'user_a',
          ),
        );
      },
    );
  });
}
