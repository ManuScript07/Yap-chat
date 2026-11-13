import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/core/database/database.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/features/chat/data/models/recorded_audio.dart';
import 'package:yap_chat/repositories/chat/local_media_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'voice draft survives repository recreation and is scoped by account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final documents = await Directory.systemTemp.createTemp(
        'voice-draft-test-',
      );
      addTearDown(database.close);
      addTearDown(() => documents.delete(recursive: true));
      final account = AccountSessionController(initialUserId: 'first');
      LocalMediaRepository repository() => LocalMediaRepository(
        preferences: preferences,
        database: database,
        ownerUserIdProvider: () => account.userId,
        environment: 'test',
        accountSessionController: account,
        documentsDirectoryProvider: () async => documents,
      );
      final source = File('${documents.path}/recording.m4a');
      await source.writeAsBytes([1, 2, 3]);
      const recording = RecordedAudio(
        path: 'unused',
        duration: Duration(seconds: 4),
        waveform: [0.1, 0.5],
      );

      final saved = await repository().saveVoiceDraft(
        'chat',
        RecordedAudio(
          path: source.path,
          duration: recording.duration,
          waveform: recording.waveform,
        ),
      );
      expect(saved, isNotNull);
      expect(await File(saved!.path).exists(), isTrue);
      expect(await source.exists(), isFalse);
      expect(repository().getVoiceDraft('chat'), saved);

      await repository().removeVoiceDraftByPath(saved.path);
      expect(repository().getVoiceDraft('chat'), isNull);
      expect(await File(saved.path).exists(), isFalse);

      final secondSource = File('${documents.path}/another.m4a');
      await secondSource.writeAsBytes([4, 5, 6]);
      final retained = await repository().saveVoiceDraft(
        'chat',
        RecordedAudio(
          path: secondSource.path,
          duration: recording.duration,
          waveform: recording.waveform,
        ),
      );
      expect(retained, isNotNull);

      final thirdSource = File('${documents.path}/third.m4a');
      await thirdSource.writeAsBytes([7, 8, 9]);
      final replacement = await repository().saveVoiceDraft(
        'chat',
        RecordedAudio(
          path: thirdSource.path,
          duration: recording.duration,
          waveform: recording.waveform,
        ),
      );
      expect(await File(retained!.path).exists(), isTrue);
      await repository().removeVoiceDraftByPath(retained.path);
      expect(repository().getVoiceDraft('chat'), replacement);
      expect(await File(retained.path).exists(), isFalse);

      account.setAuthenticatedUser('second');
      expect(repository().getVoiceDraft('chat'), isNull);
      account.setAuthenticatedUser('first');
      await repository().clearUser('first');
      expect(repository().getVoiceDraft('chat'), isNull);
      expect(await File(replacement!.path).exists(), isFalse);
    },
  );
}
