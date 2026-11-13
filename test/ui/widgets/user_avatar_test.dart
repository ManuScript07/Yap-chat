import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/services/account_session_controller.dart';
import 'package:yap_chat/ui/widgets/user_avatar.dart';

void main() {
  testWidgets('uses a row-provided local file without calling its loader', (
    tester,
  ) async {
    final photo = _localAvatar();
    var loads = 0;
    await tester.pumpWidget(
      _host(
        UserAvatar(
          avatarRevision: 'row-local-photo',
          initialAvatarPath: photo.path,
          avatarLoader: () async {
            loads++;
            throw StateError('A cached avatar must not need the network.');
          },
        ),
      ),
    );
    expect(_filePath(tester.widget<Image>(find.byType(Image))), photo.path);
    expect(loads, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _waitForAvatar(tester);
    expect(find.byIcon(Icons.person), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an OS-evicted initial file falls back to one lazy load', (
    tester,
  ) async {
    final photo = _localAvatar();
    var loads = 0;
    await tester.pumpWidget(
      _host(
        UserAvatar(
          avatarRevision: 'evicted-row-photo',
          initialAvatarPath: '${photo.parent.path}/missing.png',
          avatarLoader: () async {
            loads++;
            return photo.path;
          },
        ),
      ),
    );
    await _waitForAvatar(tester);
    expect(loads, 1);
    expect(_filePath(tester.widget<Image>(find.byType(Image))), photo.path);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removed metadata overrides even an existing initial file', (
    tester,
  ) async {
    final photo = _localAvatar();
    Widget page({required bool removed}) => _host(
      UserAvatar(
        avatarRevision: removed ? null : 'removed-row-photo',
        initialAvatarPath: photo.path,
        avatarLoader: () async => null,
      ),
    );
    await tester.pumpWidget(page(removed: false));
    await _waitForAvatar(tester);
    await tester.pumpWidget(page(removed: true));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holds the row-provided photo while a new source is loading', (
    tester,
  ) async {
    final first = _localAvatar();
    final next = _localAvatar();
    final pending = Completer<String?>();
    Widget page({required bool changed}) => _host(
      UserAvatar(
        avatarRevision: changed ? 'next-row-photo' : 'old-row-photo',
        initialAvatarPath: changed
            ? '${next.parent.path}/missing.png'
            : first.path,
        avatarLoader: () => pending.future,
      ),
    );
    await tester.pumpWidget(page(changed: false));
    await _waitForAvatar(tester);
    final oldFrame = tester.widget<RawImage>(find.byType(RawImage)).image;
    await tester.pumpWidget(page(changed: true));
    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      same(oldFrame),
    );
    expect(find.byIcon(Icons.person), findsNothing);
    pending.complete(next.path);
    await _waitForAvatar(tester, path: next.path);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loads once across rebuilds and reloads for a new revision', (
    tester,
  ) async {
    var loadCount = 0;
    Future<String?> loader() async {
      loadCount++;
      return null;
    }

    Widget build({required String revision, required bool isOnline}) =>
        MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatarLoader: loader,
              avatarRevision: revision,
              isOnline: isOnline,
              showOnlineBadge: true,
            ),
          ),
        );

    await tester.pumpWidget(build(revision: 'avatar-1', isOnline: false));
    await tester.pump();
    expect(loadCount, 1);

    await tester.pumpWidget(build(revision: 'avatar-1', isOnline: true));
    await tester.pump();
    expect(loadCount, 1);

    await tester.pumpWidget(build(revision: 'avatar-2', isOnline: true));
    await tester.pump();
    expect(loadCount, 2);
  });

  testWidgets('does not call a loader before the avatar is mounted', (
    tester,
  ) async {
    var loadCount = 0;
    final avatars = List.generate(
      30,
      (index) => UserAvatar(
        key: ValueKey(index),
        avatarRevision: 'avatar-$index',
        avatarLoader: () async {
          loadCount++;
          return null;
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemExtent: 80,
            itemCount: avatars.length,
            itemBuilder: (context, index) => avatars[index],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(loadCount, greaterThan(0));
    expect(loadCount, lessThan(avatars.length));
  });

  testWidgets('keeps the previous avatar while a new revision resolves', (
    tester,
  ) async {
    var completer = Completer<String?>();
    final first = _localAvatar();
    final second = _localAvatar();
    Future<String?> loader() => completer.future;

    Widget build(String revision) => MaterialApp(
      home: Scaffold(
        body: UserAvatar(avatarLoader: loader, avatarRevision: revision),
      ),
    );

    await tester.pumpWidget(build('avatar-1'));
    completer.complete(first.path);
    await _waitForAvatar(tester);
    final firstFrame = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(_filePath(tester.widget<Image>(find.byType(Image))), first.path);

    completer = Completer<String?>();
    await tester.pumpWidget(build('avatar-2'));
    expect(_filePath(tester.widget<Image>(find.byType(Image))), first.path);

    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      same(firstFrame),
    );
    completer.complete(second.path);
    await tester.pump();
    // The previous pixels stay visible while the next file is decoding.
    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      same(firstFrame),
    );
    await _waitForAvatar(tester, path: second.path);
    expect(_filePath(tester.widget<Image>(find.byType(Image))), second.path);
    expect(find.byIcon(Icons.person), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not add a reveal animation to a local avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UserAvatar(avatarUrl: 'avatar.jpg')),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.frameBuilder, isNotNull);
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('a confirmed absence shows the placeholder even during a load', (
    tester,
  ) async {
    final pending = Completer<String?>();
    await tester.pumpWidget(
      _host(UserAvatar(avatarLoader: () => pending.future)),
    );
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    pending.complete(null);
    await tester.pump();
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'a pending photo settles to absence on ${fails ? 'error' : 'null'}',
      (tester) async {
        final pending = Completer<String?>();
        var loads = 0;
        Widget page() => _host(
          UserAvatar(
            avatarRevision: 'unavailable-$fails',
            avatarLoader: () {
              loads++;
              return pending.future;
            },
          ),
        );
        await tester.pumpWidget(page());
        expect(find.byIcon(Icons.person), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        if (fails) {
          pending.completeError(StateError('offline'));
        } else {
          pending.complete(null);
        }
        await tester.pump();
        expect(find.byIcon(Icons.person), findsOneWidget);
        await tester.pumpWidget(page());
        await tester.pump(const Duration(seconds: 5));
        expect(loads, 1, reason: 'A failed load must not cause a retry loop.');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('removing an avatar invalidates an in-flight Yandex load', (
    tester,
  ) async {
    const oldUrl = 'https://avatars.yandex.net/removed-avatar';
    final oldLoad = Completer<String?>();
    await tester.pumpWidget(
      _host(
        UserAvatar(
          avatarUrl: oldUrl,
          avatarRevision: oldUrl,
          preferAvatarLoader: true,
          avatarLoader: () => oldLoad.future,
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(_host(UserAvatar(avatarLoader: () async => null)));
    expect(find.byIcon(Icons.person), findsOneWidget);
    oldLoad.complete(oldUrl);
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removal immediately clears a previously resolved cached avatar',
    (tester) async {
      final file = _localAvatar();
      final removal = Completer<String?>();
      await tester.pumpWidget(
        _host(
          UserAvatar(
            avatarRevision: file.path,
            avatarLoader: () async => file.path,
          ),
        ),
      );
      await _waitForAvatar(tester);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(
        _host(UserAvatar(avatarLoader: () => removal.future)),
      );
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      removal.complete(null);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(const UserAvatar()));
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a stale revision cannot replace a newer avatar', (tester) async {
    final oldLoad = Completer<String?>();
    final newLoad = Completer<String?>();
    final file = _localAvatar();
    await tester.pumpWidget(
      _host(
        UserAvatar(
          avatarRevision: 'old-in-flight',
          avatarLoader: () => oldLoad.future,
        ),
      ),
    );
    await tester.pumpWidget(
      _host(
        UserAvatar(
          avatarRevision: file.path,
          avatarLoader: () => newLoad.future,
        ),
      ),
    );
    newLoad.complete(file.path);
    await _waitForAvatar(tester);
    oldLoad.complete('https://avatars.yandex.net/stale');
    await tester.pump();
    expect(_filePath(tester.widget<Image>(find.byType(Image))), file.path);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an evicted local file is reloaded once without a rebuild loop', (
    tester,
  ) async {
    final file = _localAvatar();
    final replacement = _localAvatar();
    final pending = Completer<String?>();
    var loads = 0;
    Widget page() => _host(
      UserAvatar(
        avatarRevision: 'evicted:${file.path}',
        avatarLoader: () {
          loads++;
          return loads == 1 ? Future.value(file.path) : pending.future;
        },
      ),
    );
    await tester.pumpWidget(page());
    await _waitForAvatar(tester);
    final image = tester.widget<Image>(find.byType(Image));
    file.deleteSync();
    // Invoke the same callback that Image uses on an evicted-file error.
    image.errorBuilder!(
      tester.element(find.byType(Image)),
      const FileSystemException(),
      null,
    );
    await tester.pump();
    await tester.pumpWidget(page());
    expect(loads, 2);
    expect(find.byIcon(Icons.person), findsNothing);
    pending.complete(replacement.path);
    await _waitForAvatar(tester, path: replacement.path);
    expect(
      _filePath(tester.widget<Image>(find.byType(Image))),
      replacement.path,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a newly available loader resolves without a metadata change', (
    tester,
  ) async {
    final file = _localAvatar();
    await tester.pumpWidget(_host(UserAvatar(avatarRevision: file.path)));
    expect(find.byIcon(Icons.person), findsOneWidget);
    var loads = 0;
    await tester.pumpWidget(
      _host(
        UserAvatar(
          avatarRevision: file.path,
          avatarLoader: () async {
            loads++;
            return file.path;
          },
        ),
      ),
    );
    await _waitForAvatar(tester);
    expect(loads, 1);
    expect(_filePath(tester.widget<Image>(find.byType(Image))), file.path);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cached avatars and painted frames never cross account scopes', (
    tester,
  ) async {
    final account = AccountSessionController(initialUserId: 'first');
    final first = _localAvatar();
    final second = _localAvatar();
    final pending = Completer<String?>();
    var loads = 0;
    Widget page() => RepositoryProvider<AccountSessionController>.value(
      value: account,
      child: _host(
        UserAvatar(
          avatarRevision: 'same-private-avatar',
          avatarLoader: () {
            loads++;
            return loads == 1 ? Future.value(first.path) : pending.future;
          },
        ),
      ),
    );
    await tester.pumpWidget(page());
    await _waitForAvatar(tester);
    account.setAuthenticatedUser('second');
    await tester.pumpWidget(page());
    expect(loads, 2);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
    pending.complete(second.path);
    await _waitForAvatar(tester);
    expect(_filePath(tester.widget<Image>(find.byType(Image))), second.path);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unmounting during a load does not update a disposed widget', (
    tester,
  ) async {
    final pending = Completer<String?>();
    await tester.pumpWidget(
      _host(
        UserAvatar(
          avatarRevision: 'disposed-load',
          avatarLoader: () => pending.future,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete('unused.jpg');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Widget _host(UserAvatar avatar) => MaterialApp(home: Scaffold(body: avatar));

File _localAvatar() {
  final directory = Directory.systemTemp.createTempSync('yap-avatar-state-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return File(
    'assets/logo/logo_yap_chat.png',
  ).copySync('${directory.path}/avatar.png');
}

Future<void> _waitForAvatar(WidgetTester tester, {String? path}) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.pump();
    final images = tester.widgetList<Image>(find.byType(Image));
    if (images.isNotEmpty &&
        (path == null || _filePath(images.single) == path) &&
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null)) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('A decoded avatar frame was not painted.');
}

String _filePath(Image image) {
  final resized = image.image as ResizeImage;
  return (resized.imageProvider as FileImage).file.path;
}
