import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';

class AudioMessagePlayerState {
  const AudioMessagePlayerState({
    this.playback = const AudioPlaybackSnapshot(),
    this.isLoading = false,
    this.scrubPosition,
  });

  final AudioPlaybackSnapshot playback;
  final bool isLoading;
  final Duration? scrubPosition;

  AudioMessagePlayerState copyWith({
    AudioPlaybackSnapshot? playback,
    bool? isLoading,
    Duration? scrubPosition,
    bool clearScrubPosition = false,
  }) {
    return AudioMessagePlayerState(
      playback: playback ?? this.playback,
      isLoading: isLoading ?? this.isLoading,
      scrubPosition: clearScrubPosition ? null : scrubPosition ?? this.scrubPosition,
    );
  }
}

class AudioMessagePlayerCubit extends Cubit<AudioMessagePlayerState> {
  AudioMessagePlayerCubit({required IAudioPlayerRepository playerRepository})
      : _session = playerRepository.createSession(),
        super(const AudioMessagePlayerState()) {
    _subscription = _session.snapshots.listen((snapshot) {
      emit(state.copyWith(playback: snapshot, isLoading: false));
    });
  }

  final IAudioPlayerSession _session;
  late final StreamSubscription<AudioPlaybackSnapshot> _subscription;

  Future<void> toggle(String audioUrl) async {
    try {
      if (state.playback.isPlaying) {
        await _session.pause();
      } else {
        emit(state.copyWith(isLoading: true));
        await _session.play(audioUrl);
      }
    } catch (_) {
      emit(state.copyWith(isLoading: false));
    }
  }

  void previewSeek(Duration position) {
    emit(state.copyWith(scrubPosition: position));
  }

  Future<void> finishSeeking(String audioUrl) async {
    final position = state.scrubPosition;
    if (position == null) return;

    try {
      await _session.prepare(audioUrl);
      await _session.seek(position);
      emit(state.copyWith(clearScrubPosition: true));
    } catch (_) {
      emit(state.copyWith(isLoading: false, clearScrubPosition: true));
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _session.dispose();
    return super.close();
  }
}
