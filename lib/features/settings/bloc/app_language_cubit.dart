import 'dart:async';
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/settings/abstract_settings_repository.dart';

enum AppLanguageFeedback { success, failure }

class AppLanguageState extends Equatable {
  const AppLanguageState({
    required this.language,
    this.isSaving = false,
    this.feedback,
    this.feedbackId = 0,
  });

  final AppLanguage language;
  final bool isSaving;
  final AppLanguageFeedback? feedback;
  final int feedbackId;

  AppLanguageState copyWith({
    AppLanguage? language,
    bool? isSaving,
    AppLanguageFeedback? feedback,
    bool clearFeedback = false,
    int? feedbackId,
  }) => AppLanguageState(
    language: language ?? this.language,
    isSaving: isSaving ?? this.isSaving,
    feedback: clearFeedback ? null : feedback ?? this.feedback,
    feedbackId: feedbackId ?? this.feedbackId,
  );

  @override
  List<Object?> get props => [language, isSaving, feedback, feedbackId];
}

/// Keeps the Material locale and the persisted account preference in sync.
///
/// A selected value is applied optimistically so the interface immediately
/// reflects the user's action. While the server write is pending the picker is
/// inert; a failed write restores the confirmed language.
class AppLanguageCubit extends Cubit<AppLanguageState> {
  AppLanguageCubit({required ISettingsRepository repository})
    : _repository = repository,
      super(
        AppLanguageState(
          language: AppLanguage.fromSystemLocale(
            PlatformDispatcher.instance.locale,
          ),
        ),
      );

  final ISettingsRepository _repository;
  int _accountGeneration = 0;
  int _writeGeneration = 0;
  AppLanguage? _confirmedLanguage;

  Future<void> setAuthenticatedUser(String? userId) async {
    final generation = ++_accountGeneration;
    _confirmedLanguage = null;
    final systemLanguage = AppLanguage.fromSystemLocale(
      PlatformDispatcher.instance.locale,
    );
    emit(
      AppLanguageState(language: systemLanguage, feedbackId: state.feedbackId),
    );
    if (userId == null || userId.isEmpty) return;

    AppLanguage? cached;
    try {
      cached = await _repository.readCachedAppLanguage();
    } catch (_) {
      // A server read may still restore the language after local cache damage.
    }
    if (isClosed || generation != _accountGeneration) return;
    if (cached != null) {
      _confirmedLanguage = cached;
      emit(state.copyWith(language: cached));
    }

    final refreshWriteGeneration = _writeGeneration;
    try {
      final remote = await _repository.refreshAppLanguage();
      if (isClosed || generation != _accountGeneration) return;
      if (refreshWriteGeneration != _writeGeneration) return;
      if (remote != null) {
        _confirmedLanguage = remote;
        emit(state.copyWith(language: remote));
      }
    } catch (_) {
      // The cache (or system default) remains a valid offline value.
    }
  }

  void select(AppLanguage language) {
    if (state.isSaving || state.language == language) return;
    final rollbackLanguage = _confirmedLanguage ?? state.language;
    _writeGeneration++;
    emit(
      state.copyWith(language: language, isSaving: true, clearFeedback: true),
    );
    final generation = _accountGeneration;
    unawaited(_save(language, rollbackLanguage, generation));
  }

  Future<void> _save(
    AppLanguage language,
    AppLanguage rollbackLanguage,
    int generation,
  ) async {
    try {
      final saved = await _repository.updateAppLanguage(language);
      if (isClosed || generation != _accountGeneration) return;
      _confirmedLanguage = saved;
      emit(
        state.copyWith(
          language: saved,
          isSaving: false,
          feedback: AppLanguageFeedback.success,
          feedbackId: state.feedbackId + 1,
        ),
      );
    } catch (_) {
      if (isClosed || generation != _accountGeneration) return;
      _confirmedLanguage = rollbackLanguage;
      emit(
        state.copyWith(
          language: rollbackLanguage,
          isSaving: false,
          feedback: AppLanguageFeedback.failure,
          feedbackId: state.feedbackId + 1,
        ),
      );
    }
  }
}
