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
    this.settings = const SearchPrivacySettings(),
    this.isSaving = false,
    this.error,
    this.feedback,
    this.feedbackId = 0,
  });

  final PrivacySettingsStatus status;
  final SearchPrivacySettings settings;
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

enum PrivacySettingKey { username, phone, name }

class PrivacySettingsCubit extends Cubit<PrivacySettingsState> {
  PrivacySettingsCubit({required ISettingsRepository repository})
    : _repository = repository,
      super(const PrivacySettingsState());

  static const _writeDebounce = Duration(milliseconds: 350);
  static const _minimumRequestGap = Duration(milliseconds: 350);

  final ISettingsRepository _repository;
  SearchPrivacySettings? _confirmed;
  SearchPrivacySettings? _desired;
  Timer? _debounce;
  Future<void>? _worker;

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
    try {
      final settings = await _repository.getSearchPrivacySettings();
      if (isClosed) return;
      _confirmed = settings;
      _desired = null;
      emit(
        state.copyWith(
          status: PrivacySettingsStatus.ready,
          settings: settings,
          isSaving: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (!isClosed) {
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

  void setValue(PrivacySettingKey key, bool value) {
    if (state.status != PrivacySettingsStatus.ready) return;
    final next = (_desired ?? _confirmed ?? state.settings);
    final desired = switch (key) {
      PrivacySettingKey.username => next.copyWith(searchByUsername: value),
      PrivacySettingKey.phone => next.copyWith(searchByPhone: value),
      PrivacySettingKey.name => next.copyWith(searchByName: value),
    };
    if (desired == (_desired ?? _confirmed)) return;
    _desired = desired;
    emit(
      state.copyWith(
        settings: desired,
        isSaving: true,
        clearError: true,
        clearFeedback: true,
      ),
    );
    _debounce?.cancel();
    _debounce = Timer(_writeDebounce, _startWorker);
  }

  void _startWorker() {
    if (isClosed || _worker != null) return;
    _worker = _drainWrites();
    unawaited(_worker!.whenComplete(() => _worker = null));
  }

  Future<void> _drainWrites() async {
    while (!isClosed) {
      final target = _desired;
      final confirmed = _confirmed;
      if (target == null || target == confirmed) {
        if (!isClosed && state.isSaving) {
          emit(state.copyWith(isSaving: false, settings: confirmed));
        }
        return;
      }
      try {
        final updated = await _repository.updateSearchPrivacySettings(target);
        if (isClosed) return;
        _confirmed = updated;
        if (_desired == target) {
          _desired = null;
          emit(
            state.copyWith(
              settings: updated,
              isSaving: false,
              clearError: true,
              feedback: PrivacySettingsFeedback.success,
              feedbackId: state.feedbackId + 1,
            ),
          );
          return;
        }
        emit(state.copyWith(settings: _desired!, isSaving: true));
        await Future<void>.delayed(_minimumRequestGap);
      } catch (error) {
        if (isClosed) return;
        _desired = null;
        emit(
          state.copyWith(
            settings: _confirmed ?? state.settings,
            isSaving: false,
            error: error,
            feedback: PrivacySettingsFeedback.failure,
            feedbackId: state.feedbackId + 1,
          ),
        );
        return;
      }
    }
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
