import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/bloc/voice_recorder_cubit.dart';
import 'package:yap_chat/features/chat/data/models/audio_playback_snapshot.dart';
import 'package:yap_chat/features/chat/data/models/recorded_audio.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_player_repository.dart';
import 'package:yap_chat/repositories/chat/abstract_audio_recorder_repository.dart';
import 'package:yap_chat/repositories/chat/abstract_local_media_repository.dart';

void main() {
  test(
    'permission request cannot start a recorder after the chat closes',
    () async {
      final permission = Completer<MicrophonePermissionStatus>();
      final recorder = _Recorder(permission.future);
      final cubit = VoiceRecorderCubit(
        recorderRepository: recorder,
        playerRepository: _Players(),
        localMediaRepository: _Drafts(),
        chatId: 'chat',
      );

      final starting = cubit.startRecording();
      expect(cubit.state.isStarting, isTrue);
      expect(cubit.state.hasPendingRecording, isTrue);
      final closing = cubit.close();
      permission.complete(MicrophonePermissionStatus.granted);
      await Future.wait([starting, closing]);

      expect(recorder.starts, 0);
    },
  );

  test(
    'opening a recorded draft restores preview without network work',
    () async {
      final drafts = _Drafts()
        ..draft = const RecordedAudio(
          path: 'local-voice.m4a',
          duration: Duration(seconds: 3),
          waveform: [0.2, 0.8],
        );
      final cubit = VoiceRecorderCubit(
        recorderRepository: _Recorder(
          Future.value(MicrophonePermissionStatus.granted),
        ),
        playerRepository: _Players(),
        localMediaRepository: drafts,
        chatId: 'chat',
      );

      expect(cubit.state.status, VoiceRecorderStatus.preview);
      expect(cubit.state.recordedAudio, drafts.draft);
      await cubit.close();
      expect(drafts.draft, isNotNull);
    },
  );

  test('a failed send can restore its retained voice draft', () async {
    final drafts = _Drafts()
      ..draft = const RecordedAudio(
        path: 'local-voice.m4a',
        duration: Duration(seconds: 3),
        waveform: [0.5],
      );
    final cubit = VoiceRecorderCubit(
      recorderRepository: _Recorder(
        Future.value(MicrophonePermissionStatus.granted),
      ),
      playerRepository: _Players(),
      localMediaRepository: drafts,
      chatId: 'chat',
    );

    final audio = await cubit.takeRecordingForSending();
    expect(audio, drafts.draft);
    expect(cubit.state.status, VoiceRecorderStatus.idle);
    cubit.restoreUnsentDraft();
    expect(cubit.state.status, VoiceRecorderStatus.preview);
    await cubit.close();
  });

  test('recording remains active while a playback session is used', () async {
    final recorder = _Recorder(
      Future.value(MicrophonePermissionStatus.granted),
    );
    final players = _Players();
    final cubit = VoiceRecorderCubit(
      recorderRepository: recorder,
      playerRepository: players,
      localMediaRepository: _Drafts(),
      chatId: 'chat',
    );

    await cubit.startRecording();
    await players.session.play('another-voice');

    expect(cubit.state.status, VoiceRecorderStatus.recording);
    expect(recorder.starts, 1);
    await cubit.close();
  });

  test('rapid exit stops once and drops a too-short recording', () async {
    final recorder = _Recorder(Future.value(MicrophonePermissionStatus.granted))
      ..returnRecording = true;
    final drafts = _Drafts();
    final cubit = VoiceRecorderCubit(
      recorderRepository: recorder,
      playerRepository: _Players(),
      localMediaRepository: drafts,
      chatId: 'chat',
    );

    await cubit.startRecording();
    await Future.wait([
      cubit.finishForNavigation(),
      cubit.finishForNavigation(),
    ]);

    expect(recorder.stops, 1);
    expect(recorder.deletedPaths, ['local.m4a']);
    expect(cubit.state.status, VoiceRecorderStatus.idle);
    expect(drafts.draft, isNull);
    await cubit.close();
  });

  test(
    'leaving a chat finishes the recording into a reusable preview',
    () async {
      final recorder = _Recorder(
        Future.value(MicrophonePermissionStatus.granted),
      )..returnRecording = true;
      final drafts = _Drafts();
      final cubit = VoiceRecorderCubit(
        recorderRepository: recorder,
        playerRepository: _Players(),
        localMediaRepository: drafts,
        chatId: 'chat',
      );

      await cubit.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 1050));
      await cubit.finishForNavigation();

      expect(cubit.state.status, VoiceRecorderStatus.preview);
      expect(drafts.draft, cubit.state.recordedAudio);
      expect(recorder.stops, 1);
      await cubit.close();

      final reopened = VoiceRecorderCubit(
        recorderRepository: recorder,
        playerRepository: _Players(),
        localMediaRepository: drafts,
        chatId: 'chat',
      );
      expect(reopened.state.status, VoiceRecorderStatus.preview);
      await reopened.close();
    },
  );
}

class _Recorder extends Fake implements IAudioRecorderRepository {
  _Recorder(this.permission);

  final Future<MicrophonePermissionStatus> permission;
  int starts = 0;
  int stops = 0;
  final List<String> deletedPaths = [];
  bool returnRecording = false;

  @override
  Future<MicrophonePermissionStatus> requestPermission() => permission;

  @override
  Future<void> startRecording() async {
    starts++;
  }

  @override
  Stream<double> watchAmplitude() => const Stream<double>.empty();

  @override
  Future<RecordedAudio?> stopRecording(
    Duration duration,
    List<double> waveform,
  ) async {
    stops++;
    return returnRecording
        ? RecordedAudio(
            path: 'local.m4a',
            duration: duration,
            waveform: waveform,
          )
        : null;
  }

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> deleteRecording(String path) async => deletedPaths.add(path);
}

class _Drafts extends Fake implements ILocalMediaRepository {
  RecordedAudio? draft;

  @override
  RecordedAudio? getVoiceDraft(String chatId) => draft;

  @override
  Future<RecordedAudio?> saveVoiceDraft(
    String chatId,
    RecordedAudio audio,
  ) async => draft = audio;

  @override
  Future<void> removeVoiceDraft(String chatId, {bool deleteFile = true}) async {
    draft = null;
  }

  @override
  Future<void> removeVoiceDraftByPath(String audioPath) async {
    if (draft?.path == audioPath) draft = null;
  }
}

class _Players implements IAudioPlayerRepository {
  final _PlayerSession session = _PlayerSession();

  @override
  IAudioPlayerSession createSession() => session;
}

class _PlayerSession implements IAudioPlayerSession {
  final StreamController<AudioPlaybackSnapshot> _snapshots =
      StreamController<AudioPlaybackSnapshot>.broadcast();

  @override
  Stream<AudioPlaybackSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> prepare(String audioUrl) async {}

  @override
  Future<void> play(String audioUrl) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() => _snapshots.close();
}
