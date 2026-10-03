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
    this.isStarting = false,
    this.isStopping = false,
  });

  final VoiceRecorderStatus status;
  final Duration duration;
  final List<double> amplitudes;
  final RecordedAudio? recordedAudio;
  final AudioPlaybackSnapshot playback;
  final MicrophonePermissionStatus? permissionStatus;
  final Duration? scrubPosition;
  final bool isStarting;
  final bool isStopping;

  bool get hasPendingRecording =>
      status != VoiceRecorderStatus.idle || isStarting;

  bool get canFinishRecording =>
      !isStopping && duration >= const Duration(seconds: 1);

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
    bool? isStarting,
    bool? isStopping,
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
      scrubPosition: clearScrubPosition
          ? null
          : scrubPosition ?? this.scrubPosition,
      isStarting: isStarting ?? this.isStarting,
      isStopping: isStopping ?? this.isStopping,
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
    isStarting,
    isStopping,
  ];
}

class VoiceRecorderCubit extends Cubit<VoiceRecorderState> {
  VoiceRecorderCubit({
    required IAudioRecorderRepository recorderRepository,
    required IAudioPlayerRepository playerRepository,
    required ILocalMediaRepository localMediaRepository,
    required String chatId,
  }) : _recorderRepository = recorderRepository,
       _localMediaRepository = localMediaRepository,
       _chatId = chatId,
       _playerSession = playerRepository.createSession(),
       super(_initialState(localMediaRepository.getVoiceDraft(chatId))) {
    _playbackSubscription = _playerSession.snapshots.listen((playback) {
      emit(state.copyWith(playback: playback));
    });
  }

  static const _maxDuration = Duration(minutes: 5);
  static const _minDuration = Duration(seconds: 1);
  static const _maxAmplitudeSamples = 4000;

  final IAudioRecorderRepository _recorderRepository;
  final ILocalMediaRepository _localMediaRepository;
  final String _chatId;
  final IAudioPlayerSession _playerSession;
  late final StreamSubscription<AudioPlaybackSnapshot> _playbackSubscription;

  StreamSubscription<double>? _amplitudeSubscription;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  bool _isStarting = false;
  bool _closing = false;
  bool _isTakingRecording = false;
  int _startGeneration = 0;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  Future<RecordedAudio?>? _takeOperation;

  static VoiceRecorderState _initialState(RecordedAudio? draft) => draft == null
      ? const VoiceRecorderState()
      : VoiceRecorderState(
          status: VoiceRecorderStatus.preview,
          duration: draft.duration,
          amplitudes: draft.waveform,
          recordedAudio: draft,
        );

  Future<void> startRecording() {
    if (state.status != VoiceRecorderStatus.idle || _isStarting || _closing) {
      return Future<void>.value();
    }
    _isStarting = true;
    final generation = ++_startGeneration;
    final operation = _beginRecording(generation);
    _startOperation = operation;
    return operation.whenComplete(() {
      if (identical(_startOperation, operation)) _startOperation = null;
    });
  }

  Future<void> _beginRecording(int generation) async {
    emit(state.copyWith(isStarting: true));
    try {
      final permission = await _recorderRepository.requestPermission();
      if (generation != _startGeneration || _closing) return;
      if (permission != MicrophonePermissionStatus.granted) {
        emit(state.copyWith(permissionStatus: permission, isStarting: false));
        return;
      }

      await _recorderRepository.startRecording();
      if (generation != _startGeneration || _closing) {
        await _recorderRepository.cancelRecording();
        return;
      }
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
      emit(const VoiceRecorderState(status: VoiceRecorderStatus.recording));
    } catch (_) {
      await _resetActiveRecording();
      if (!_closing) emit(const VoiceRecorderState());
    } finally {
      _isStarting = false;
      if (!_closing && state.isStarting) {
        emit(state.copyWith(isStarting: false));
      }
    }
  }

  Future<void> stopRecording({bool force = false}) {
    if (_stopOperation case final pending?) return pending;
    if (state.status != VoiceRecorderStatus.recording) {
      return Future<void>.value();
    }

    final duration = _stopwatch.elapsed;
    if (duration < _minDuration && !force) return Future<void>.value();
    final operation = _finishRecording(duration);
    _stopOperation = operation;
    return operation.whenComplete(() {
      if (identical(_stopOperation, operation)) _stopOperation = null;
    });
  }

  Future<void> _finishRecording(Duration duration) async {
    emit(state.copyWith(isStopping: true));
    try {
      await _stopActiveRecording();
      final recordedAudio = await _recorderRepository.stopRecording(
        duration,
        state.amplitudes,
      );
      if (recordedAudio == null || recordedAudio.duration < _minDuration) {
        if (recordedAudio != null) {
          await _recorderRepository.deleteRecording(recordedAudio.path);
        }
        emit(const VoiceRecorderState());
        return;
      }
      final saved = await _localMediaRepository.saveVoiceDraft(
        _chatId,
        recordedAudio,
      );
      if (saved == null) {
        emit(const VoiceRecorderState());
        return;
      }

      emit(
        state.copyWith(
          status: VoiceRecorderStatus.preview,
          duration: saved.duration,
          recordedAudio: saved,
          isStopping: false,
        ),
      );
    } catch (_) {
      emit(const VoiceRecorderState());
    }
  }

  Future<void> finishForNavigation() async {
    if (_isStarting) {
      _startGeneration++;
      await _startOperation;
    }
    if (state.status == VoiceRecorderStatus.recording) {
      await stopRecording(force: true);
    } else if (_stopOperation case final pending?) {
      await pending;
    }
    await _playerSession.pause();
  }

  void restoreUnsentDraft() {
    if (_closing || state.status != VoiceRecorderStatus.idle || _isStarting) {
      return;
    }
    final draft = _localMediaRepository.getVoiceDraft(_chatId);
    if (draft != null) emit(_initialState(draft));
  }

  Future<RecordedAudio?> takeRecordingForSending() {
    if (_isTakingRecording || _closing) return Future<RecordedAudio?>.value();
    _isTakingRecording = true;
    final operation = _takeRecordingForSending();
    _takeOperation = operation;
    return operation.whenComplete(() {
      _isTakingRecording = false;
      if (identical(_takeOperation, operation)) _takeOperation = null;
    });
  }

  Future<RecordedAudio?> _takeRecordingForSending() async {
    if (state.status == VoiceRecorderStatus.recording) {
      if (_stopwatch.elapsed < _minDuration) return null;
      await stopRecording();
    }

    if (_stopOperation case final pending?) await pending;
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
    if (_isStarting) {
      _startGeneration++;
      await _startOperation;
    }
    if (_stopOperation case final pending?) await pending;
    if (state.status == VoiceRecorderStatus.recording) {
      await _resetActiveRecording();
    }
    await _playerSession.pause();
    await _localMediaRepository.removeVoiceDraft(_chatId);
    emit(const VoiceRecorderState());
  }

  Future<void> clearPermissionFeedback() async {
    if (state.permissionStatus == null) return;
    emit(state.copyWith(clearPermissionStatus: true));
  }

  Future<void> openAppSettings() => _recorderRepository.openAppSettings();

  void _listenToAmplitude() {
    _amplitudeSubscription = _recorderRepository.watchAmplitude().listen((
      value,
    ) {
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
    _closing = true;
    _startGeneration++;
    await _startOperation;
    await _takeOperation;
    if (state.status == VoiceRecorderStatus.recording) {
      await stopRecording(force: true);
    }
    if (_stopOperation case final pending?) await pending;
    await _playbackSubscription.cancel();
    await _playerSession.dispose();
    return super.close();
  }
}
