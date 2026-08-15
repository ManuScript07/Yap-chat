import 'package:yap_chat/features/chat/data/data.dart';

enum MicrophonePermissionStatus { granted, denied, permanentlyDenied }

abstract interface class IAudioRecorderRepository {
  Future<MicrophonePermissionStatus> requestPermission();

  Future<void> startRecording();

  Stream<double> watchAmplitude();

  Future<RecordedAudio?> stopRecording(
    Duration duration,
    List<double> waveform,
  );

  Future<void> cancelRecording();

  Future<void> openAppSettings();
}
