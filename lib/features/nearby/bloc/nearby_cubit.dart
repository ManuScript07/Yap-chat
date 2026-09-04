import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yap_chat/app/location_tracking_coordinator.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/nearby/bloc/nearby_state.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_location_repository.dart';
import 'package:yap_chat/repositories/blocks/abstract_blocklist_repository.dart';
import 'package:yap_chat/repositories/friends/abstract_friends_repository.dart';
import 'package:yap_chat/repositories/nearby/nearby.dart';

class NearbyCubit extends Cubit<NearbyState> {
  NearbyCubit({
    required INearbyRepository repository,
    required ILocationRepository locationRepository,
    required LocationTrackingCoordinator locationTrackingCoordinator,
    required AccountSessionController accountSessionController,
    required IBlocklistRepository blocklistRepository,
    required IProfileFriendsRepository profileFriendsRepository,
    this.refreshTimeout = defaultRefreshTimeout,
  }) : _repository = repository,
       _locationRepository = locationRepository,
       _locationTrackingCoordinator = locationTrackingCoordinator,
       _accountSessionController = accountSessionController,
       _profileFriendsRepository = profileFriendsRepository,
       super(const NearbyState()) {
    _blocklistSubscription = blocklistRepository.watchBlockedUserIds().listen(
      (userIds) => unawaited(_removeNewlyBlockedPeople(userIds)),
    );
  }

  final INearbyRepository _repository;
  final ILocationRepository _locationRepository;
  final LocationTrackingCoordinator _locationTrackingCoordinator;
  final AccountSessionController _accountSessionController;
  final IProfileFriendsRepository _profileFriendsRepository;
  static const defaultRefreshTimeout = Duration(seconds: 12);
  final Duration refreshTimeout;
  late final StreamSubscription<Set<String>> _blocklistSubscription;
  Set<String> _blockedUserIds = const {};
  Future<void>? _initialization;
  Future<void>? _locationRefresh;
  Future<void>? _feedRefresh;
  final List<DateTime> _feedRequestStarts = [];

  bool _tryConsumeFeedRequest() {
    final now = DateTime.now().toUtc();
    _feedRequestStarts.removeWhere(
      (startedAt) => now.difference(startedAt) >= const Duration(minutes: 1),
    );
    if (_feedRequestStarts.length >= 20) {
      if (!isClosed) {
        emit(
          state.copyWith(rateLimitFeedbackId: state.rateLimitFeedbackId + 1),
        );
      }
      return false;
    }
    _feedRequestStarts.add(now);
    return true;
  }

  Future<void> initialize() {
    final active = _initialization;
    if (active != null) return active;
    final future = _initialize();
    _initialization = future;
    return future;
  }

  Future<void> _initialize() async {
    emit(state.copyWith(status: NearbyStatus.loading));
    try {
      final filters = await _repository.getFilters();
      final cached = await _repository.getCachedFeed(filters);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: NearbyStatus.ready,
          filters: filters,
          people: cached?.people ?? const [],
          hasMore: cached?.hasMore ?? false,
          clearLocationIssue: true,
        ),
      );
      final ownLocation = await _locationRepository.getCachedCurrentLocation(
        maxAge: const Duration(hours: 12),
      );
      final hasFreshLocationConfirmation =
          _hasFreshServerLocationConfirmation(cached) ||
          await _repository.hasFreshLocationConfirmation();
      if (ownLocation == null && !hasFreshLocationConfirmation) {
        // A cold start can arrive here while the authenticated application's
        // foreground refresh is still publishing the same point. Let the
        // shared contour settle first, so a location acquired here is also
        // used by friends and distance calculations.
        final refreshResult = await _locationTrackingCoordinator
            .refreshSilently();
        if (isClosed) return;
        if (refreshResult == TrackedLocationRefreshResult.updated &&
            !await _invalidateDistancesAfterLocationUpdate()) {
          return;
        }
        // A local publication timestamp is an optimization, not the source
        // of truth. It may be absent after an unchanged server write even
        // though `user_locations.updated_at` is still recent. In that case
        // the feed RPC is the single authoritative 12-hour check. It also
        // preserves the required blur when that RPC says no current location
        // exists or when it cannot be reached.
        await _refresh(
          force: true,
          refreshOwnLocation: false,
          requireLocationOnFailure: true,
        );
        return;
      }
      // A populated snapshot remains untouched until an explicit pull to
      // refresh. A first visit has no snapshot, so it is loaded once.
      if (cached == null || (cached.people.isEmpty && cached.hasMore)) {
        await refresh();
      }
    } catch (_) {
      if (!isClosed) emit(state.copyWith(status: NearbyStatus.failure));
    }
  }

  Future<void> requestLocation() {
    final active = _locationRefresh;
    if (active != null) return active;
    final future = _requestLocation();
    _locationRefresh = future;
    return future.whenComplete(() => _locationRefresh = null);
  }

  Future<void> _requestLocation() async {
    if (isClosed) return;
    emit(state.copyWith(isRefreshing: true, clearLocationIssue: true));
    try {
      final scope = _accountSessionController.capture();
      final result = await _locationTrackingCoordinator.refreshWithPermission();
      _accountSessionController.ensureCurrent(scope);
      if (result == TrackedLocationRefreshResult.unavailable) {
        _requireLocation(NearbyLocationIssue.unavailable);
        return;
      }
      if (result == TrackedLocationRefreshResult.updated &&
          !await _invalidateDistancesAfterLocationUpdate()) {
        return;
      }
      await _refresh(force: true, refreshOwnLocation: false);
    } on LocationServiceDisabledFailure {
      _requireLocation(NearbyLocationIssue.serviceDisabled);
    } on LocationPermissionPermanentlyDeniedFailure {
      _requireLocation(NearbyLocationIssue.permanentlyDenied);
    } on LocationPermissionDeniedFailure {
      _requireLocation(NearbyLocationIssue.denied);
    } on StaleAccountSessionException {
      return;
    } catch (_) {
      final ownLocation = await _locationRepository.getCachedCurrentLocation(
        maxAge: const Duration(hours: 12),
      );
      if (isClosed) return;
      if (ownLocation == null) {
        _requireLocation(NearbyLocationIssue.unavailable);
      } else {
        // Publishing succeeded but the following feed refresh may have lost
        // connectivity. The server still has a current own location, so a
        // retained snapshot is safe to show until the user pulls to refresh.
        emit(
          state.copyWith(
            status: NearbyStatus.ready,
            isRefreshing: false,
            clearLocationIssue: true,
          ),
        );
      }
    }
  }

  /// A user-initiated feed refresh first silently synchronizes the shared
  /// location. This keeps nearby ordering, friend locations and server-side
  /// distance calculations on the same point without reopening OS UI.
  Future<void> refresh() => _refresh(force: false, refreshOwnLocation: true);

  Future<void> _refresh({
    required bool force,
    bool refreshOwnLocation = false,
    bool requireLocationOnFailure = false,
  }) {
    final active = _feedRefresh;
    if (active != null) return active;
    final future = _performRefresh(
      force: force,
      refreshOwnLocation: refreshOwnLocation,
      requireLocationOnFailure: requireLocationOnFailure,
    );
    _feedRefresh = future;
    return future.whenComplete(() => _feedRefresh = null);
  }

  Future<void> _performRefresh({
    required bool force,
    required bool refreshOwnLocation,
    required bool requireLocationOnFailure,
  }) async {
    if (state.status == NearbyStatus.locationRequired && !force) return;
    if (!_tryConsumeFeedRequest()) return;
    if (!isClosed) emit(state.copyWith(isRefreshing: true));
    try {
      await _refreshFeedAndLocation(
        refreshOwnLocation: refreshOwnLocation,
      ).timeout(refreshTimeout);
    } catch (error) {
      if (!isClosed) {
        if (_isNearbyRateLimitedError(error)) {
          emit(
            state.copyWith(
              status: state.people.isEmpty
                  ? NearbyStatus.failure
                  : NearbyStatus.ready,
              isRefreshing: false,
              rateLimitFeedbackId: state.rateLimitFeedbackId + 1,
            ),
          );
        } else if (requireLocationOnFailure ||
            _isLocationRequiredError(error)) {
          _requireLocation();
        } else {
          emit(
            state.copyWith(status: NearbyStatus.failure, isRefreshing: false),
          );
        }
      }
    }
  }

  Future<void> _refreshFeedAndLocation({
    required bool refreshOwnLocation,
  }) async {
    if (refreshOwnLocation) {
      final locationResult = await _locationTrackingCoordinator
          .refreshSilently();
      if (locationResult == TrackedLocationRefreshResult.updated) {
        if (!await _invalidateDistancesAfterLocationUpdate()) return;
      }
      if (isClosed) return;
    }
    final snapshot = await _repository.refreshFeed(state.filters);
    if (!isClosed) {
      emit(
        state.copyWith(
          status: NearbyStatus.ready,
          people: snapshot.people,
          hasMore: snapshot.hasMore,
          isRefreshing: false,
          clearLocationIssue: true,
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore ||
        !state.hasMore ||
        state.status != NearbyStatus.ready) {
      return;
    }
    if (!_tryConsumeFeedRequest()) return;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final snapshot = await _repository.loadMore(state.filters);
      if (!isClosed && snapshot != null) {
        emit(
          state.copyWith(
            people: snapshot.people,
            hasMore: snapshot.hasMore,
            isLoadingMore: false,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) emit(state.copyWith(isLoadingMore: false));
    }
  }

  Future<void> applyFilters(NearbyFilters filters) async {
    final normalized = filters.normalized();
    if (normalized == state.filters) return;
    await _repository.saveFilters(normalized);
    final cached = await _repository.getCachedFeed(normalized);
    if (isClosed) return;
    emit(
      state.copyWith(
        status: NearbyStatus.ready,
        filters: normalized,
        people: cached?.people ?? const [],
        hasMore: cached?.hasMore ?? false,
        clearLocationIssue: true,
      ),
    );
    final ownLocation = await _locationRepository.getCachedCurrentLocation(
      maxAge: const Duration(hours: 12),
    );
    if (ownLocation == null) {
      _requireLocation();
      return;
    }
    // Applying a filter is an explicit user refresh and therefore may contact
    // the server; merely changing location never invalidates stored pages.
    await refresh();
  }

  Future<void> _removeNewlyBlockedPeople(Set<String> userIds) async {
    final newlyBlocked = userIds.difference(_blockedUserIds);
    _blockedUserIds = Set.unmodifiable(userIds);
    if (newlyBlocked.isEmpty) return;
    if (!isClosed) {
      emit(
        state.copyWith(
          people: state.people
              .where((person) => !newlyBlocked.contains(person.id))
              .toList(growable: false),
        ),
      );
    }
    try {
      await _repository.removeCachedPeople(newlyBlocked);
    } on StaleAccountSessionException {
      // A logout/account switch owns cache cleanup and invalidates this work.
    } catch (_) {
      // The in-memory list is already protected; an optional cache cleanup
      // failure must not affect the local block.
    }
  }

  Future<bool> _invalidateDistancesAfterLocationUpdate() async {
    try {
      await _profileFriendsRepository.clearCachedUserDistances();
      return true;
    } on StaleAccountSessionException {
      return false;
    } catch (_) {
      // A cache cleanup must not make an otherwise valid feed refresh fail.
      // The ten-minute distance TTL remains a safe fallback.
      return true;
    }
  }

  bool _hasFreshServerLocationConfirmation(NearbyCacheSnapshot? snapshot) {
    if (snapshot == null) return false;
    final age = DateTime.now().toUtc().difference(snapshot.cachedAt.toUtc());
    return !age.isNegative && age < const Duration(hours: 12);
  }

  bool _isLocationRequiredError(Object error) =>
      error is PostgrestException &&
      error.message.contains('nearby_location_required');

  bool _isNearbyRateLimitedError(Object error) =>
      error is PostgrestException &&
      error.message.contains('nearby_rate_limited');

  @override
  Future<void> close() async {
    await _blocklistSubscription.cancel();
    return super.close();
  }

  void _requireLocation([NearbyLocationIssue? issue]) {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: NearbyStatus.locationRequired,
        isRefreshing: false,
        locationIssue: issue,
        locationFeedbackId: issue == null
            ? state.locationFeedbackId
            : state.locationFeedbackId + 1,
      ),
    );
  }
}
