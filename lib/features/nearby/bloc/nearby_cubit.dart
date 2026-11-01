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
    DateTime Function()? clock,
  }) : _repository = repository,
       _locationRepository = locationRepository,
       _locationTrackingCoordinator = locationTrackingCoordinator,
       _accountSessionController = accountSessionController,
       _profileFriendsRepository = profileFriendsRepository,
       _clock = clock ?? DateTime.now,
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
  final DateTime Function() _clock;
  late final StreamSubscription<Set<String>> _blocklistSubscription;
  Set<String> _blockedUserIds = const {};
  Future<void>? _initialization;
  Future<void>? _locationRefresh;
  Future<void>? _feedRefresh;
  final List<DateTime> _feedRequestStarts = [];
  var _queryRevision = 0;
  var _refreshOperationId = 0;
  DateTime? _feedBlockedUntil;
  DateTime? _paginationRetryAt;
  bool _needsHeadRefresh = false;
  bool get needsHeadRefresh => _needsHeadRefresh;
  static const _maximumFeedRequestsPerMinute = 8;

  /// A denied page may be retried once when the quota window ends. Network
  /// failures use gesture-driven backoff and must not start an automatic poll.
  Duration? get paginationQuotaRetryDelay {
    final until = _feedBlockedUntil;
    if (until == null) return null;
    final remaining = until.difference(_clock().toUtc());
    return remaining.isNegative || remaining == Duration.zero
        ? null
        : remaining;
  }

  bool _tryConsumeFeedRequest() {
    final now = _clock().toUtc();
    if (_feedBlockedUntil case final until? when now.isBefore(until)) {
      return false;
    }
    _feedRequestStarts.removeWhere(
      (startedAt) => now.difference(startedAt) >= const Duration(minutes: 1),
    );
    if (_feedRequestStarts.length >= _maximumFeedRequestsPerMinute) {
      _feedBlockedUntil = _feedRequestStarts.first.add(
        const Duration(minutes: 1),
      );
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
      final ownLocation = await _locationRepository.getCachedCurrentLocation(
        maxAge: const Duration(hours: 12),
      );
      if (isClosed) return;
      if (ownLocation == null) {
        // The persisted publication timestamp is the only offline source of
        // truth. A feed's cache time merely says when people were loaded; it
        // must never extend the twelve-hour lifetime of the user's point.
        _requireLocation(
          filters: filters,
          people: cached?.people,
          hasMore: cached?.hasMore,
        );
        return;
      }
      emit(
        state.copyWith(
          status: NearbyStatus.ready,
          filters: filters,
          people: cached?.people ?? const [],
          hasMore: cached?.hasMore ?? false,
          clearLocationIssue: true,
        ),
      );
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
        _requireLocation(issue: NearbyLocationIssue.unavailable);
        return;
      }
      if (result == TrackedLocationRefreshResult.updated &&
          !await _invalidateDistancesAfterLocationUpdate()) {
        return;
      }
      await _refresh(force: true, refreshOwnLocation: false);
    } on LocationServiceDisabledFailure {
      _requireLocation(issue: NearbyLocationIssue.serviceDisabled);
    } on LocationPermissionPermanentlyDeniedFailure {
      _requireLocation(issue: NearbyLocationIssue.permanentlyDenied);
    } on LocationPermissionDeniedFailure {
      _requireLocation(issue: NearbyLocationIssue.denied);
    } on StaleAccountSessionException {
      return;
    } catch (_) {
      final ownLocation = await _locationRepository.getCachedCurrentLocation(
        maxAge: const Duration(hours: 12),
      );
      if (isClosed) return;
      if (ownLocation == null) {
        _requireLocation(issue: NearbyLocationIssue.unavailable);
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
    if (isClosed || (state.status == NearbyStatus.locationRequired && !force)) {
      return Future<void>.value();
    }
    if (!_tryConsumeFeedRequest()) {
      _needsHeadRefresh = true;
      if (state.isRefreshing) emit(state.copyWith(isRefreshing: false));
      return Future<void>.value();
    }
    final filters = state.filters;
    _needsHeadRefresh = false;
    final revision = _queryRevision;
    final operationId = ++_refreshOperationId;
    _repository.invalidateFeed(filters);
    _paginationRetryAt = null;
    emit(state.copyWith(isRefreshing: true, isLoadingMore: false));
    final operation = _performRefresh(
      refreshOwnLocation: refreshOwnLocation,
      requireLocationOnFailure: requireLocationOnFailure,
      filters: filters,
      revision: revision,
      operationId: operationId,
    );
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_feedRefresh, tracked)) _feedRefresh = null;
    });
    _feedRefresh = tracked;
    return tracked;
  }

  Future<void> _performRefresh({
    required bool refreshOwnLocation,
    required bool requireLocationOnFailure,
    required NearbyFilters filters,
    required int revision,
    required int operationId,
  }) async {
    try {
      await _refreshFeedAndLocation(
        refreshOwnLocation: refreshOwnLocation,
        filters: filters,
        revision: revision,
        operationId: operationId,
      ).timeout(
        refreshTimeout,
        onTimeout: () => throw const _NearbyRefreshDeadlineExceeded(),
      );
    } catch (error) {
      if (!isClosed && _isCurrentOperation(operationId, revision, filters)) {
        if (_isNearbyRateLimitedError(error)) {
          _needsHeadRefresh = true;
          _feedBlockedUntil = _clock().toUtc().add(const Duration(minutes: 1));
          emit(
            state.copyWith(
              status: NearbyStatus.ready,
              isRefreshing: false,
              rateLimitFeedbackId: state.rateLimitFeedbackId + 1,
            ),
          );
        } else if (error is _NearbyRefreshDeadlineExceeded) {
          // GPS may finish in the shared coordinator, but this completed UI
          // attempt must not replace the list or write a late feed snapshot.
          _repository.invalidateFeed(filters);
          _refreshOperationId++;
          emit(
            state.copyWith(
              status: state.people.isEmpty
                  ? NearbyStatus.failure
                  : NearbyStatus.ready,
              isRefreshing: false,
              isLoadingMore: false,
            ),
          );
        } else if (error is NearbyFeedSupersededException) {
          emit(state.copyWith(isRefreshing: false));
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
    required NearbyFilters filters,
    required int revision,
    required int operationId,
  }) async {
    if (refreshOwnLocation) {
      final locationResult = await _locationTrackingCoordinator
          .refreshSilently();
      if (isClosed || !_isCurrentOperation(operationId, revision, filters)) {
        return;
      }
      if (locationResult == TrackedLocationRefreshResult.updated) {
        if (!await _invalidateDistancesAfterLocationUpdate()) return;
      }
      if (isClosed || !_isCurrentOperation(operationId, revision, filters)) {
        return;
      }
    }
    final snapshot = await _repository.refreshFeed(filters);
    if (!isClosed && _isCurrentOperation(operationId, revision, filters)) {
      emit(
        state.copyWith(
          status: NearbyStatus.ready,
          people: _visiblePeople(snapshot.people),
          hasMore: snapshot.hasMore,
          isRefreshing: false,
          clearLocationIssue: true,
          feedRevision: state.feedRevision + 1,
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (_needsHeadRefresh &&
        !state.isRefreshing &&
        !isClosed &&
        state.status == NearbyStatus.ready) {
      await refresh();
      return;
    }
    if (state.isRefreshing ||
        state.isLoadingMore ||
        state.people.isEmpty ||
        !state.hasMore ||
        state.status != NearbyStatus.ready) {
      return;
    }
    if (_paginationRetryAt case final until?
        when _clock().toUtc().isBefore(until)) {
      return;
    }
    if (!_tryConsumeFeedRequest()) return;
    final filters = state.filters;
    final revision = _queryRevision;
    final operationId = _refreshOperationId;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final snapshot = await _repository.loadMore(filters);
      if (!isClosed && _isCurrentOperation(operationId, revision, filters)) {
        emit(
          state.copyWith(
            people: snapshot == null
                ? state.people
                : _visiblePeople(snapshot.people),
            hasMore: snapshot?.hasMore ?? false,
            isLoadingMore: false,
          ),
        );
      }
    } catch (error) {
      if (!isClosed && _isCurrentOperation(operationId, revision, filters)) {
        if (_isNearbyRateLimitedError(error)) {
          _feedBlockedUntil = _clock().toUtc().add(const Duration(minutes: 1));
        } else if (error is! NearbyFeedSupersededException) {
          _paginationRetryAt = _clock().toUtc().add(const Duration(seconds: 3));
        }
        emit(state.copyWith(isLoadingMore: false));
      }
    }
  }

  Future<void> applyFilters(NearbyFilters filters) async {
    final normalized = filters.normalized();
    if (normalized == state.filters) return;
    _needsHeadRefresh = false;
    final revision = ++_queryRevision;
    _refreshOperationId++;
    _repository.invalidateFeed(state.filters);
    _feedRefresh = null;
    _paginationRetryAt = null;
    // Mark the transition immediately: closing the sheet must not leave a
    // short window in which a pull-to-refresh can start a competing query.
    emit(
      state.copyWith(
        status: NearbyStatus.ready,
        filters: normalized,
        isRefreshing: true,
        isLoadingMore: false,
        clearLocationIssue: true,
      ),
    );
    try {
      await _repository.saveFilters(normalized);
      if (isClosed || revision != _queryRevision) return;
      final cached = await _repository.getCachedFeed(normalized);
      if (isClosed || revision != _queryRevision) return;
      final ownLocation = await _locationRepository.getCachedCurrentLocation(
        maxAge: const Duration(hours: 12),
      );
      if (isClosed || revision != _queryRevision) return;
      if (ownLocation == null) {
        _requireLocation(
          filters: normalized,
          // An absent snapshot for the newly selected filter must not blank a
          // usable feed while its first server query is still pending.
          people: cached?.people ?? state.people,
          hasMore: cached?.hasMore ?? false,
        );
        return;
      }
      emit(
        state.copyWith(
          status: NearbyStatus.ready,
          filters: normalized,
          // Caches are scoped to an exact filter combination. Retain the
          // current list until a missing new snapshot is replaced by a
          // successful server result, rather than flashing an empty state.
          people: cached?.people ?? state.people,
          hasMore: cached?.hasMore ?? false,
          isRefreshing: true,
          isLoadingMore: false,
          clearLocationIssue: true,
        ),
      );
      // Applying a filter is an explicit user refresh and therefore may
      // contact the server; merely changing location never invalidates stored
      // pages.
      if (isClosed ||
          revision != _queryRevision ||
          state.filters != normalized) {
        return;
      }
      await refresh();
    } catch (_) {
      if (!isClosed && revision == _queryRevision) {
        emit(state.copyWith(isRefreshing: false));
      }
    }
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

  bool _isLocationRequiredError(Object error) =>
      error is PostgrestException &&
      error.message.contains('nearby_location_required');

  bool _isNearbyRateLimitedError(Object error) =>
      error is PostgrestException &&
      error.message.contains('nearby_rate_limited');

  bool _isCurrentQuery(int revision, NearbyFilters filters) =>
      revision == _queryRevision && state.filters == filters;

  bool _isCurrentOperation(
    int operationId,
    int revision,
    NearbyFilters filters,
  ) => operationId == _refreshOperationId && _isCurrentQuery(revision, filters);

  List<NearbyPerson> _visiblePeople(List<NearbyPerson> people) => people
      .where((person) => !_blockedUserIds.contains(person.id))
      .toList(growable: false);

  @override
  Future<void> close() async {
    await _blocklistSubscription.cancel();
    return super.close();
  }

  void _requireLocation({
    NearbyLocationIssue? issue,
    NearbyFilters? filters,
    List<NearbyPerson>? people,
    bool? hasMore,
  }) {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: NearbyStatus.locationRequired,
        filters: filters,
        people: people,
        hasMore: hasMore,
        isRefreshing: false,
        locationIssue: issue,
        locationFeedbackId: issue == null
            ? state.locationFeedbackId
            : state.locationFeedbackId + 1,
      ),
    );
  }
}

class _NearbyRefreshDeadlineExceeded implements Exception {
  const _NearbyRefreshDeadlineExceeded();
}
