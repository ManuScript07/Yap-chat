import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

void main() {
  test(
    'uses the cached policy before refresh and saves a global change once',
    () async {
      final update = Completer<SearchPrivacySettings>();
      final repository = _SettingsRepository(
        cached: const SearchPrivacySettings(),
        cachedExclusions: {'friend-a'},
        refresh: () => Future.value(const SearchPrivacySettings()),
        refreshExclusions: () => Future.value({'friend-a'}),
        locationUpdate: (_, _) => update.future,
      );
      final cubit = LocationVisibilityCubit(repository: repository);
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.settings, const SearchPrivacySettings());
      expect(cubit.state.excludedFriendIds, {'friend-a'});

      cubit.setGlobal(shareDistance: false);
      expect(cubit.state.settings?.shareDistance, isFalse);
      expect(cubit.state.isSaving, isTrue);
      expect(repository.locationUpdates, [(true, false)]);

      cubit.setGlobal(sharePreciseLocation: false);
      expect(repository.locationUpdates, [(true, false)]);

      update.complete(const SearchPrivacySettings(shareDistance: false));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSaving, isFalse);
      expect(cubit.state.settings?.shareDistance, isFalse);
    },
  );

  test('rolls back a per-friend exclusion after a rejected update', () async {
    final repository = _SettingsRepository(
      cached: const SearchPrivacySettings(),
      cachedExclusions: const {},
      refresh: () => Future.value(const SearchPrivacySettings()),
      refreshExclusions: () => Future.value(const {}),
      exclusionUpdate: (_, _) =>
          Future<Set<String>>.error(StateError('offline')),
    );
    final cubit = LocationVisibilityCubit(repository: repository);
    addTearDown(cubit.close);

    await cubit.load();
    cubit.setFriendExcluded('friend-a', excluded: true);
    expect(cubit.state.excludedFriendIds, {'friend-a'});

    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.excludedFriendIds, isEmpty);
    expect(cubit.state.feedback, LocationVisibilityFeedback.failure);
  });
}

class _SettingsRepository implements ISettingsRepository {
  @override
  Stream<bool> watchNearbyVisibility() => const Stream.empty();

  _SettingsRepository({
    required this.cached,
    required this.cachedExclusions,
    required this.refresh,
    required this.refreshExclusions,
    this.locationUpdate,
    this.exclusionUpdate,
  });

  final SearchPrivacySettings? cached;
  final Set<String> cachedExclusions;
  final Future<SearchPrivacySettings> Function() refresh;
  final Future<Set<String>> Function() refreshExclusions;
  final Future<SearchPrivacySettings> Function(bool, bool)? locationUpdate;
  final Future<Set<String>> Function(String, bool)? exclusionUpdate;
  final locationUpdates = <(bool, bool)>[];

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
  Future<Set<String>> readCachedPreciseLocationExclusions() async =>
      cachedExclusions;

  @override
  Future<SearchPrivacySettings> refreshSearchPrivacySettings() => refresh();

  @override
  Future<Set<String>> refreshPreciseLocationExclusions() => refreshExclusions();

  @override
  Future<SearchPrivacySettings> updateLocationVisibility({
    required bool sharePreciseLocation,
    required bool shareDistance,
  }) {
    locationUpdates.add((sharePreciseLocation, shareDistance));
    return locationUpdate?.call(sharePreciseLocation, shareDistance) ??
        Future.value(
          SearchPrivacySettings(
            sharePreciseLocation: sharePreciseLocation,
            shareDistance: shareDistance,
          ),
        );
  }

  @override
  Future<Set<String>> setPreciseLocationExcluded(
    String friendUserId, {
    required bool excluded,
  }) => exclusionUpdate?.call(friendUserId, excluded) ?? Future.value(const {});

  @override
  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  ) => Future.value(const SearchPrivacySettings());

  @override
  Future<SearchPrivacySettings> updateLastSeenVisibility(
    LastSeenVisibility visibility,
  ) => Future.value(const SearchPrivacySettings());

  @override
  Future<void> clearUserCache(String userId) async {}
}
