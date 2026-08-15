import 'package:equatable/equatable.dart';

class AudioPlaybackSnapshot extends Equatable {
  const AudioPlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isCompleted = false,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isCompleted;

  AudioPlaybackSnapshot copyWith({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isCompleted,
  }) {
    return AudioPlaybackSnapshot(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  @override
  List<Object?> get props => [position, duration, isPlaying, isCompleted];
}
