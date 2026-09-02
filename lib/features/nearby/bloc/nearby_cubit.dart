import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/location_tracking_coordinator.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/nearby/bloc/nearby_state.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_location_repository.dart';
import 'package:yap_chat/repositories/nearby/nearby.dart';

class NearbyCubit extends Cubit<NearbyState> {
  NearbyCubit({
    required INearbyRepository repository,
    required ILocationRepository locationRepository,
    required LocationTrackingCoordinator locationTrackingCoordinator,
    required AccountSessionController accountSessionController,
  }) : _repository = repository,
       _locationRepository = locationRepository,
       _locationTrackingCoordinator = locationTrackingCoordinator,
       _accountSessionController = accountSessionController,
       super(const NearbyState());

  final INearbyRepository _repository;
  final ILocationRepository _locationRepository;
  final LocationTrackingCoordinator _locationTrackingCoordinator;
  final AccountSessionController _accountSessionController;
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
        emit(state.copyWith(rateLimitFeedbackId: state.rateLimitFeedbackId + 1));
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
      emit(state.copyWith(
        status: NearbyStatus.ready,
        filters: filters,
        people: cached?.people ?? const [],
        hasMore: cached?.hasMore ?? false,
        clearLocationIssue: true,
      ));
      final ownLocation = await _locationRepository.getCachedCurrentLocation(
        maxAge: const Duration(hours: 12),
      );
      if (ownLocation == null) {
        _requireLocation();
        return;
      }
      // A populated snapshot remains untouched until an explicit pull to
      // refresh. A first visit has no snapshot, so it is loaded once.
      if (cached == null) await refresh();
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
      await _refresh(force: true);
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
        emit(state.copyWith(
          status: NearbyStatus.ready,
          isRefreshing: false,
          clearLocationIssue: true,
        ));
      }
    }
  }

  Future<void> refresh() => _refresh(force: false);

  Future<void> _refresh({required bool force}) {
    final active = _feedRefresh;
    if (active != null) return active;
    final future = _performRefresh(force: force);
    _feedRefresh = future;
    return future.whenComplete(() => _feedRefresh = null);
  }

  Future<void> _performRefresh({required bool force}) async {
    if (state.status == NearbyStatus.locationRequired && !force) return;
    if (!_tryConsumeFeedRequest()) return;
    if (!isClosed) emit(state.copyWith(isRefreshing: true));
    try {
      final snapshot = await _repository.refreshFeed(state.filters);
      if (!isClosed) {
        emit(state.copyWith(
          status: NearbyStatus.ready,
          people: snapshot.people,
          hasMore: snapshot.hasMore,
          isRefreshing: false,
          clearLocationIssue: true,
        ));
      }
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(status: NearbyStatus.failure, isRefreshing: false));
      }
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.status != NearbyStatus.ready) {
      return;
    }
    if (!_tryConsumeFeedRequest()) return;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final snapshot = await _repository.loadMore(state.filters);
      if (!isClosed && snapshot != null) {
        emit(state.copyWith(
          people: snapshot.people,
          hasMore: snapshot.hasMore,
          isLoadingMore: false,
        ));
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
    emit(state.copyWith(
      status: NearbyStatus.ready,
      filters: normalized,
      people: cached?.people ?? const [],
      hasMore: cached?.hasMore ?? false,
      clearLocationIssue: true,
    ));
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

  void _requireLocation([NearbyLocationIssue? issue]) {
    if (isClosed) return;
    emit(state.copyWith(
      status: NearbyStatus.locationRequired,
      isRefreshing: false,
      locationIssue: issue,
      locationFeedbackId: issue == null
          ? state.locationFeedbackId
          : state.locationFeedbackId + 1,
    ));
  }
}
