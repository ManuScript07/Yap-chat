import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/models/audio_playback_snapshot.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_player_repository.dart';
import 'package:yap_chat/repositories/chat/audio_player_repository.dart';

void main() {
  test('playing another message pauses the previous session', () async {
    final first = _FakePlayerSession();
    final second = _FakePlayerSession();
    final available = [first, second];
    final repository = AudioPlayerRepository(
      sessionFactory: () => available.removeAt(0),
    );
    final firstClient = repository.createSession();
    final secondClient = repository.createSession();

    await firstClient.play('first');
    await secondClient.play('second');

    expect(first.played, ['first']);
    expect(first.pauseCount, 1);
    expect(second.played, ['second']);
    await firstClient.dispose();
    await secondClient.dispose();
  });

  test('concurrent play requests resolve to one active session', () async {
    final first = _FakePlayerSession();
    final second = _FakePlayerSession();
    final available = [first, second];
    final repository = AudioPlayerRepository(
      sessionFactory: () => available.removeAt(0),
    );
    final firstClient = repository.createSession();
    final secondClient = repository.createSession();

    await Future.wait([firstClient.play('first'), secondClient.play('second')]);

    expect(first.pauseCount, 1);
    expect(second.isPlaying, isTrue);
    expect(first.isPlaying, isFalse);
    await firstClient.dispose();
    await secondClient.dispose();
  });
}

class _FakePlayerSession implements IAudioPlayerSession {
  final StreamController<AudioPlaybackSnapshot> _snapshots =
      StreamController<AudioPlaybackSnapshot>.broadcast();
  final List<String> played = [];
  int pauseCount = 0;
  bool isPlaying = false;

  @override
  Stream<AudioPlaybackSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> prepare(String audioUrl) async {}

  @override
  Future<void> play(String audioUrl) async {
    played.add(audioUrl);
    isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    isPlaying = false;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() => _snapshots.close();
}
