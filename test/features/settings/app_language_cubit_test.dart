import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

void main() {
  test(
    'restores startup language without flashing device locale while loading',
    () async {
      final cache = Completer<AppLanguage?>();
      final cubit = AppLanguageCubit(
        initialLanguage: AppLanguage.russian,
        repository: _LanguageRepository(
          cached: null,
          refreshed: AppLanguage.english,
          readCache: () => cache.future,
        ),
      );
      addTearDown(cubit.close);
      expect(cubit.state.language, AppLanguage.russian);
      final loading = cubit.setAuthenticatedUser('user-a');
      expect(cubit.state.language, AppLanguage.russian);
      expect(cubit.state.isLoading, isTrue);
      cache.complete(AppLanguage.english);
      await loading;
      expect(cubit.state.language, AppLanguage.english);
      expect(cubit.state.isLoading, isFalse);
    },
  );
  test(
    'keeps startup unconfirmed until cache or remote is available',
    () async {
      final cache = Completer<AppLanguage?>();
      final refresh = Completer<AppLanguage?>();
      final cubit = AppLanguageCubit(
        repository: _LanguageRepository(
          cached: null,
          refreshed: null,
          readCache: () => cache.future,
          refresh: () => refresh.future,
        ),
      );
      addTearDown(cubit.close);
      final loading = cubit.setAuthenticatedUser('user-a');
      expect(cubit.state.isLoading, isTrue);
      cache.complete(AppLanguage.english);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.language, AppLanguage.english);
      expect(cubit.state.isLoading, isFalse);
      refresh.complete(AppLanguage.english);
      await loading;
      expect(cubit.state.isLoading, isFalse);
    },
  );

  test(
    'offline cold start clears loading after cache and remote fail',
    () async {
      final cubit = AppLanguageCubit(
        repository: _LanguageRepository(
          cached: null,
          refreshed: null,
          readCache: () async => throw StateError('cache unavailable'),
          refresh: () async => throw StateError('offline'),
        ),
      );
      addTearDown(cubit.close);
      final fallback = cubit.state.language;
      await cubit.setAuthenticatedUser('user-a');
      expect(cubit.state.language, fallback);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.isSaving, isFalse);
    },
  );

  test(
    'late cache cannot undo a selection made while startup is pending',
    () async {
      final cache = Completer<AppLanguage?>();
      final write = Completer<AppLanguage>();
      final cubit = AppLanguageCubit(
        repository: _LanguageRepository(
          cached: null,
          refreshed: AppLanguage.english,
          readCache: () => cache.future,
          update: (_) => write.future,
        ),
      );
      addTearDown(cubit.close);
      final loading = cubit.setAuthenticatedUser('user-a');
      final selected = cubit.state.language == AppLanguage.english
          ? AppLanguage.russian
          : AppLanguage.english;
      final stale = selected == AppLanguage.english
          ? AppLanguage.russian
          : AppLanguage.english;
      cubit.select(selected);
      cache.complete(stale);
      await loading;
      expect(cubit.state.language, selected);
      expect(cubit.state.isSaving, isTrue);
      write.complete(selected);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.language, selected);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.isSaving, isFalse);
    },
  );

  test(
    'old account completion cannot apply its cached language after logout',
    () async {
      final cache = Completer<AppLanguage?>();
      var remoteCalls = 0;
      final cubit = AppLanguageCubit(
        repository: _LanguageRepository(
          cached: null,
          refreshed: null,
          readCache: () => cache.future,
          refresh: () async {
            remoteCalls++;
            return AppLanguage.russian;
          },
        ),
      );
      addTearDown(cubit.close);
      final fallback = cubit.state.language;
      final loading = cubit.setAuthenticatedUser('user-a');
      await cubit.setAuthenticatedUser(null);
      cache.complete(
        fallback == AppLanguage.english
            ? AppLanguage.russian
            : AppLanguage.english,
      );
      await loading;
      expect(cubit.state.language, fallback);
      expect(cubit.state.isLoading, isFalse);
      expect(remoteCalls, 0);
    },
  );

  test(
    'uses cached language before refreshing the account preference',
    () async {
      final cubit = AppLanguageCubit(
        repository: _LanguageRepository(
          cached: AppLanguage.english,
          refreshed: AppLanguage.russian,
        ),
      );
      addTearDown(cubit.close);

      await cubit.setAuthenticatedUser('user-a');

      expect(cubit.state.language, AppLanguage.russian);
      expect(cubit.state.isSaving, isFalse);
    },
  );

  test(
    'locks a write and rolls the optimistic language back on failure',
    () async {
      final completer = Completer<AppLanguage>();
      final cubit = AppLanguageCubit(
        repository: _LanguageRepository(
          cached: AppLanguage.russian,
          refreshed: AppLanguage.russian,
          update: (_) => completer.future,
        ),
      );
      addTearDown(cubit.close);
      await cubit.setAuthenticatedUser('user-a');

      cubit.select(AppLanguage.english);
      cubit.select(AppLanguage.russian);
      expect(cubit.state.language, AppLanguage.english);
      expect(cubit.state.isSaving, isTrue);

      completer.completeError(StateError('offline'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.language, AppLanguage.russian);
      expect(cubit.state.isSaving, isFalse);
      expect(cubit.state.feedback, AppLanguageFeedback.failure);
    },
  );

  test('does not let a late refresh replace an optimistic language', () async {
    final refresh = Completer<AppLanguage?>();
    final write = Completer<AppLanguage>();
    final cubit = AppLanguageCubit(
      repository: _LanguageRepository(
        cached: AppLanguage.russian,
        refreshed: AppLanguage.russian,
        refresh: () => refresh.future,
        update: (_) => write.future,
      ),
    );
    addTearDown(cubit.close);

    final loading = cubit.setAuthenticatedUser('user-a');
    await Future<void>.delayed(Duration.zero);
    cubit.select(AppLanguage.english);
    refresh.complete(AppLanguage.russian);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.language, AppLanguage.english);
    expect(cubit.state.isSaving, isTrue);
    write.complete(AppLanguage.english);
    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.language, AppLanguage.english);
    expect(cubit.state.isSaving, isFalse);
  });
}

class _LanguageRepository implements ISettingsRepository {
  @override
  Stream<bool> watchNearbyVisibility() => const Stream.empty();

  _LanguageRepository({
    required this.cached,
    required this.refreshed,
    this.refresh,
    this.update,
    this.readCache,
  });

  final AppLanguage? cached;
  final AppLanguage? refreshed;
  final Future<AppLanguage?> Function()? refresh;
  final Future<AppLanguage?> Function()? readCache;
  final Future<AppLanguage> Function(AppLanguage)? update;

  @override
  Future<AppLanguage?> readCachedAppLanguage() =>
      readCache?.call() ?? Future.value(cached);

  @override
  Future<AppLanguage?> refreshAppLanguage() =>
      refresh?.call() ?? Future.value(refreshed);

  @override
  Future<AppLanguage> updateAppLanguage(AppLanguage language) =>
      update?.call(language) ?? Future.value(language);

  @override
  Future<SearchPrivacySettings?> readCachedSearchPrivacySettings() async =>
      null;

  @override
  Future<SearchPrivacySettings> refreshSearchPrivacySettings() async =>
      const SearchPrivacySettings();

  @override
  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  ) async => const SearchPrivacySettings();

  @override
  Future<SearchPrivacySettings> updateLastSeenVisibility(
    LastSeenVisibility visibility,
  ) async => const SearchPrivacySettings();

  @override
  Future<SearchPrivacySettings> updateLocationVisibility({
    required bool sharePreciseLocation,
    required bool shareDistance,
  }) async => const SearchPrivacySettings();

  @override
  Future<Set<String>> readCachedPreciseLocationExclusions() async => {};

  @override
  Future<Set<String>> refreshPreciseLocationExclusions() async => {};

  @override
  Future<Set<String>> setPreciseLocationExcluded(
    String friendUserId, {
    required bool excluded,
  }) async => {};

  @override
  Future<void> clearUserCache(String userId) async {}
}
