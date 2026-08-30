import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

enum LocationVisibilityStatus { initial, loading, ready, failure }

enum LocationVisibilityFeedback { success, failure }

class _LoadResult<T> {
  const _LoadResult.value(this.value) : error = null;
  const _LoadResult.error(this.error) : value = null;

  final T? value;
  final Object? error;
}

class LocationVisibilityState extends Equatable {
  const LocationVisibilityState({
    this.status = LocationVisibilityStatus.initial,
    this.settings,
    this.excludedFriendIds = const {},
    this.isSaving = false,
    this.feedback,
    this.feedbackId = 0,
  });

  final LocationVisibilityStatus status;
  final SearchPrivacySettings? settings;
  final Set<String> excludedFriendIds;
  final bool isSaving;
  final LocationVisibilityFeedback? feedback;
  final int feedbackId;

  LocationVisibilityState copyWith({
    LocationVisibilityStatus? status,
    SearchPrivacySettings? settings,
    Set<String>? excludedFriendIds,
    bool? isSaving,
    LocationVisibilityFeedback? feedback,
    bool clearFeedback = false,
    int? feedbackId,
  }) => LocationVisibilityState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    excludedFriendIds: excludedFriendIds ?? this.excludedFriendIds,
    isSaving: isSaving ?? this.isSaving,
    feedback: clearFeedback ? null : feedback ?? this.feedback,
    feedbackId: feedbackId ?? this.feedbackId,
  );

  @override
  List<Object?> get props => [
    status,
    settings,
    excludedFriendIds,
    isSaving,
    feedback,
    feedbackId,
  ];
}

class LocationVisibilityCubit extends Cubit<LocationVisibilityState> {
  LocationVisibilityCubit({required ISettingsRepository repository})
    : _repository = repository,
      super(const LocationVisibilityState());

  final ISettingsRepository _repository;
  SearchPrivacySettings? _confirmedSettings;
  Set<String> _confirmedExclusions = const {};
  int _writeGeneration = 0;

  Future<void> load() async {
    if (state.status == LocationVisibilityStatus.loading || state.isSaving) {
      return;
    }
    emit(
      state.copyWith(
        status: LocationVisibilityStatus.loading,
        clearFeedback: true,
      ),
    );
    final cached = await Future.wait([
      _capture(() => _repository.readCachedSearchPrivacySettings()),
      _capture(() => _repository.readCachedPreciseLocationExclusions()),
    ]);
    final cachedSettings = cached[0].value as SearchPrivacySettings?;
    final cachedExclusions =
        cached[1].value as Set<String>? ?? const <String>{};
    if (cachedSettings != null && !isClosed) {
      _confirmedSettings = cachedSettings;
      _confirmedExclusions = cachedExclusions;
      emit(
        state.copyWith(
          status: LocationVisibilityStatus.ready,
          settings: cachedSettings,
          excludedFriendIds: cachedExclusions,
          isSaving: false,
        ),
      );
    }
    final refreshGeneration = _writeGeneration;
    final refreshed = await Future.wait([
      _capture(() => _repository.refreshSearchPrivacySettings()),
      _capture(() => _repository.refreshPreciseLocationExclusions()),
    ]);
    if (isClosed || refreshGeneration != _writeGeneration) {
      return;
    }
    final refreshedSettings = refreshed[0].value as SearchPrivacySettings?;
    final refreshedExclusions = refreshed[1].value as Set<String>?;
    if (refreshedSettings != null) {
      _confirmedSettings = refreshedSettings;
    }
    if (refreshedExclusions != null) {
      _confirmedExclusions = refreshedExclusions;
    }
    if (_confirmedSettings != null) {
      emit(
        state.copyWith(
          status: LocationVisibilityStatus.ready,
          settings: _confirmedSettings,
          excludedFriendIds: _confirmedExclusions,
          isSaving: false,
        ),
      );
      return;
    }
    if (cachedSettings == null) {
      emit(
        state.copyWith(
          status: LocationVisibilityStatus.failure,
          isSaving: false,
        ),
      );
    }
  }

  void setGlobal({bool? sharePreciseLocation, bool? shareDistance}) {
    final confirmed = _confirmedSettings;
    if (state.status != LocationVisibilityStatus.ready ||
        state.isSaving ||
        confirmed == null) {
      return;
    }
    final desired = confirmed.copyWith(
      sharePreciseLocation: sharePreciseLocation,
      shareDistance: shareDistance,
    );
    if (desired == confirmed) {
      return;
    }
    _writeGeneration++;
    emit(
      state.copyWith(settings: desired, isSaving: true, clearFeedback: true),
    );
    unawaited(_saveSettings(desired, confirmed));
  }

  void setFriendExcluded(String friendUserId, {required bool excluded}) {
    if (state.status != LocationVisibilityStatus.ready || state.isSaving) {
      return;
    }
    final id = friendUserId.trim();
    if (id.isEmpty || state.excludedFriendIds.contains(id) == excluded) {
      return;
    }
    final desired = Set<String>.from(_confirmedExclusions);
    if (excluded) {
      desired.add(id);
    } else {
      desired.remove(id);
    }
    _writeGeneration++;
    emit(
      state.copyWith(
        excludedFriendIds: desired,
        isSaving: true,
        clearFeedback: true,
      ),
    );
    unawaited(_saveExclusions(id, excluded, _confirmedExclusions));
  }

  Future<void> _saveSettings(
    SearchPrivacySettings desired,
    SearchPrivacySettings rollback,
  ) async {
    try {
      final updated = await _repository.updateLocationVisibility(
        sharePreciseLocation: desired.sharePreciseLocation,
        shareDistance: desired.shareDistance,
      );
      if (isClosed) return;
      _confirmedSettings = updated;
      emit(
        state.copyWith(
          settings: updated,
          isSaving: false,
          feedback: LocationVisibilityFeedback.success,
          feedbackId: state.feedbackId + 1,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      _confirmedSettings = rollback;
      emit(
        state.copyWith(
          settings: rollback,
          isSaving: false,
          feedback: LocationVisibilityFeedback.failure,
          feedbackId: state.feedbackId + 1,
        ),
      );
    }
  }

  Future<void> _saveExclusions(
    String friendUserId,
    bool excluded,
    Set<String> rollback,
  ) async {
    try {
      final updated = await _repository.setPreciseLocationExcluded(
        friendUserId,
        excluded: excluded,
      );
      if (isClosed) return;
      _confirmedExclusions = updated;
      emit(
        state.copyWith(
          excludedFriendIds: updated,
          isSaving: false,
          feedback: LocationVisibilityFeedback.success,
          feedbackId: state.feedbackId + 1,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      _confirmedExclusions = rollback;
      emit(
        state.copyWith(
          excludedFriendIds: rollback,
          isSaving: false,
          feedback: LocationVisibilityFeedback.failure,
          feedbackId: state.feedbackId + 1,
        ),
      );
    }
  }

  Future<_LoadResult<T>> _capture<T>(Future<T> Function() operation) async {
    try {
      return _LoadResult.value(await operation());
    } catch (error) {
      return _LoadResult.error(error);
    }
  }
}
