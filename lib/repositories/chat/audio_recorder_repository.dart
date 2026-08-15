import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'
    as permission_handler;
import 'package:record/record.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_recorder_repository.dart';

class AudioRecorderRepository implements IAudioRecorderRepository {
  AudioRecorderRepository() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<MicrophonePermissionStatus> requestPermission() async {
    if (await _recorder.hasPermission()) {
      return MicrophonePermissionStatus.granted;
    }

    final permission = await permission_handler.Permission.microphone.request();
    if (permission.isGranted) {
      return MicrophonePermissionStatus.granted;
    }

    return permission.isPermanentlyDenied
        ? MicrophonePermissionStatus.permanentlyDenied
        : MicrophonePermissionStatus.denied;
  }

  @override
  Future<void> startRecording() async {
    await _recorder.start(
      _recordConfig,
      path: await _createOutputPath(),
    );
  }

  @override
  Stream<double> watchAmplitude() {
    return _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .map((amplitude) => ((amplitude.current + 60) / 60).clamp(0.04, 1.0));
  }

  @override
  Future<RecordedAudio?> stopRecording(
    Duration duration,
    List<double> waveform,
  ) async {
    final audioPath = await _recorder.stop();
    if (audioPath == null || audioPath.isEmpty) return null;

    return RecordedAudio(
      path: audioPath,
      duration: duration,
      waveform: List.unmodifiable(waveform),
    );
  }

  @override
  Future<void> cancelRecording() => _recorder.cancel();

  @override
  Future<void> openAppSettings() async {
    await permission_handler.openAppSettings();
  }

  Future<String> _createOutputPath() async {
    final fileName = 'voice_${DateTime.now().microsecondsSinceEpoch}${
      kIsWeb ? '.wav' : '.m4a'
    }';
    if (kIsWeb) return fileName;

    final directory = await getTemporaryDirectory();
    return path.join(directory.path, fileName);
  }

  RecordConfig get _recordConfig {
    if (kIsWeb) {
      return const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        numChannels: 1,
      );
    }

    return const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
      numChannels: 1,
    );
  }
}
