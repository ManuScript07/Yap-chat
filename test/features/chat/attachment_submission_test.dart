import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/widgets/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late List<String> paths;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('attachment-submission-');
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
      '/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    );
    paths = List.generate(2, (index) {
      final file = File('${directory.path}/$index.png')..writeAsBytesSync(png);
      return file.path;
    });
  });

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    directory.deleteSync(recursive: true);
  });

  for (final orientation in ['portrait', 'landscape']) {
    final size = orientation == 'portrait'
        ? const Size(480, 900)
        : const Size(900, 480);

    group(orientation, () {
      testWidgets('refusal preserves images and retries the same selection', (
        tester,
      ) async {
        final submissions = <AttachmentSelection>[];
        final harness = _Harness(paths);
        await harness.open(
          tester,
          size,
          onSubmit: (selection) async {
            submissions.add(selection);
            return submissions.length > 1;
          },
        );
        await tester.tap(_card(paths[1]));
        await tester.pump();

        await tester.tap(_send);
        await tester.pumpAndSettle();

        expect(submissions.single.imagePaths, paths);
        expect(harness.returned, isFalse);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
        expect(find.text('Send (2)'), findsOneWidget);
        expect(tester.widget<FilledButton>(_send).onPressed, isNotNull);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);

        await tester.tap(_send);
        await tester.pumpAndSettle();

        expect(submissions, hasLength(2));
        expect(submissions.last.imagePaths, paths);
        expect(harness.returned, isTrue);
        expect(harness.result, isNull);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('partial six-image send retries only the unqueued image', (
        tester,
      ) async {
        final images = _sixImages(paths);
        final queued = <String>[];
        final submissions = <List<String>>[];
        final harness = _Harness(images);
        await harness.open(
          tester,
          size,
          onSubmit: (selection) async {
            final requested = List<String>.of(selection.imagePaths!);
            submissions.add(requested);
            if (submissions.length == 1) {
              queued.addAll(requested.take(5));
              throw PartialImageSendException(
                queuedPaths: requested.take(5),
                remainingPaths: requested.skip(5),
                cause: StateError('second batch could not be queued'),
              );
            }
            queued.addAll(requested);
            return true;
          },
        );
        await _selectAllImages(tester, images);

        await tester.tap(_send);
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(tester.element(_send))!;
        expect(submissions, [images]);
        expect(queued, images.take(5).toList());
        expect(harness.returned, isFalse);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text(l10n.chatImagesPartiallySent), findsOneWidget);
        expect(find.text(l10n.chatsActionFailed), findsNothing);
        expect(find.text(l10n.chatSendFiles(1)), findsOneWidget);
        expect(
          find.descendant(
            of: _card(images.last),
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );
        expect(harness.media.deleted, isEmpty);

        // Even an old enabled callback cannot enqueue the remainder twice.
        final retry = tester.widget<FilledButton>(_send).onPressed!;
        retry();
        retry();
        await tester.pumpAndSettle();

        expect(submissions, [
          images,
          [images.last],
        ]);
        expect(queued, images);
        expect(queued.toSet(), hasLength(6));
        expect(harness.returned, isTrue);
        expect(harness.result, isNull);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      });

      for (final failure in ['refusal', 'error', 'repeated partial']) {
        testWidgets('retry $failure keeps only the partial-send remainder', (
          tester,
        ) async {
          final images = _sixImages(paths);
          final queued = <String>[];
          final submissions = <List<String>>[];
          final partial = PartialImageSendException(
            queuedPaths: images.take(5),
            remainingPaths: images.skip(5),
            cause: StateError('second batch could not be queued'),
          );
          final harness = _Harness(images);
          await harness.open(
            tester,
            size,
            onSubmit: (selection) async {
              final requested = List<String>.of(selection.imagePaths!);
              submissions.add(requested);
              if (submissions.length == 1) {
                queued.addAll(requested.take(5));
                throw partial;
              }
              if (submissions.length < 4) {
                if (failure == 'error') throw StateError('retry failed');
                // Replayed progress must not reselect already queued images.
                if (failure == 'repeated partial') throw partial;
                return false;
              }
              queued.addAll(requested);
              return true;
            },
          );
          await _selectAllImages(tester, images);
          await tester.tap(_send);
          await tester.pumpAndSettle();

          for (var attempt = 0; attempt < 2; attempt++) {
            await tester.tap(_send);
            await tester.pumpAndSettle();

            final l10n = AppLocalizations.of(tester.element(_send))!;
            expect(submissions.last, [images.last]);
            expect(queued, images.take(5).toList());
            expect(harness.returned, isFalse);
            expect(find.byType(BottomSheet), findsOneWidget);
            expect(find.text(l10n.chatSendFiles(1)), findsOneWidget);
            expect(tester.widget<FilledButton>(_send).onPressed, isNotNull);
            expect(tester.widget<GlassButton>(_delete).onPressed, isNotNull);
            if (failure == 'error') {
              expect(find.text(l10n.chatsActionFailed), findsOneWidget);
            } else if (failure == 'repeated partial') {
              expect(find.text(l10n.chatImagesPartiallySent), findsOneWidget);
            }
          }

          await tester.tap(_send);
          await tester.pumpAndSettle();

          expect(submissions, [
            images,
            [images.last],
            [images.last],
            [images.last],
          ]);
          expect(queued, images);
          expect(queued.toSet(), hasLength(6));
          expect(harness.media.deleted, isEmpty);
          expect(harness.returned, isTrue);
          expect(harness.result, isNull);
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }

      for (final disposeFirst in [false, true]) {
        testWidgets(
          'partial failure after dismissal ${disposeFirst ? 'and disposal' : 'during closing'} preserves the next route',
          (tester) async {
            final images = _sixImages(paths);
            final gate = Completer<void>();
            final queued = <String>[];
            final submissions = <List<String>>[];
            var completed = false;
            final harness = _Harness(images);
            await harness.open(
              tester,
              size,
              onSubmit: (selection) async {
                final requested = List<String>.of(selection.imagePaths!);
                submissions.add(requested);
                await gate.future;
                queued.addAll(requested.take(5));
                completed = true;
                throw PartialImageSendException(
                  queuedPaths: requested.take(5),
                  remainingPaths: requested.skip(5),
                  cause: StateError('late second-batch failure'),
                );
              },
            );
            await _selectAllImages(tester, images);
            await tester.tap(_send);
            await tester.pump();
            harness.navigator.currentState!.pop();
            if (disposeFirst) await tester.pumpAndSettle();
            harness.pushOtherRoute();

            gate.complete();
            await tester.pumpAndSettle();

            expect(completed, isTrue);
            expect(submissions, [images]);
            expect(queued, images.take(5).toList());
            expect(harness.returned, isTrue);
            expect(harness.result, isNull);
            expect(find.text('other route'), findsOneWidget);
            expect(find.byType(SnackBar), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets(
        'partial failure beneath another route retains the remainder',
        (tester) async {
          final images = _sixImages(paths);
          final gate = Completer<void>();
          final queued = <String>[];
          final submissions = <List<String>>[];
          final harness = _Harness(images);
          await harness.open(
            tester,
            size,
            onSubmit: (selection) async {
              final requested = List<String>.of(selection.imagePaths!);
              submissions.add(requested);
              if (submissions.length == 1) {
                await gate.future;
                queued.addAll(requested.take(5));
                throw PartialImageSendException(
                  queuedPaths: requested.take(5),
                  remainingPaths: requested.skip(5),
                  cause: StateError('second batch failed under another route'),
                );
              }
              queued.addAll(requested);
              return true;
            },
          );
          await _selectAllImages(tester, images);
          final sheetRoute = ModalRoute.of(tester.element(_send))!;
          await tester.tap(_send);
          await tester.pump();
          harness.pushOtherRoute();
          await tester.pumpAndSettle();

          gate.complete();
          await tester.pumpAndSettle();

          expect(submissions, [images]);
          expect(queued, images.take(5).toList());
          expect(harness.returned, isFalse);
          expect(sheetRoute.isActive, isTrue);
          expect(sheetRoute.isCurrent, isFalse);
          expect(find.text('other route'), findsOneWidget);
          harness.navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(sheetRoute.isCurrent, isTrue);
          final l10n = AppLocalizations.of(tester.element(_send))!;
          expect(find.text(l10n.chatSendFiles(1)), findsOneWidget);

          await tester.tap(_send);
          await tester.pumpAndSettle();

          expect(submissions, [
            images,
            [images.last],
          ]);
          expect(queued, images);
          expect(queued.toSet(), hasLength(6));
          expect(harness.returned, isTrue);
          expect(harness.result, isNull);
          expect(find.text('chat'), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'partial failure is handled after the entire widget is disposed',
        (tester) async {
          final images = _sixImages(paths);
          final gate = Completer<void>();
          final queued = <String>[];
          var completed = false;
          final harness = _Harness(images);
          await harness.open(
            tester,
            size,
            onSubmit: (selection) async {
              final requested = List<String>.of(selection.imagePaths!);
              await gate.future;
              queued.addAll(requested.take(5));
              completed = true;
              throw PartialImageSendException(
                queuedPaths: requested.take(5),
                remainingPaths: requested.skip(5),
                cause: StateError('second batch failed after disposal'),
              );
            },
          );
          await _selectAllImages(tester, images);
          await tester.tap(_send);
          await tester.pumpWidget(const SizedBox());

          gate.complete();
          await tester.pumpAndSettle();

          expect(completed, isTrue);
          expect(queued, images.take(5).toList());
          expect(find.byType(SnackBar), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'real limit dialog overlays the sheet and preserves its remainder',
        (tester) async {
          final images = _sixImages(paths);
          final queued = <String>[];
          final submissions = <List<String>>[];
          final harness = _Harness(images);
          await harness.open(
            tester,
            size,
            onSubmit: (selection) async {
              final requested = List<String>.of(selection.imagePaths!);
              submissions.add(requested);
              if (submissions.length == 1) {
                queued.addAll(requested.take(5));
                throw PartialImageSendException(
                  queuedPaths: requested.take(5),
                  remainingPaths: requested.skip(5),
                  cause: StateError('second batch could not be queued'),
                );
              }
              if (submissions.length == 2) {
                // The parent owns limit presentation. Use its real dialog while
                // returning false, as the ChatBloc listener does in the chat page.
                unawaited(
                  showChatLimitReachedDialog(
                    harness.navigator.currentContext!,
                    limit: ChatLimitReachedException.maximum,
                  ),
                );
                return false;
              }
              queued.addAll(requested);
              return true;
            },
          );
          await _selectAllImages(tester, images);
          await tester.tap(_send);
          await tester.pumpAndSettle();
          final sheetRoute = ModalRoute.of(tester.element(_send))!;
          final l10n = AppLocalizations.of(tester.element(_send))!;

          await tester.tap(_send);
          await tester.pumpAndSettle();

          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text(l10n.chatsLimitTitle), findsOneWidget);
          expect(
            find.text(
              l10n.chatsLimitContent(ChatLimitReachedException.maximum),
            ),
            findsOneWidget,
          );
          expect(find.text(l10n.chatsLimitDismiss), findsOneWidget);
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(sheetRoute.isActive, isTrue);
          expect(sheetRoute.isCurrent, isFalse);
          expect(
            ModalRoute.of(tester.element(find.byType(AlertDialog)))!.isCurrent,
            isTrue,
          );
          expect(harness.returned, isFalse);
          expect(submissions, [
            images,
            [images.last],
          ]);
          expect(queued, images.take(5).toList());

          await tester.tap(find.text(l10n.chatsLimitDismiss));
          await tester.pumpAndSettle();

          expect(find.byType(AlertDialog), findsNothing);
          expect(sheetRoute.isCurrent, isTrue);
          expect(find.text(l10n.chatSendFiles(1)), findsOneWidget);
          expect(tester.widget<FilledButton>(_send).onPressed, isNotNull);
          await tester.tap(_send);
          await tester.pumpAndSettle();

          expect(submissions, [
            images,
            [images.last],
            [images.last],
          ]);
          expect(queued, images);
          expect(queued.toSet(), hasLength(6));
          expect(harness.returned, isTrue);
          expect(harness.result, isNull);
          expect(find.text('chat'), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );

      for (final synchronous in [true, false]) {
        testWidgets(
          '${synchronous ? 'synchronous' : 'asynchronous'} callback error keeps images for retry',
          (tester) async {
            final submissions = <AttachmentSelection>[];
            final harness = _Harness(paths);
            await harness.open(
              tester,
              size,
              onSubmit: (selection) {
                submissions.add(selection);
                if (submissions.length > 1) return Future.value(true);
                if (synchronous) throw StateError('submission failed');
                return Future<bool>.error(StateError('submission failed'));
              },
            );

            await tester.tap(_send);
            await tester.pumpAndSettle();

            expect(harness.returned, isFalse);
            expect(find.byIcon(Icons.check_rounded), findsOneWidget);
            expect(find.byType(SnackBar), findsOneWidget);
            expect(
              find.text(
                'Could not complete the action. Check your internet connection',
              ),
              findsOneWidget,
            );
            expect(tester.widget<FilledButton>(_send).onPressed, isNotNull);

            await tester.tap(_send);
            await tester.pumpAndSettle();

            expect(submissions, hasLength(2));
            expect(submissions.last.imagePaths, [paths.first]);
            expect(harness.returned, isTrue);
            expect(harness.result, isNull);
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets('double tap submits once and locks every attachment control', (
        tester,
      ) async {
        final gate = Completer<bool>();
        final submissions = <AttachmentSelection>[];
        final harness = _Harness(paths);
        await harness.open(
          tester,
          size,
          onSubmit: (selection) {
            submissions.add(selection);
            return gate.future;
          },
        );
        final sendAgain = tester.widget<FilledButton>(_send).onPressed!;
        final selectAgain = tester
            .widget<GestureDetector>(
              find
                  .descendant(
                    of: _card(paths[1]),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
            )
            .onTap!;
        final deleteAgain = tester.widget<GlassButton>(_delete).onPressed!;
        final cameraAgain = tester
            .widget<InkWell>(_action(Icons.camera_alt_rounded))
            .onTap!;
        final galleryAgain = tester
            .widget<InkWell>(_action(Icons.image_rounded))
            .onTap!;
        final locationAgain = tester
            .widget<InkWell>(_action(Icons.near_me))
            .onTap!;

        // No pump between taps: the old enabled callbacks must also be guarded.
        await tester.tap(_send);
        await tester.tap(_send);
        sendAgain();
        selectAgain();
        deleteAgain();
        cameraAgain();
        galleryAgain();
        locationAgain();
        await tester.pump();

        expect(submissions, hasLength(1));
        expect(submissions.single.imagePaths, [paths.first]);
        expect(tester.widget<FilledButton>(_send).onPressed, isNull);
        expect(tester.widget<GlassButton>(_delete).onPressed, isNull);
        for (final icon in [
          Icons.camera_alt_rounded,
          Icons.image_rounded,
          Icons.near_me,
        ]) {
          expect(tester.widget<InkWell>(_action(icon)).onTap, isNull);
        }
        for (final path in paths) {
          expect(
            tester
                .widget<GestureDetector>(
                  find
                      .descendant(
                        of: _card(path),
                        matching: find.byType(GestureDetector),
                      )
                      .first,
                )
                .onTap,
            isNull,
          );
        }
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(harness.media.deleted, isEmpty);
        expect(harness.media.cameraStarts, 0);
        expect(harness.location.reads, 0);

        gate.complete(false);
        await tester.pumpAndSettle();

        expect(harness.returned, isFalse);
        expect(tester.widget<FilledButton>(_send).onPressed, isNotNull);
        expect(tester.widget<GlassButton>(_delete).onPressed, isNotNull);
        await tester.tap(_card(paths[1]));
        await tester.pump();
        expect(find.text('Send (2)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'accepted submission closes with null, never legacy selection',
        (tester) async {
          var submissions = 0;
          final harness = _Harness(paths);
          await harness.open(
            tester,
            size,
            onSubmit: (_) async {
              submissions++;
              return true;
            },
          );

          await tester.tap(_send);
          await tester.pumpAndSettle();

          expect(submissions, 1);
          expect(harness.returned, isTrue);
          expect(harness.result, isNull);
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.text('chat'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('legacy images return their selection without a callback', (
        tester,
      ) async {
        final harness = _Harness(paths);
        await harness.open(tester, size);
        await tester.tap(_card(paths[1]));
        await tester.pump();
        final sendAgain = tester.widget<FilledButton>(_send).onPressed!;
        await tester.tap(_send);
        sendAgain();
        await tester.pumpAndSettle();

        expect(harness.returned, isTrue);
        expect(harness.result!.imagePaths, paths);
        expect(harness.result!.location, isNull);
        expect(find.byType(BottomSheet), findsNothing);
      });

      for (final failure in ['refusal', 'error']) {
        testWidgets(
          'location $failure retries confirmed coordinates without GPS',
          (tester) async {
            final submissions = <AttachmentSelection>[];
            final retry = Completer<bool>();
            final harness = _Harness(paths);
            await harness.open(
              tester,
              size,
              onSubmit: (selection) async {
                submissions.add(selection);
                if (submissions.length > 1) return retry.future;
                if (failure == 'error') throw StateError('location failed');
                return false;
              },
            );

            await _confirmLocation(tester);
            await tester.pumpAndSettle();

            expect(harness.returned, isFalse);
            expect(harness.location.reads, 1);
            expect(submissions.single.location!.latitude, 55);
            expect(submissions.single.location!.longitude, 37);
            expect(find.byIcon(Icons.check_rounded), findsOneWidget);

            await tester.tap(find.byIcon(Icons.near_me));
            await tester.tap(find.byIcon(Icons.near_me));
            await tester.pump();

            expect(submissions, hasLength(2));
            expect(submissions.last.location, same(submissions.first.location));
            expect(harness.location.reads, 1);
            expect(find.byType(AlertDialog), findsNothing);
            expect(tester.widget<FilledButton>(_send).onPressed, isNull);

            retry.complete(true);
            await tester.pumpAndSettle();

            expect(harness.returned, isTrue);
            expect(harness.result, isNull);
            expect(find.byType(BottomSheet), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets('legacy location returns confirmed coordinates', (
        tester,
      ) async {
        final harness = _Harness(paths);
        await harness.open(tester, size);

        await _confirmLocation(tester);
        await tester.pumpAndSettle();

        expect(harness.returned, isTrue);
        expect(harness.result!.imagePaths, isNull);
        expect(harness.result!.location!.latitude, 55);
        expect(harness.result!.location!.longitude, 37);
        expect(harness.location.reads, 1);
        expect(find.byType(BottomSheet), findsNothing);
      });

      testWidgets('cancelling location never submits or caches coordinates', (
        tester,
      ) async {
        var submissions = 0;
        final harness = _Harness(paths);
        await harness.open(
          tester,
          size,
          onSubmit: (_) async {
            submissions++;
            return false;
          },
        );
        await _openLocationConfirmation(tester);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(submissions, 0);

        await _confirmLocation(tester);
        await tester.pumpAndSettle();
        expect(submissions, 1);
        expect(harness.location.reads, 2);
      });

      for (final action in [
        'selection',
        'delete',
        'images',
        'gallery',
        'camera',
      ]) {
        testWidgets('$action supersedes a refused location', (tester) async {
          _mockPickers();
          final submissions = <AttachmentSelection>[];
          final harness = _Harness(paths);
          await harness.open(
            tester,
            size,
            onSubmit: (selection) async {
              submissions.add(selection);
              return false;
            },
          );
          await _confirmLocation(tester);
          await tester.pumpAndSettle();

          switch (action) {
            case 'selection':
              await tester.tap(_card(paths[1]));
            case 'delete':
              await tester.tap(_delete);
            case 'images':
              await tester.tap(_send);
            case 'gallery':
              await tester.tap(find.byIcon(Icons.image_rounded));
            case 'camera':
              await tester.tap(find.byIcon(Icons.camera_alt_rounded));
          }
          await tester.pumpAndSettle();
          harness.location.position = _position(56, 38);

          await _openLocationConfirmation(tester);
          expect(harness.location.reads, 2);
          await tester.tap(_confirm);
          await tester.pumpAndSettle();

          expect(submissions.last.location!.latitude, 56);
          expect(submissions.last.location!.longitude, 38);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('late GPS result cannot override a newer image selection', (
        tester,
      ) async {
        final gps = Completer<Position>();
        final submissions = <AttachmentSelection>[];
        final harness = _Harness(paths)..location.pending = gps.future;
        await harness.open(
          tester,
          size,
          onSubmit: (selection) async {
            submissions.add(selection);
            return false;
          },
        );

        await tester.tap(find.byIcon(Icons.near_me));
        await tester.pump();
        await tester.tap(_card(paths[1]));
        await tester.pump();
        gps.complete(_position(55, 37));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(submissions, isEmpty);
        await tester.tap(_send);
        await tester.pumpAndSettle();
        expect(submissions.single.imagePaths, paths);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'older GPS completion cannot clear a newer location request',
        (tester) async {
          final oldGps = Completer<Position>();
          final newGps = Completer<Position>();
          final submissions = <AttachmentSelection>[];
          final harness = _Harness(paths)..location.pending = oldGps.future;
          await harness.open(
            tester,
            size,
            onSubmit: (selection) async {
              submissions.add(selection);
              return false;
            },
          );
          await tester.tap(find.byIcon(Icons.near_me));
          await tester.pump();
          await tester.tap(_card(paths[1]));
          await tester.pump();
          harness.location.pending = newGps.future;
          await tester.tap(find.byIcon(Icons.near_me));
          await tester.pump();

          oldGps.complete(_position(55, 37));
          await tester.pump();
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);

          newGps.complete(_position(56, 38));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(_confirm);
          await tester.pumpAndSettle();

          expect(harness.location.reads, 2);
          expect(submissions.single.location!.latitude, 56);
          expect(submissions.single.location!.longitude, 38);
          expect(tester.takeException(), isNull);
        },
      );

      for (final disposeFirst in [false, true]) {
        for (final outcome in ['success', 'refusal', 'error']) {
          testWidgets(
            '$outcome after dismissal ${disposeFirst ? 'and disposal' : 'during closing'} preserves the next route',
            (tester) async {
              final gate = Completer<void>();
              var completed = false;
              final harness = _Harness(paths);
              await harness.open(
                tester,
                size,
                onSubmit: (_) async {
                  await gate.future;
                  completed = true;
                  if (outcome == 'error') throw StateError('late failure');
                  return outcome == 'success';
                },
              );
              await tester.tap(_send);
              await tester.pump();
              harness.navigator.currentState!.pop();
              if (disposeFirst) await tester.pumpAndSettle();
              harness.pushOtherRoute();

              gate.complete();
              await tester.pumpAndSettle();

              expect(completed, isTrue);
              expect(harness.returned, isTrue);
              expect(harness.result, isNull);
              expect(find.text('other route'), findsOneWidget);
              expect(find.byType(SnackBar), findsNothing);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }

      testWidgets('success beneath another route removes only the sheet', (
        tester,
      ) async {
        final gate = Completer<bool>();
        final harness = _Harness(paths);
        await harness.open(tester, size, onSubmit: (_) => gate.future);
        await tester.tap(_send);
        await tester.pump();
        harness.pushOtherRoute();
        await tester.pumpAndSettle();

        gate.complete(true);
        await tester.pumpAndSettle();

        expect(harness.returned, isTrue);
        expect(harness.result, isNull);
        expect(find.text('other route'), findsOneWidget);
        harness.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('chat'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'submission also completes after the whole widget is disposed',
        (tester) async {
          final gate = Completer<void>();
          var completed = false;
          final harness = _Harness(paths);
          await harness.open(
            tester,
            size,
            onSubmit: (_) async {
              await gate.future;
              completed = true;
              return true;
            },
          );
          await tester.tap(_send);
          await tester.pumpWidget(const SizedBox());

          gate.complete();
          await tester.pumpAndSettle();

          expect(completed, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    });
  }
}

final _send = find.descendant(
  of: find.byType(BottomSheet),
  matching: find.byType(FilledButton),
);
final _delete = find.byType(GlassButton);
final _confirm = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(FilledButton),
);

Finder _card(String path) => find.byKey(ValueKey('recent-media:$path'));

Finder _action(IconData icon) =>
    find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell));

List<String> _sixImages(List<String> existingPaths) {
  final source = File(existingPaths.first);
  final png = source.readAsBytesSync();
  return List.generate(6, (index) {
    if (index < existingPaths.length) return existingPaths[index];
    final file = File('${source.parent.path}/$index.png')
      ..writeAsBytesSync(png);
    return file.path;
  });
}

Future<void> _selectAllImages(WidgetTester tester, List<String> images) async {
  final mediaScroll = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    ),
  );
  // The harness preselects the first image; reveal later, lazily built cards.
  for (final path in images.skip(1)) {
    await tester.scrollUntilVisible(_card(path), 140, scrollable: mediaScroll);
    await tester.tap(_card(path));
    await tester.pump();
  }
  final l10n = AppLocalizations.of(tester.element(_send))!;
  expect(find.text(l10n.chatSendFiles(images.length)), findsOneWidget);
}

Future<void> _openLocationConfirmation(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.near_me));
  await tester.pump();
  // GPS loading intentionally remains active through the confirmation dialog.
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _confirmLocation(WidgetTester tester) async {
  await _openLocationConfirmation(tester);
  await tester.tap(_confirm);
  await tester.pump();
}

void _mockPickers() {
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(picker, (_) async => null);
  messenger.setMockMethodCallHandler(permissions, (call) async {
    if (call.method == 'requestPermissions') return <int, int>{1: 1};
    if (call.method == 'checkPermissionStatus') return 1;
    throw StateError('Unexpected permission call: ${call.method}');
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(picker, null);
    messenger.setMockMethodCallHandler(permissions, null);
  });
}

class _Harness {
  _Harness(List<String> paths) : media = _Media(paths);

  final navigator = GlobalKey<NavigatorState>();
  final _Media media;
  final location = _Location();
  bool returned = false;
  AttachmentSelection? result;

  Future<void> open(
    WidgetTester tester,
    Size size, {
    Future<bool> Function(AttachmentSelection)? onSubmit,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ILocalMediaRepository>.value(value: media),
          RepositoryProvider<ILocationRepository>.value(value: location),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const Text('chat'),
                  TextButton(
                    onPressed: () async {
                      result = await showAttachmentBottomSheet(
                        context,
                        chatId: 'chat-1',
                        peerName: 'Peer',
                        initiallySelectedPath: media.paths.first,
                        onSubmit: onSubmit,
                      );
                      returned = true;
                    },
                    child: const Text('open attachments'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open attachments'));
    await tester.pumpAndSettle();
  }

  void pushOtherRoute() {
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('other route')),
        ),
      ),
    );
  }
}

class _Media extends Fake implements ILocalMediaRepository {
  _Media(this.paths);

  final List<String> paths;
  final deleted = <String>[];
  int cameraStarts = 0;

  @override
  List<String> getRecentMediaPaths() => List.of(paths);

  @override
  Future<void> deleteMedia(String path) async {
    deleted.add(path);
  }

  @override
  Future<void> savePendingChatId(String chatId) async {
    cameraStarts++;
  }

  @override
  Future<void> clearPendingChatId() async {}
}

class _Location extends Fake implements ILocationRepository {
  int reads = 0;
  Position position = _position(55, 37);
  Future<Position>? pending;

  @override
  Future<Position> getCurrentPosition() async {
    reads++;
    final pendingPosition = pending;
    if (pendingPosition != null) return pendingPosition;
    return position;
  }
}

Position _position(double latitude, double longitude) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime(2026, 10, 27),
  altitude: 0,
  altitudeAccuracy: 0,
  accuracy: 10,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
