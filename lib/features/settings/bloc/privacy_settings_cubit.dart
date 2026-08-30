import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

enum PrivacySettingsStatus { initial, loading, ready, failure }

enum PrivacySettingsFeedback { success, failure }

class PrivacySettingsState extends Equatable {
  const PrivacySettingsState({
    this.status = PrivacySettingsStatus.initial,
    this.settings,
    this.isSaving = false,
    this.error,
    this.feedback,
    this.feedbackId = 0,
  });

  final PrivacySettingsStatus status;
  final SearchPrivacySettings? settings;
  final bool isSaving;
  final Object? error;
  final PrivacySettingsFeedback? feedback;
  final int feedbackId;

  PrivacySettingsState copyWith({
    PrivacySettingsStatus? status,
    SearchPrivacySettings? settings,
    bool? isSaving,
    Object? error,
    bool clearError = false,
    PrivacySettingsFeedback? feedback,
    bool clearFeedback = false,
    int? feedbackId,
  }) => PrivacySettingsState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    isSaving: isSaving ?? this.isSaving,
    error: clearError ? null : error ?? this.error,
    feedback: clearFeedback ? null : feedback ?? this.feedback,
    feedbackId: feedbackId ?? this.feedbackId,
  );

  @override
  List<Object?> get props => [
    status,
    settings,
    isSaving,
    error,
    feedback,
    feedbackId,
  ];
}

class PrivacySettingsCubit extends Cubit<PrivacySettingsState> {
  PrivacySettingsCubit({required ISettingsRepository repository})
    : _repository = repository,
      super(const PrivacySettingsState());

  final ISettingsRepository _repository;
  SearchPrivacySettings? _confirmed;
  int _writeGeneration = 0;

  Future<void> load() async {
    if (state.status == PrivacySettingsStatus.loading || state.isSaving) {
      return;
    }
    emit(
      state.copyWith(
        status: PrivacySettingsStatus.loading,
        clearError: true,
        clearFeedback: true,
      ),
    );
    SearchPrivacySettings? cached;
    try {
      cached = await _repository.readCachedSearchPrivacySettings();
    } catch (_) {
      // A server refresh remains possible even if the local database failed.
    }
    if (cached != null && !isClosed) {
      _confirmed = cached;
      emit(
        state.copyWith(
          status: PrivacySettingsStatus.ready,
          settings: cached,
          isSaving: false,
          clearError: true,
        ),
      );
    }
    final refreshWriteGeneration = _writeGeneration;
    try {
      final settings = await _repository.refreshSearchPrivacySettings();
      if (isClosed) return;
      // A cached page stays interactive. Do not let an older background read
      // replace the result of a setting write that started after that read.
      if (refreshWriteGeneration != _writeGeneration) return;
      _confirmed = settings;
      emit(
        state.copyWith(
          status: PrivacySettingsStatus.ready,
          settings: settings,
          isSaving: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (!isClosed && cached == null) {
        emit(
          state.copyWith(
            status: PrivacySettingsStatus.failure,
            isSaving: false,
            error: error,
          ),
        );
      }
    }
  }

  void setValue(SearchPrivacySettingKey key, bool value) {
    final confirmed = _confirmed;
    if (state.status != PrivacySettingsStatus.ready ||
        state.isSaving ||
        confirmed == null ||
        confirmed.valueFor(key) == value) {
      return;
    }
    final desired = confirmed.withValue(key, value);
    _writeGeneration++;
    emit(
      state.copyWith(
        settings: desired,
        isSaving: true,
        clearError: true,
        clearFeedback: true,
      ),
    );
    unawaited(_save(key, value, confirmed));
  }

  void setLastSeenVisibility(LastSeenVisibility visibility) {
    final confirmed = _confirmed;
    if (state.status != PrivacySettingsStatus.ready ||
        state.isSaving ||
        confirmed == null ||
        confirmed.lastSeenVisibility == visibility) {
      return;
    }
    _writeGeneration++;
    emit(
      state.copyWith(
        settings: confirmed.copyWith(lastSeenVisibility: visibility),
        isSaving: true,
        clearError: true,
        clearFeedback: true,
      ),
    );
    unawaited(_saveLastSeenVisibility(visibility, confirmed));
  }

  Future<void> _save(
    SearchPrivacySettingKey key,
    bool value,
    SearchPrivacySettings rollbackValue,
  ) async {
    try {
      final updated = await _repository.updateSearchPrivacySetting(key, value);
      if (isClosed) return;
      _confirmed = updated;
      emit(
        state.copyWith(
          settings: updated,
          isSaving: false,
          clearError: true,
          feedback: PrivacySettingsFeedback.success,
          feedbackId: state.feedbackId + 1,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      _confirmed = rollbackValue;
      emit(
        state.copyWith(
          settings: rollbackValue,
          isSaving: false,
          error: error,
          feedback: PrivacySettingsFeedback.failure,
          feedbackId: state.feedbackId + 1,
        ),
      );
    }
  }

  Future<void> _saveLastSeenVisibility(
    LastSeenVisibility visibility,
    SearchPrivacySettings rollbackValue,
  ) async {
    try {
      final updated = await _repository.updateLastSeenVisibility(visibility);
      if (isClosed) return;
      _confirmed = updated;
      emit(
        state.copyWith(
          settings: updated,
          isSaving: false,
          clearError: true,
          feedback: PrivacySettingsFeedback.success,
          feedbackId: state.feedbackId + 1,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      _confirmed = rollbackValue;
      emit(
        state.copyWith(
          settings: rollbackValue,
          isSaving: false,
          error: error,
          feedback: PrivacySettingsFeedback.failure,
          feedbackId: state.feedbackId + 1,
        ),
      );
    }
  }
}
