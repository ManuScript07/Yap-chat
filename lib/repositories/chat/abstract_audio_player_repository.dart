import 'package:yap_chat/features/chat/data/data.dart';

abstract interface class IAudioPlayerRepository {
  IAudioPlayerSession createSession();
}

abstract interface class IAudioPlayerSession {
  Stream<AudioPlaybackSnapshot> get snapshots;

  Future<void> prepare(String audioUrl);

  Future<void> play(String audioUrl);

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> dispose();
}
