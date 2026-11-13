import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/repositories/profile/avatar_deletion_queue.dart';

void main() {
  late SharedPreferences preferences;
  late AvatarDeletionQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    queue = AvatarDeletionQueue(
      preferences: preferences,
      environment: 'test',
      talker: Talker(),
    );
  });

  test(
    'never deletes a path still referenced by the authoritative profile',
    () async {
      await queue.enqueue('user', ['kept.jpg']);
      final deleted = <String>[];
      await queue.reconcile(
        ownerUserId: 'user',
        referencedPaths: {'kept.jpg'},
        delete: (path) async => deleted.add(path),
      );
      await queue.reconcile(
        ownerUserId: 'user',
        referencedPaths: const {},
        delete: (path) async => deleted.add(path),
      );
      expect(deleted, isEmpty);
    },
  );

  test('retains failed deletions and retries them later', () async {
    await queue.enqueue('user', ['orphan.jpg']);
    var attempts = 0;
    Future<void> delete(String _) async {
      attempts++;
      if (attempts == 1) throw StateError('offline');
    }

    await queue.reconcile(
      ownerUserId: 'user',
      referencedPaths: const {},
      delete: delete,
    );
    queue = AvatarDeletionQueue(
      preferences: preferences,
      environment: 'test',
      talker: Talker(),
    );
    await queue.reconcile(
      ownerUserId: 'user',
      referencedPaths: const {},
      delete: delete,
    );
    await queue.reconcile(
      ownerUserId: 'user',
      referencedPaths: const {},
      delete: delete,
    );
    expect(attempts, 2);
  });
}
