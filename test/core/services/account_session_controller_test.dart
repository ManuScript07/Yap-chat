import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';

void main() {
  group('AccountSessionController', () {
    test('rejects an A commit after switching to B', () async {
      final controller = AccountSessionController(initialUserId: 'account-a');
      final scopeA = controller.capture();
      final remoteResponse = Completer<void>();
      var committedOwner = '';

      final operation = () async {
        await remoteResponse.future;
        await controller.commit(scopeA, () async {
          committedOwner = scopeA.userId;
        });
      }();

      controller.setAuthenticatedUser(null);
      controller.setAuthenticatedUser('account-b');
      remoteResponse.complete();

      await expectLater(
        operation,
        throwsA(isA<StaleAccountSessionException>()),
      );
      expect(committedOwner, isEmpty);
      expect(controller.capture().userId, 'account-b');
    });

    test('invalidates work after signing out and into the same account', () {
      final controller = AccountSessionController(initialUserId: 'account-a');
      final oldScope = controller.capture();

      controller.setAuthenticatedUser(null);
      controller.setAuthenticatedUser('account-a');

      expect(controller.isCurrent(oldScope), isFalse);
      expect(controller.capture().userId, oldScope.userId);
    });

    test('drain waits for an already running local commit', () async {
      final controller = AccountSessionController(initialUserId: 'account-a');
      final scope = controller.capture();
      final release = Completer<void>();
      var commitFinished = false;

      final commit = controller.commit(scope, () async {
        await release.future;
        commitFinished = true;
      });
      await Future<void>.delayed(Duration.zero);

      var drainFinished = false;
      final drain = controller.drainCommits().then((_) => drainFinished = true);
      await Future<void>.delayed(Duration.zero);
      expect(drainFinished, isFalse);

      release.complete();
      await Future.wait([commit, drain]);
      expect(commitFinished, isTrue);
      expect(drainFinished, isTrue);
    });
  });
}
