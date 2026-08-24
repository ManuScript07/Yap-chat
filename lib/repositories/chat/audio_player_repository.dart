import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_player_repository.dart';

class AudioPlayerRepository implements IAudioPlayerRepository {
  @override
  IAudioPlayerSession createSession() => _AudioPlayerSession();
}

class _AudioPlayerSession implements IAudioPlayerSession {
  _AudioPlayerSession() {
    _subscriptions = [
      _player.positionStream.listen((position) {
        _emit(position: position);
      }),
      _player.durationStream.listen((duration) {
        _emit(duration: duration ?? Duration.zero);
      }),
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _hasCompleted = true;
          _scheduleCompletionReset();
          return;
        }
        if (!_isResettingAfterCompletion) {
          _emit(isPlaying: state.playing, isCompleted: false);
        }
      }),
    ];
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<AudioPlaybackSnapshot> _controller =
      StreamController<AudioPlaybackSnapshot>.broadcast();
  late final List<StreamSubscription> _subscriptions;

  AudioPlaybackSnapshot _snapshot = const AudioPlaybackSnapshot();
  String? _audioUrl;
  bool _hasCompleted = false;
  bool _isResettingAfterCompletion = false;
  Future<void>? _prepareOperation;
  Future<void>? _completionReset;

  @override
  Stream<AudioPlaybackSnapshot> get snapshots => _controller.stream;

  @override
  Future<void> prepare(String audioUrl) {
    if (_audioUrl == audioUrl) {
      return _prepareOperation ?? Future<void>.value();
    }

    _audioUrl = audioUrl;
    final operation = _loadAudio(audioUrl);
    _prepareOperation = operation;
    return operation.whenComplete(() {
      if (identical(_prepareOperation, operation)) {
        _prepareOperation = null;
      }
    });
  }

  Future<void> _loadAudio(String audioUrl) async {
    await _player.setAudioSource(AudioSource.uri(_toUri(audioUrl)));
    _hasCompleted = false;
    _emit(
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      isCompleted: false,
    );
  }

  @override
  Future<void> play(String audioUrl) async {
    await prepare(audioUrl);
    final completionReset = _completionReset;
    if (completionReset != null) await completionReset;
    if (_hasCompleted) {
      await _player.seek(Duration.zero);
      _hasCompleted = false;
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    _emit(position: position, isCompleted: false);
    _hasCompleted = false;
    try {
      await _player.seek(position);
    } catch (_) {
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _controller.close();
  }

  void _emit({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isCompleted,
  }) {
    _snapshot = AudioPlaybackSnapshot(
      position: position ?? _snapshot.position,
      duration: duration ?? _snapshot.duration,
      isPlaying: isPlaying ?? _snapshot.isPlaying,
      isCompleted: isCompleted ?? _snapshot.isCompleted,
    );
    _controller.add(_snapshot);
  }

  Uri _toUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme ? uri : Uri.file(value);
  }

  Future<void> _resetAfterCompletion() async {
    if (_isResettingAfterCompletion) return;
    _isResettingAfterCompletion = true;
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
      _hasCompleted = true;
      _emit(position: Duration.zero, isPlaying: false, isCompleted: true);
    } finally {
      _isResettingAfterCompletion = false;
    }
  }

  void _scheduleCompletionReset() {
    if (_completionReset != null) return;

    final reset = _resetAfterCompletion();
    _completionReset = reset;
    unawaited(
      reset.whenComplete(() {
        if (identical(_completionReset, reset)) {
          _completionReset = null;
        }
      }),
    );
  }
}
