import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

void main() {
  test('uses cached settings before the server refresh completes', () async {
    final refresh = Completer<SearchPrivacySettings>();
    final repository = _FakeSettingsRepository(
      cached: const SearchPrivacySettings(searchByUsername: false),
      refresh: () => refresh.future,
    );
    final cubit = PrivacySettingsCubit(repository: repository);
    addTearDown(cubit.close);

    unawaited(cubit.load());
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.status, PrivacySettingsStatus.ready);
    expect(cubit.state.settings?.searchByUsername, isFalse);

    refresh.complete(const SearchPrivacySettings(searchByPhone: false));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.settings?.searchByPhone, isFalse);
  });

  test(
    'persists only the changed setting and blocks another tap in flight',
    () async {
      final update = Completer<SearchPrivacySettings>();
      final repository = _FakeSettingsRepository(
        cached: const SearchPrivacySettings(),
        refresh: () async => const SearchPrivacySettings(),
        update: (_, _) => update.future,
      );
      final cubit = PrivacySettingsCubit(repository: repository);
      addTearDown(cubit.close);
      await cubit.load();

      cubit.setValue(SearchPrivacySettingKey.phone, false);
      cubit.setValue(SearchPrivacySettingKey.username, false);

      expect(cubit.state.settings?.searchByPhone, isFalse);
      expect(cubit.state.isSaving, isTrue);
      expect(repository.updates, [
        (key: SearchPrivacySettingKey.phone, value: false),
      ]);

      update.complete(
        const SearchPrivacySettings(
          searchByUsername: true,
          searchByPhone: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSaving, isFalse);
      expect(cubit.state.feedback, PrivacySettingsFeedback.success);
    },
  );

  test('does not let a late refresh replace an optimistic write', () async {
    final refresh = Completer<SearchPrivacySettings>();
    final update = Completer<SearchPrivacySettings>();
    final repository = _FakeSettingsRepository(
      cached: const SearchPrivacySettings(),
      refresh: () => refresh.future,
      update: (_, _) => update.future,
    );
    final cubit = PrivacySettingsCubit(repository: repository);
    addTearDown(cubit.close);

    unawaited(cubit.load());
    await Future<void>.delayed(Duration.zero);
    cubit.setValue(SearchPrivacySettingKey.phone, false);

    update.complete(const SearchPrivacySettings(searchByPhone: false));
    refresh.complete(const SearchPrivacySettings());
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.settings?.searchByPhone, isFalse);
    expect(cubit.state.isSaving, isFalse);
  });

  test('restores the confirmed value when an update fails', () async {
    final repository = _FakeSettingsRepository(
      cached: const SearchPrivacySettings(),
      refresh: () async => const SearchPrivacySettings(),
      update: (_, _) => Future.error(StateError('offline')),
    );
    final cubit = PrivacySettingsCubit(repository: repository);
    addTearDown(cubit.close);
    await cubit.load();

    cubit.setValue(SearchPrivacySettingKey.phone, false);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.settings, const SearchPrivacySettings());
    expect(cubit.state.isSaving, isFalse);
    expect(cubit.state.feedback, PrivacySettingsFeedback.failure);
  });

  test('does not write an unchanged value', () async {
    final repository = _FakeSettingsRepository(
      cached: const SearchPrivacySettings(),
      refresh: () async => const SearchPrivacySettings(),
    );
    final cubit = PrivacySettingsCubit(repository: repository);
    addTearDown(cubit.close);
    await cubit.load();

    cubit.setValue(SearchPrivacySettingKey.username, true);
    await Future<void>.delayed(Duration.zero);

    expect(repository.updates, isEmpty);
  });

  test('optimistically saves the selected last-seen audience', () async {
    final update = Completer<SearchPrivacySettings>();
    final repository = _FakeSettingsRepository(
      cached: const SearchPrivacySettings(),
      refresh: () async => const SearchPrivacySettings(),
      lastSeenUpdate: (_) => update.future,
    );
    final cubit = PrivacySettingsCubit(repository: repository);
    addTearDown(cubit.close);
    await cubit.load();

    cubit.setLastSeenVisibility(LastSeenVisibility.friends);

    expect(
      cubit.state.settings?.lastSeenVisibility,
      LastSeenVisibility.friends,
    );
    expect(cubit.state.isSaving, isTrue);
    expect(repository.lastSeenUpdates, [LastSeenVisibility.friends]);

    update.complete(
      const SearchPrivacySettings(
        lastSeenVisibility: LastSeenVisibility.friends,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isSaving, isFalse);
  });
}

class _FakeSettingsRepository implements ISettingsRepository {
  @override
  Stream<bool> watchNearbyVisibility() => const Stream.empty();

  _FakeSettingsRepository({
    required this.cached,
    required this.refresh,
    this.update,
    this.lastSeenUpdate,
  });

  final SearchPrivacySettings? cached;
  final Future<SearchPrivacySettings> Function() refresh;
  final Future<SearchPrivacySettings> Function(SearchPrivacySettingKey, bool)?
  update;
  final Future<SearchPrivacySettings> Function(LastSeenVisibility)?
  lastSeenUpdate;
  final updates = <({SearchPrivacySettingKey key, bool value})>[];
  final lastSeenUpdates = <LastSeenVisibility>[];

  @override
  Future<AppLanguage?> readCachedAppLanguage() async => null;

  @override
  Future<AppLanguage?> refreshAppLanguage() async => null;

  @override
  Future<AppLanguage> updateAppLanguage(AppLanguage language) async => language;

  @override
  Future<SearchPrivacySettings?> readCachedSearchPrivacySettings() async =>
      cached;

  @override
  Future<SearchPrivacySettings> refreshSearchPrivacySettings() => refresh();

  @override
  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  ) {
    updates.add((key: key, value: value));
    return update?.call(key, value) ??
        Future.value(
          (cached ?? const SearchPrivacySettings()).withValue(key, value),
        );
  }

  @override
  Future<SearchPrivacySettings> updateLastSeenVisibility(
    LastSeenVisibility visibility,
  ) {
    lastSeenUpdates.add(visibility);
    return lastSeenUpdate?.call(visibility) ??
        Future.value(
          (cached ?? const SearchPrivacySettings()).copyWith(
            lastSeenVisibility: visibility,
          ),
        );
  }

  @override
  Future<SearchPrivacySettings> updateLocationVisibility({
    required bool sharePreciseLocation,
    required bool shareDistance,
  }) async => (cached ?? const SearchPrivacySettings()).copyWith(
    sharePreciseLocation: sharePreciseLocation,
    shareDistance: shareDistance,
  );

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
