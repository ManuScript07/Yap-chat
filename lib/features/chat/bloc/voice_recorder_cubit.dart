import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/chat.dart';

enum VoiceRecorderStatus { idle, recording, preview }

class VoiceRecorderState extends Equatable {
  const VoiceRecorderState({
    this.status = VoiceRecorderStatus.idle,
    this.duration = Duration.zero,
    this.amplitudes = const [],
    this.recordedAudio,
    this.playback = const AudioPlaybackSnapshot(),
    this.permissionStatus,
    this.scrubPosition,
  });

  final VoiceRecorderStatus status;
  final Duration duration;
  final List<double> amplitudes;
  final RecordedAudio? recordedAudio;
  final AudioPlaybackSnapshot playback;
  final MicrophonePermissionStatus? permissionStatus;
  final Duration? scrubPosition;

  bool get hasPendingRecording => status != VoiceRecorderStatus.idle;

  bool get canFinishRecording =>
      duration >= const Duration(seconds: 1);

  VoiceRecorderState copyWith({
    VoiceRecorderStatus? status,
    Duration? duration,
    List<double>? amplitudes,
    RecordedAudio? recordedAudio,
    AudioPlaybackSnapshot? playback,
    MicrophonePermissionStatus? permissionStatus,
    Duration? scrubPosition,
    bool clearPermissionStatus = false,
    bool clearScrubPosition = false,
  }) {
    return VoiceRecorderState(
      status: status ?? this.status,
      duration: duration ?? this.duration,
      amplitudes: amplitudes ?? this.amplitudes,
      recordedAudio: recordedAudio ?? this.recordedAudio,
      playback: playback ?? this.playback,
      permissionStatus: clearPermissionStatus
          ? null
          : permissionStatus ?? this.permissionStatus,
      scrubPosition: clearScrubPosition ? null : scrubPosition ?? this.scrubPosition,
    );
  }

  @override
  List<Object?> get props => [
    status,
    duration,
    amplitudes,
    recordedAudio,
    playback,
    permissionStatus,
    scrubPosition,
  ];
}

class VoiceRecorderCubit extends Cubit<VoiceRecorderState> {
  VoiceRecorderCubit({
    required IAudioRecorderRepository recorderRepository,
    required IAudioPlayerRepository playerRepository,
  })  : _recorderRepository = recorderRepository,
        _playerSession = playerRepository.createSession(),
        super(const VoiceRecorderState()) {
    _playbackSubscription = _playerSession.snapshots.listen((playback) {
      emit(state.copyWith(playback: playback));
    });
  }

  static const _maxDuration = Duration(minutes: 5);
  static const _minDuration = Duration(seconds: 1);
  static const _maxAmplitudeSamples = 4000;

  final IAudioRecorderRepository _recorderRepository;
  final IAudioPlayerSession _playerSession;
  late final StreamSubscription<AudioPlaybackSnapshot> _playbackSubscription;

  StreamSubscription<double>? _amplitudeSubscription;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  bool _isStarting = false;

  Future<void> startRecording() async {
    if (state.status != VoiceRecorderStatus.idle || _isStarting) return;
    _isStarting = true;

    try {
      final permission = await _recorderRepository.requestPermission();
      if (permission != MicrophonePermissionStatus.granted) {
        emit(state.copyWith(permissionStatus: permission));
        return;
      }

      await _recorderRepository.startRecording();
      _stopwatch
        ..reset()
        ..start();
      _listenToAmplitude();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final duration = _stopwatch.elapsed;
        if (duration >= _maxDuration) {
          stopRecording();
          return;
        }
        emit(state.copyWith(duration: duration));
      });
      emit(
        const VoiceRecorderState(
          status: VoiceRecorderStatus.recording,
        ),
      );
    } catch (_) {
      await _stopActiveRecording();
      emit(const VoiceRecorderState());
    } finally {
      _isStarting = false;
    }
  }

  Future<void> stopRecording() async {
    if (state.status != VoiceRecorderStatus.recording) return;

    final duration = _stopwatch.elapsed;
    if (duration < _minDuration) return;
    try {
      await _stopActiveRecording();
      final recordedAudio = await _recorderRepository.stopRecording(
        duration,
        state.amplitudes,
      );
      if (recordedAudio == null || recordedAudio.duration == Duration.zero) {
        emit(const VoiceRecorderState());
        return;
      }

      emit(
        state.copyWith(
          status: VoiceRecorderStatus.preview,
          duration: recordedAudio.duration,
          recordedAudio: recordedAudio,
        ),
      );
    } catch (_) {
      emit(const VoiceRecorderState());
    }
  }

  Future<RecordedAudio?> takeRecordingForSending() async {
    if (state.status == VoiceRecorderStatus.recording) {
      if (_stopwatch.elapsed < _minDuration) return null;
      await stopRecording();
    }

    final recordedAudio = state.recordedAudio;
    if (recordedAudio == null) return null;

    await _playerSession.pause();
    emit(const VoiceRecorderState());
    return recordedAudio;
  }

  Future<void> togglePreviewPlayback() async {
    final recordedAudio = state.recordedAudio;
    if (state.status != VoiceRecorderStatus.preview || recordedAudio == null) {
      return;
    }

    if (state.playback.isPlaying) {
      await _playerSession.pause();
    } else {
      await _playerSession.play(recordedAudio.path);
    }
  }

  void previewSeek(Duration position) {
    if (state.status != VoiceRecorderStatus.preview) return;
    emit(state.copyWith(scrubPosition: position));
  }

  Future<void> finishPreviewSeeking() async {
    final recordedAudio = state.recordedAudio;
    if (state.status != VoiceRecorderStatus.preview || recordedAudio == null) {
      return;
    }

    final position = state.scrubPosition;
    if (position == null) return;

    try {
      await _playerSession.prepare(recordedAudio.path);
      await _playerSession.seek(position);
    } finally {
      emit(state.copyWith(clearScrubPosition: true));
    }
  }

  Future<void> discardRecording() async {
    if (state.status == VoiceRecorderStatus.recording) {
      await _resetActiveRecording();
    }
    await _playerSession.pause();
    emit(const VoiceRecorderState());
  }

  Future<void> clearPermissionFeedback() async {
    if (state.permissionStatus == null) return;
    emit(state.copyWith(clearPermissionStatus: true));
  }

  Future<void> openAppSettings() => _recorderRepository.openAppSettings();

  void _listenToAmplitude() {
    _amplitudeSubscription = _recorderRepository.watchAmplitude().listen((value) {
      final amplitudes = [...state.amplitudes, value];
      if (amplitudes.length > _maxAmplitudeSamples) amplitudes.removeAt(0);
      emit(state.copyWith(amplitudes: amplitudes));
    });
  }

  Future<void> _stopActiveRecording() async {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
  }

  Future<void> _resetActiveRecording() async {
    await _stopActiveRecording();
    await _recorderRepository.cancelRecording();
  }

  @override
  Future<void> close() async {
    if (state.status == VoiceRecorderStatus.recording) {
      await _resetActiveRecording();
    }
    await _playbackSubscription.cancel();
    await _playerSession.dispose();
    return super.close();
  }
}
