import 'package:equatable/equatable.dart';

class RecordedAudio extends Equatable {
  const RecordedAudio({
    required this.path,
    required this.duration,
    required this.waveform,
  });

  final String path;
  final Duration duration;
  final List<double> waveform;

  @override
  List<Object?> get props => [path, duration, waveform];
}
