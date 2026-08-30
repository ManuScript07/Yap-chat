import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/app_content/abstract_app_public_content_repository.dart';

class AppPublicContentState extends Equatable {
  const AppPublicContentState({this.content, this.isLoading = false});

  final AppPublicContent? content;
  final bool isLoading;

  AppPublicContentState copyWith({
    AppPublicContent? content,
    bool? isLoading,
  }) => AppPublicContentState(
    content: content ?? this.content,
    isLoading: isLoading ?? this.isLoading,
  );

  @override
  List<Object?> get props => [content, isLoading];
}

/// Global public metadata. It is intentionally not tied to an account and
/// remains available across logout from its small preferences cache.
class AppPublicContentCubit extends Cubit<AppPublicContentState> {
  AppPublicContentCubit({required this._repository})
    : super(const AppPublicContentState());

  final IAppPublicContentRepository _repository;
  Future<void>? _activeLoad;

  Future<void> load() => _activeLoad ??= _load();

  Future<AppPublicContent?> ensureContent() async {
    await load();
    return state.content;
  }

  Future<void> _load() async {
    AppPublicContent? cached;
    try {
      cached = await _repository.readCached();
      if (!isClosed && cached != null) {
        emit(state.copyWith(content: cached));
      }
    } catch (_) {
      // A remote refresh can still restore public links after cache damage.
    }
    if (!isClosed) emit(state.copyWith(isLoading: cached == null));
    try {
      final remote = await _repository.refresh();
      if (!isClosed && remote != null) emit(state.copyWith(content: remote));
    } catch (_) {
      // Cached public links remain usable offline.
    } finally {
      if (!isClosed) emit(state.copyWith(isLoading: false));
    }
  }
}
