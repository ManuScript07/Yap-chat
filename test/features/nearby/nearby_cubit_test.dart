import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'dart:async';
import 'package:yap_chat/app/location_tracking_coordinator.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/nearby/bloc/bloc.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/blocks/mock_blocklist_repository.dart';
import 'package:yap_chat/repositories/chat/abstract_location_repository.dart';
import 'package:yap_chat/repositories/friends/mock_friends_repository.dart';
import 'package:yap_chat/repositories/nearby/nearby.dart';
import 'package:yap_chat/repositories/settings/settings.dart';
import 'package:yap_chat/features/settings/data/data.dart';

void main() {
  test(
    'new installation reads hidden server preference before requesting feed',
    () async {
      final settings = _UncachedHiddenSettings();
      final location = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unchanged,
      );
      final tracking = LocationTrackingCoordinator(
        locationRepository: location,
        talker: Talker(),
      );
      final repo = _CountingNearbyRepository();
      final cubit = _createCubit(
        repository: repo,
        locationRepository: location,
        locationTracking: tracking,
        settingsRepository: settings,
      );
      await cubit.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.status, NearbyStatus.visibilityDisabled);
      expect(repo.refreshCount, 0);
      expect(
        settings.reads,
        1,
        reason: 'initial authoritative read must not be duplicated',
      );
      await cubit.close();
      await tracking.dispose();
    },
  );
  for (final fresh in [true, false]) {
    test(
      'hidden feed stays hidden; enable respects fresh geo=$fresh',
      () async {
        final settings = MockSettingsRepository();
        await settings.updateSearchPrivacySetting(
          SearchPrivacySettingKey.nearby,
          false,
        );
        final location = _FakeLocationRepository(
          refreshResult: TrackedLocationRefreshResult.unchanged,
          hasCachedLocation: fresh,
        );
        final tracking = LocationTrackingCoordinator(
          locationRepository: location,
          talker: Talker(),
        );
        final repo = _CountingNearbyRepository();
        final cubit = _createCubit(
          repository: repo,
          locationRepository: location,
          locationTracking: tracking,
          settingsRepository: settings,
        );
        await cubit.initialize();
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.status, NearbyStatus.visibilityDisabled);
        expect(cubit.state.shouldObscureContent, isTrue);
        await cubit.refresh();
        await cubit.loadMore();
        await cubit.requestLocation();
        expect(repo.refreshCount, 0);
        await cubit.enableVisibility();
        await Future<void>.delayed(Duration.zero);
        expect(
          cubit.state.status,
          fresh ? NearbyStatus.ready : NearbyStatus.locationRequired,
        );
        expect(cubit.state.isVisibilitySaving, isFalse);
        expect(repo.refreshCount, fresh ? 1 : 0);
        await cubit.close();
        await tracking.dispose();
      },
    );
  }
  test(
    'hiding invalidates an in-flight head and page, even after completion',
    () async {
      final settings = MockSettingsRepository();
      final location = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unchanged,
      );
      final tracking = LocationTrackingCoordinator(
        locationRepository: location,
        talker: Talker(),
      );
      final repo = _RacingFeedRepository();
      final cubit = _createCubit(
        repository: repo,
        locationRepository: location,
        locationTracking: tracking,
        settingsRepository: settings,
      );
      await cubit.initialize();
      final page = cubit.loadMore();
      final head = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      await settings.updateSearchPrivacySetting(
        SearchPrivacySettingKey.nearby,
        false,
      );
      await Future<void>.delayed(Duration.zero);
      repo.head.complete(_snapshot('late-head'));
      repo.page.complete(_snapshot('late-page'));
      await Future.wait([page, head]);
      expect(cubit.state.status, NearbyStatus.visibilityDisabled);
      expect(cubit.state.people.map((p) => p.id), ['cached']);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.isLoadingMore, isFalse);
      await cubit.close();
      await tracking.dispose();
    },
  );
  test('failed enabling remains hidden and can be retried', () async {
    final settings = _FailingVisibilitySettings();
    final location = _FakeLocationRepository(
      refreshResult: TrackedLocationRefreshResult.unchanged,
    );
    final tracking = LocationTrackingCoordinator(
      locationRepository: location,
      talker: Talker(),
    );
    final cubit = _createCubit(
      repository: _CountingNearbyRepository(),
      locationRepository: location,
      locationTracking: tracking,
      settingsRepository: settings,
    );
    await cubit.initialize();
    await cubit.enableVisibility();
    expect(cubit.state.status, NearbyStatus.visibilityDisabled);
    expect(cubit.state.visibilityFeedbackId, 1);
    expect(cubit.state.isVisibilitySaving, isFalse);
    await cubit.close();
    await tracking.dispose();
  });

  test(
    'quota-denied filter head resumes before paging the new filter',
    () async {
      var now = DateTime.utc(2026, 11, 1);
      final location = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final tracking = LocationTrackingCoordinator(
        locationRepository: location,
        talker: Talker(),
      );
      final repository = _SuccessfulFeedRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: location,
        locationTracking: tracking,
        clock: () => now,
      );
      await cubit.initialize();
      for (var i = 0; i < 8; i++) {
        await cubit.refresh();
      }
      await cubit.applyFilters(const NearbyFilters(minimumAge: 30));
      expect(cubit.needsHeadRefresh, isTrue);
      expect(cubit.paginationQuotaRetryDelay, isNotNull);
      await cubit.loadMore();
      expect(repository.pageCalls, 0);
      now = now.add(const Duration(minutes: 1, seconds: 1));
      expect(cubit.paginationQuotaRetryDelay, isNull);
      await cubit.loadMore();
      expect(cubit.needsHeadRefresh, isFalse);
      expect(cubit.state.filters.minimumAge, 30);
      expect(cubit.state.hasMore, isTrue);
      expect(repository.pageCalls, 0);
      await cubit.loadMore();
      expect(repository.pageCalls, 1);
      await cubit.close();
      await tracking.dispose();
    },
  );

  test('loads a first feed when a recent point is cached locally', () async {
    final locationRepository = _FakeLocationRepository(
      refreshResult: TrackedLocationRefreshResult.unchanged,
    );
    final locationTracking = LocationTrackingCoordinator(
      locationRepository: locationRepository,
      talker: Talker(),
    );
    await locationTracking.setAuthenticatedUser('user-1');
    final repository = _CountingNearbyRepository();
    final cubit = _createCubit(
      repository: repository,
      locationRepository: locationRepository,
      locationTracking: locationTracking,
    );

    await cubit.initialize();

    expect(cubit.state.status, NearbyStatus.ready);
    expect(repository.refreshCount, 1);

    await cubit.close();
    await locationTracking.dispose();
  });

  test(
    'requires a locally recorded point when device location is unavailable',
    () async {
      final locationRepository = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
        hasCachedLocation: false,
      );
      final locationTracking = LocationTrackingCoordinator(
        locationRepository: locationRepository,
        talker: Talker(),
      );
      final repository = _CountingNearbyRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: locationRepository,
        locationTracking: locationTracking,
      );

      await cubit.initialize();

      expect(cubit.state.status, NearbyStatus.locationRequired);
      expect(repository.refreshCount, 0);

      await cubit.close();
      await locationTracking.dispose();
    },
  );

  test(
    'does not treat a fresh feed cache as a location confirmation offline',
    () async {
      final locationRepository = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
        hasCachedLocation: false,
      );
      final locationTracking = LocationTrackingCoordinator(
        locationRepository: locationRepository,
        talker: Talker(),
      );
      final repository = _FreshCachedNearbyRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: locationRepository,
        locationTracking: locationTracking,
      );

      await cubit.initialize();

      expect(cubit.state.status, NearbyStatus.locationRequired);
      expect(repository.refreshCount, 0);

      await cubit.close();
      await locationTracking.dispose();
    },
  );

  test('requires location when the server has no recent point', () async {
    final locationRepository = _FakeLocationRepository(
      refreshResult: TrackedLocationRefreshResult.unavailable,
    );
    final locationTracking = LocationTrackingCoordinator(
      locationRepository: locationRepository,
      talker: Talker(),
    );
    final repository = _LocationRequiredNearbyRepository();
    final cubit = _createCubit(
      repository: repository,
      locationRepository: locationRepository,
      locationTracking: locationTracking,
    );

    await cubit.initialize();

    expect(cubit.state.status, NearbyStatus.locationRequired);
    expect(repository.refreshCount, 1);

    await cubit.close();
    await locationTracking.dispose();
  });

  test(
    'a first-load deadline is a failure, not a false empty result',
    () async {
      final locationRepository = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final locationTracking = LocationTrackingCoordinator(
        locationRepository: locationRepository,
        talker: Talker(),
      );
      final cubit = _createCubit(
        repository: _HangingNearbyRepository(),
        locationRepository: locationRepository,
        locationTracking: locationTracking,
        refreshTimeout: Duration.zero,
      );

      await cubit.initialize();

      expect(cubit.state.status, NearbyStatus.failure);
      expect(cubit.state.isRefreshing, isFalse);

      await cubit.close();
      await locationTracking.dispose();
    },
  );

  test(
    'quietly completes refresh when the server nearby quota is exhausted',
    () async {
      final locationRepository = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final locationTracking = LocationTrackingCoordinator(
        locationRepository: locationRepository,
        talker: Talker(),
      );
      final cubit = _createCubit(
        repository: _RateLimitedNearbyRepository(),
        locationRepository: locationRepository,
        locationTracking: locationTracking,
      );

      await cubit.initialize();

      expect(cubit.state.status, NearbyStatus.ready);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.rateLimitFeedbackId, 1);

      await cubit.close();
      await locationTracking.dispose();
    },
  );

  test(
    'drops an old filter response and refreshes the newly selected filter',
    () async {
      final locationRepository = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final locationTracking = LocationTrackingCoordinator(
        locationRepository: locationRepository,
        talker: Talker(),
      );
      final repository = _DelayedFiltersNearbyRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: locationRepository,
        locationTracking: locationTracking,
      );

      final firstRefresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      final apply = cubit.applyFilters(
        const NearbyFilters(minimumAge: 21, maximumAge: 35),
      );
      await Future<void>.delayed(Duration.zero);
      repository.completeFirst();
      await Future<void>.delayed(Duration.zero);
      repository.completeSecond();
      await Future.wait([firstRefresh, apply]);

      expect(
        cubit.state.filters,
        const NearbyFilters(minimumAge: 21, maximumAge: 35),
      );
      expect(cubit.state.people.map((person) => person.id), ['new-filter']);
      expect(repository.requestedFilters, [
        const NearbyFilters(),
        const NearbyFilters(minimumAge: 21, maximumAge: 35),
      ]);

      await cubit.close();
      await locationTracking.dispose();
    },
  );

  test('locally limits nearby reads to eight requests per minute', () async {
    final locationRepository = _FakeLocationRepository(
      refreshResult: TrackedLocationRefreshResult.unavailable,
    );
    final locationTracking = LocationTrackingCoordinator(
      locationRepository: locationRepository,
      talker: Talker(),
    );
    final repository = _CountingNearbyRepository();
    final cubit = _createCubit(
      repository: repository,
      locationRepository: locationRepository,
      locationTracking: locationTracking,
    );

    for (var attempt = 0; attempt < 9; attempt++) {
      await cubit.refresh();
    }

    expect(repository.refreshCount, 8);
    expect(cubit.state.rateLimitFeedbackId, 1);

    await cubit.close();
    await locationTracking.dispose();
  });

  test(
    'does not leave a changed filter in loading state at the local quota',
    () async {
      final locationRepository = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final locationTracking = LocationTrackingCoordinator(
        locationRepository: locationRepository,
        talker: Talker(),
      );
      final repository = _CountingNearbyRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: locationRepository,
        locationTracking: locationTracking,
      );

      for (var attempt = 0; attempt < 8; attempt++) {
        await cubit.refresh();
      }
      await cubit.applyFilters(
        const NearbyFilters(minimumAge: 21, maximumAge: 35),
      );

      expect(
        cubit.state.filters,
        const NearbyFilters(minimumAge: 21, maximumAge: 35),
      );
      expect(cubit.state.isRefreshing, isFalse);
      expect(repository.refreshCount, 8);

      await cubit.close();
      await locationTracking.dispose();
    },
  );

  test('does not paginate while refreshing the first page', () async {
    final locationRepository = _FakeLocationRepository(
      refreshResult: TrackedLocationRefreshResult.unavailable,
    );
    final locationTracking = LocationTrackingCoordinator(
      locationRepository: locationRepository,
      talker: Talker(),
    );
    final repository = _RefreshAndPaginationRepository();
    final cubit = _createCubit(
      repository: repository,
      locationRepository: locationRepository,
      locationTracking: locationTracking,
    );

    final refresh = cubit.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isRefreshing, isTrue);

    await cubit.loadMore();
    expect(repository.loadMoreCount, 0);

    repository.completeRefresh();
    await refresh;
    await cubit.close();
    await locationTracking.dispose();
  });

  test(
    'keeps the current feed visible while a new filter has no cache',
    () async {
      final locationRepository = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final locationTracking = LocationTrackingCoordinator(
        locationRepository: locationRepository,
        talker: Talker(),
      );
      final repository = _FilterTransitionNearbyRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: locationRepository,
        locationTracking: locationTracking,
      );
      await cubit.initialize();

      final apply = cubit.applyFilters(
        const NearbyFilters(minimumAge: 50, maximumAge: 99),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.people.map((person) => person.id), ['previous-feed']);

      repository.completeFilterRefresh();
      await apply;
      expect(cubit.state.people.map((person) => person.id), ['filtered-feed']);

      await cubit.close();
      await locationTracking.dispose();
    },
  );

  test('does not publish a result after its refresh deadline', () async {
    final locationRepository = _FakeLocationRepository(
      refreshResult: TrackedLocationRefreshResult.unavailable,
    );
    final locationTracking = LocationTrackingCoordinator(
      locationRepository: locationRepository,
      talker: Talker(),
    );
    final repository = _LateNearbyResultRepository();
    final cubit = _createCubit(
      repository: repository,
      locationRepository: locationRepository,
      locationTracking: locationTracking,
      refreshTimeout: Duration.zero,
    );

    await cubit.refresh();
    expect(cubit.state.status, NearbyStatus.failure);
    expect(cubit.state.isRefreshing, isFalse);

    repository.completeRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.status, NearbyStatus.failure);
    expect(cubit.state.people, isEmpty);

    await cubit.close();
    await locationTracking.dispose();
  });
  for (final oldFirst in [false, true]) {
    test('page cannot replace a newer refresh oldFirst=$oldFirst', () async {
      final location = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final tracking = LocationTrackingCoordinator(
        locationRepository: location,
        talker: Talker(),
      );
      final repository = _RacingFeedRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: location,
        locationTracking: tracking,
      );
      await cubit.initialize();
      final page = cubit.loadMore();
      final refresh = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      if (oldFirst) {
        repository.page.complete(_snapshot('old-page'));
        await page;
        expect(cubit.state.people.single.id, 'cached');
      }
      repository.head.complete(_snapshot('fresh'));
      await refresh;
      if (!oldFirst) {
        repository.page.complete(_snapshot('old-page'));
        await page;
      }
      expect(cubit.state.people.single.id, 'fresh');
      expect(cubit.state.isLoadingMore, false);
      expect(cubit.state.feedRevision, 1);
      await cubit.close();
      await tracking.dispose();
    });
  }

  test(
    'refresh deadline keeps a populated feed without accepting its late result',
    () async {
      final location = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final tracking = LocationTrackingCoordinator(
        locationRepository: location,
        talker: Talker(),
      );
      final repository = _RacingFeedRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: location,
        locationTracking: tracking,
        refreshTimeout: Duration.zero,
      );
      await cubit.initialize();
      await cubit.refresh();
      expect(cubit.state.status, NearbyStatus.ready);
      expect(cubit.state.people.single.id, 'cached');
      repository.head.complete(_snapshot('late'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.people.single.id, 'cached');
      expect(cubit.state.feedRevision, 0);
      await cubit.close();
      await tracking.dispose();
    },
  );

  test(
    'blocked reads at the end do not emit a state for every scroll tick',
    () async {
      final location = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final tracking = LocationTrackingCoordinator(
        locationRepository: location,
        talker: Talker(),
      );
      final repository = _SuccessfulFeedRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: location,
        locationTracking: tracking,
      );
      await cubit.initialize();
      for (var i = 0; i < 8; i++) {
        await cubit.refresh();
      }
      await cubit.loadMore();
      final before = cubit.state;
      for (var i = 0; i < 100; i++) {
        await cubit.loadMore();
      }
      expect(identical(cubit.state, before), true);
      expect(repository.pageCalls, 0);
      await cubit.close();
      await tracking.dispose();
    },
  );

  test('null page clears loading and ends automatic pagination', () async {
    final location = _FakeLocationRepository(
      refreshResult: TrackedLocationRefreshResult.unavailable,
    );
    final tracking = LocationTrackingCoordinator(
      locationRepository: location,
      talker: Talker(),
    );
    final repository = _NullPageRepository();
    final cubit = _createCubit(
      repository: repository,
      locationRepository: location,
      locationTracking: tracking,
    );
    await cubit.initialize();
    await cubit.loadMore();
    expect(cubit.state.isLoadingMore, false);
    expect(cubit.state.hasMore, false);
    expect(cubit.state.people.single.id, 'cached');
    await cubit.close();
    await tracking.dispose();
  });

  for (final serverQuota in [false, true]) {
    test(
      'failed page retries without a scroll request storm quota=$serverQuota',
      () async {
        var now = DateTime.utc(2026, 10, 30);
        final location = _FakeLocationRepository(
          refreshResult: TrackedLocationRefreshResult.unavailable,
        );
        final tracking = LocationTrackingCoordinator(
          locationRepository: location,
          talker: Talker(),
        );
        final repository = _FailedPageRepository(serverQuota);
        final cubit = _createCubit(
          repository: repository,
          locationRepository: location,
          locationTracking: tracking,
          clock: () => now,
        );
        await cubit.initialize();
        await cubit.loadMore();
        for (var i = 0; i < 100; i++) {
          await cubit.loadMore();
        }
        expect(repository.pageCalls, 1);
        now = now.add(Duration(seconds: serverQuota ? 61 : 4));
        await cubit.loadMore();
        expect(repository.pageCalls, 2);
        expect(cubit.state.people.single.id, 'cached');
        expect(cubit.state.isLoadingMore, false);
        await cubit.close();
        await tracking.dispose();
      },
    );
  }
  test(
    'rapid filters publish only the latest result even when older calls finish later',
    () async {
      final location = _FakeLocationRepository(
        refreshResult: TrackedLocationRefreshResult.unavailable,
      );
      final tracking = LocationTrackingCoordinator(
        locationRepository: location,
        talker: Talker(),
      );
      final repository = _ManyRequestsRepository();
      final cubit = _createCubit(
        repository: repository,
        locationRepository: location,
        locationTracking: tracking,
      );
      final first = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      final second = cubit.applyFilters(const NearbyFilters(minimumAge: 25));
      await Future<void>.delayed(Duration.zero);
      final latest = cubit.applyFilters(const NearbyFilters(minimumAge: 30));
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests.length, 3);
      repository.requests[2].complete(_snapshot('latest'));
      await latest;
      repository.requests[1].complete(_snapshot('old-b'));
      repository.requests[0].complete(_snapshot('old-a'));
      await Future.wait([first, second]);
      expect(cubit.state.people.single.id, 'latest');
      expect(cubit.state.filters.minimumAge, 30);
      expect(cubit.state.feedRevision, 1);
      expect(cubit.state.isRefreshing, false);
      await cubit.close();
      await tracking.dispose();
    },
  );
}

NearbyCubit _createCubit({
  required INearbyRepository repository,
  required ILocationRepository locationRepository,
  required LocationTrackingCoordinator locationTracking,
  ISettingsRepository? settingsRepository,
  Duration refreshTimeout = NearbyCubit.defaultRefreshTimeout,
  DateTime Function()? clock,
}) {
  final session = AccountSessionController(initialUserId: 'user-1');
  return NearbyCubit(
    repository: repository,
    locationRepository: locationRepository,
    locationTrackingCoordinator: locationTracking,
    accountSessionController: session,
    blocklistRepository: MockBlocklistRepository(),
    profileFriendsRepository: MockFriendsRepository(),
    settingsRepository: settingsRepository,
    refreshTimeout: refreshTimeout,
    clock: clock,
  );
}

class _CountingNearbyRepository extends MockNearbyRepository {
  var refreshCount = 0;

  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) async {
    refreshCount++;
    return super.refreshFeed(filters);
  }
}

class _LocationRequiredNearbyRepository extends _CountingNearbyRepository {
  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) async {
    refreshCount++;
    throw const PostgrestException(message: 'nearby_location_required');
  }
}

class _FreshCachedNearbyRepository extends _CountingNearbyRepository {
  @override
  Future<NearbyCacheSnapshot?> getCachedFeed(NearbyFilters filters) async =>
      NearbyCacheSnapshot(
        people: const [],
        hasMore: false,
        cachedAt: DateTime.now().toUtc(),
      );
}

class _HangingNearbyRepository extends _CountingNearbyRepository {
  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) =>
      Completer<NearbyCacheSnapshot>().future;
}

class _RateLimitedNearbyRepository extends _CountingNearbyRepository {
  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) async {
    refreshCount++;
    throw const PostgrestException(message: 'nearby_rate_limited');
  }
}

class _DelayedFiltersNearbyRepository extends MockNearbyRepository {
  final requestedFilters = <NearbyFilters>[];
  final _first = Completer<NearbyCacheSnapshot>();
  final _second = Completer<NearbyCacheSnapshot>();

  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) {
    requestedFilters.add(filters);
    return requestedFilters.length == 1 ? _first.future : _second.future;
  }

  void completeFirst() => _first.complete(
    NearbyCacheSnapshot(
      people: [_person('old-filter')],
      hasMore: false,
      cachedAt: DateTime.now().toUtc(),
    ),
  );

  void completeSecond() => _second.complete(
    NearbyCacheSnapshot(
      people: [_person('new-filter')],
      hasMore: false,
      cachedAt: DateTime.now().toUtc(),
    ),
  );
}

class _RefreshAndPaginationRepository extends MockNearbyRepository {
  final _refresh = Completer<NearbyCacheSnapshot>();
  var loadMoreCount = 0;

  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) =>
      _refresh.future;

  @override
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters) async {
    loadMoreCount++;
    return super.loadMore(filters);
  }

  void completeRefresh() => _refresh.complete(
    NearbyCacheSnapshot(
      people: [_person('first-page')],
      hasMore: true,
      cachedAt: DateTime.now().toUtc(),
    ),
  );
}

class _FilterTransitionNearbyRepository extends MockNearbyRepository {
  final _filterRefresh = Completer<NearbyCacheSnapshot>();

  @override
  Future<NearbyCacheSnapshot?> getCachedFeed(NearbyFilters filters) async {
    if (filters == const NearbyFilters()) {
      return NearbyCacheSnapshot(
        people: [_person('previous-feed')],
        hasMore: false,
        cachedAt: DateTime.now().toUtc(),
      );
    }
    return null;
  }

  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) =>
      _filterRefresh.future;

  void completeFilterRefresh() => _filterRefresh.complete(
    NearbyCacheSnapshot(
      people: [_person('filtered-feed')],
      hasMore: false,
      cachedAt: DateTime.now().toUtc(),
    ),
  );
}

class _LateNearbyResultRepository extends MockNearbyRepository {
  final _refresh = Completer<NearbyCacheSnapshot>();

  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) =>
      _refresh.future;

  void completeRefresh() => _refresh.complete(
    NearbyCacheSnapshot(
      people: [_person('late-result')],
      hasMore: false,
      cachedAt: DateTime.now().toUtc(),
    ),
  );
}

class _FakeLocationRepository implements ILocationRepository {
  _FakeLocationRepository({
    required this.refreshResult,
    this.hasCachedLocation = true,
  });

  final TrackedLocationRefreshResult refreshResult;
  final bool hasCachedLocation;

  @override
  Future<CachedTrackedLocation?> getCachedCurrentLocation({
    Duration maxAge = const Duration(hours: 24),
  }) async => hasCachedLocation
      ? CachedTrackedLocation(
          latitude: 55,
          longitude: 37,
          updatedAt: DateTime.now().toUtc(),
        )
      : null;

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocation(
    String userId, {
    bool forcePublish = false,
  }) async => refreshResult;

  @override
  Future<Position> getCurrentPosition() => throw UnimplementedError();

  @override
  Future<TrackedLocationRefreshResult> refreshTrackedLocationWithPermission(
    String userId, {
    bool forcePublish = false,
  }) => refreshTrackedLocation(userId, forcePublish: forcePublish);

  @override
  Future<LocationAccessStatus> getLocationAccessStatus() async =>
      LocationAccessStatus.granted;

  @override
  Future<LocationAccessStatus> requestLocationAccess() async =>
      LocationAccessStatus.granted;

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;
}

NearbyPerson _person(String id) => NearbyPerson(
  id: id,
  username: id,
  displayName: id,
  activeUntil: DateTime.now().toUtc().add(const Duration(days: 1)),
);

NearbyCacheSnapshot _snapshot(String id) => NearbyCacheSnapshot(
  people: [_person(id)],
  hasMore: true,
  cachedAt: DateTime.now().toUtc(),
);

class _ManyRequestsRepository extends MockNearbyRepository {
  final requests = <Completer<NearbyCacheSnapshot>>[];
  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) {
    final request = Completer<NearbyCacheSnapshot>();
    requests.add(request);
    return request.future;
  }
}

class _RacingFeedRepository extends MockNearbyRepository {
  final head = Completer<NearbyCacheSnapshot>();
  final page = Completer<NearbyCacheSnapshot?>();
  @override
  Future<NearbyCacheSnapshot?> getCachedFeed(NearbyFilters filters) async =>
      _snapshot('cached');
  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) => head.future;
  @override
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters) => page.future;
}

class _SuccessfulFeedRepository extends MockNearbyRepository {
  int pageCalls = 0;
  @override
  Future<NearbyCacheSnapshot?> getCachedFeed(NearbyFilters filters) async =>
      _snapshot('cached');
  @override
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters) async =>
      _snapshot('cached');
  @override
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters) async {
    pageCalls++;
    return _snapshot('cached');
  }
}

class _NullPageRepository extends _SuccessfulFeedRepository {
  @override
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters) async => null;
}

class _FailedPageRepository extends _SuccessfulFeedRepository {
  _FailedPageRepository(this.quota);
  final bool quota;
  @override
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters) async {
    pageCalls++;
    if (quota) throw const PostgrestException(message: 'nearby_rate_limited');
    throw StateError('offline');
  }
}

class _FailingVisibilitySettings extends MockSettingsRepository {
  @override
  Future<SearchPrivacySettings?> readCachedSearchPrivacySettings() async =>
      const SearchPrivacySettings(nearbyVisible: false);
  @override
  Future<SearchPrivacySettings> refreshSearchPrivacySettings() async =>
      const SearchPrivacySettings(nearbyVisible: false);
  @override
  Stream<bool> watchNearbyVisibility() => const Stream.empty();
  @override
  Future<SearchPrivacySettings> updateSearchPrivacySetting(
    SearchPrivacySettingKey key,
    bool value,
  ) async => throw StateError('offline');
}

class _UncachedHiddenSettings extends MockSettingsRepository {
  int reads = 0;
  @override
  Future<SearchPrivacySettings?> readCachedSearchPrivacySettings() async =>
      null;
  @override
  Future<SearchPrivacySettings> refreshSearchPrivacySettings() async {
    reads++;
    return const SearchPrivacySettings(nearbyVisible: false);
  }
}
