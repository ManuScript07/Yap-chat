import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_player_repository.dart';

class AudioPlayerRepository implements IAudioPlayerRepository {
  AudioPlayerRepository({IAudioPlayerSession Function()? sessionFactory})
    : _sessionFactory = sessionFactory ?? _AudioPlayerSession.new;

  final IAudioPlayerSession Function() _sessionFactory;
  _CoordinatedAudioPlayerSession? _activeSession;
  Future<void> _transition = Future<void>.value();

  @override
  IAudioPlayerSession createSession() =>
      _CoordinatedAudioPlayerSession(this, _sessionFactory());

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _transition.then((_) => action());
    _transition = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _play(_CoordinatedAudioPlayerSession session, String audioUrl) =>
      _serialize(() async {
        if (session._disposed) return;
        final previous = _activeSession;
        if (previous != null && previous != session) {
          await previous._underlying.pause();
        }
        _activeSession = session;
        try {
          await session._underlying.play(audioUrl);
        } catch (_) {
          if (_activeSession == session) _activeSession = null;
          rethrow;
        }
      });

  Future<void> _pause(_CoordinatedAudioPlayerSession session) =>
      _serialize(() async {
        if (session._disposed) return;
        await session._underlying.pause();
        if (_activeSession == session) _activeSession = null;
      });

  Future<void> _dispose(_CoordinatedAudioPlayerSession session) =>
      _serialize(() async {
        if (_activeSession == session) _activeSession = null;
        await session._underlying.dispose();
      });
}

class _CoordinatedAudioPlayerSession implements IAudioPlayerSession {
  _CoordinatedAudioPlayerSession(this._repository, this._underlying);

  final AudioPlayerRepository _repository;
  final IAudioPlayerSession _underlying;
  bool _disposed = false;

  @override
  Stream<AudioPlaybackSnapshot> get snapshots => _underlying.snapshots;

  @override
  Future<void> prepare(String audioUrl) => _underlying.prepare(audioUrl);

  @override
  Future<void> play(String audioUrl) => _repository._play(this, audioUrl);

  @override
  Future<void> pause() => _repository._pause(this);

  @override
  Future<void> seek(Duration position) => _underlying.seek(position);

  @override
  Future<void> dispose() {
    if (_disposed) return Future<void>.value();
    _disposed = true;
    return _repository._dispose(this);
  }
}

class _AudioPlayerSession implements IAudioPlayerSession {
  _AudioPlayerSession();

  AudioPlayer? _player;
  final StreamController<AudioPlaybackSnapshot> _controller =
      StreamController<AudioPlaybackSnapshot>.broadcast();
  final List<StreamSubscription> _subscriptions = [];

  AudioPlayer _ensurePlayer() {
    if (_player case final existing?) return existing;
    // A visible voice bubble needs only a logical session. Create its native
    // player when the user actually plays or seeks that message.
    final player = AudioPlayer();
    _player = player;
    _subscriptions.addAll([
      player.positionStream.listen((position) {
        _emit(position: position);
      }),
      player.durationStream.listen((duration) {
        _emit(duration: duration ?? Duration.zero);
      }),
      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _hasCompleted = true;
          _scheduleCompletionReset();
          return;
        }
        if (!_isResettingAfterCompletion) {
          _emit(isPlaying: state.playing, isCompleted: false);
        }
      }),
    ]);
    return player;
  }

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
    _hasCompleted = false;
    _emit(
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      isCompleted: false,
    );
    try {
      await _ensurePlayer().setAudioSource(AudioSource.uri(_toUri(audioUrl)));
    } catch (_) {
      if (_audioUrl == audioUrl) _audioUrl = null;
      rethrow;
    }
  }

  @override
  Future<void> play(String audioUrl) async {
    await prepare(audioUrl);
    final completionReset = _completionReset;
    if (completionReset != null) await completionReset;
    if (_hasCompleted) {
      await _ensurePlayer().seek(Duration.zero);
      _hasCompleted = false;
    }
    // just_audio's play future completes when playback ends, not when it starts.
    // Do not keep the repository's cross-chat transition locked for the whole clip.
    unawaited(
      _ensurePlayer().play().then<void>(
        (_) {},
        onError: (Object _, StackTrace stackTrace) {
          _emit(isPlaying: false);
        },
      ),
    );
  }

  @override
  Future<void> pause() => _player?.pause() ?? Future<void>.value();

  @override
  Future<void> seek(Duration position) async {
    _emit(position: position, isCompleted: false);
    _hasCompleted = false;
    try {
      await _ensurePlayer().seek(position);
    } catch (_) {
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player?.dispose();
    await _controller.close();
  }

  void _emit({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isCompleted,
  }) {
    if (_controller.isClosed) return;
    final next = AudioPlaybackSnapshot(
      position: position ?? _snapshot.position,
      duration: duration ?? _snapshot.duration,
      isPlaying: isPlaying ?? _snapshot.isPlaying,
      isCompleted: isCompleted ?? _snapshot.isCompleted,
    );
    if (next == _snapshot) return;
    _snapshot = next;
    _controller.add(_snapshot);
  }

  Uri _toUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme ? uri : Uri.file(value);
  }

  Future<void> _resetAfterCompletion() async {
    if (_isResettingAfterCompletion) return;
    final player = _player;
    if (player == null) return;
    _isResettingAfterCompletion = true;
    try {
      await player.pause();
      await player.seek(Duration.zero);
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
      reset
          .catchError((Object _) {
            // A disposed/interrupted player cannot reset its position.
            _emit(isPlaying: false);
          })
          .whenComplete(() {
            if (identical(_completionReset, reset)) {
              _completionReset = null;
            }
          }),
    );
  }
}
