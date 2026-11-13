import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:yap_chat/app/app.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/nearby/nearby.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      'navigation returns nearby to top without refresh or page requests $size',
      (tester) async {
        final navigation = NavigationScrollToTopController();
        final f = await _mount(
          tester,
          size: size,
          count: 150,
          navigation: navigation,
        );
        expect(
          tester
              .widgetList<UserAvatar>(find.byType(UserAvatar))
              .every((avatar) => avatar.borderRadius == 8),
          isTrue,
        );
        final controller = tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!;
        controller.jumpTo(controller.position.maxScrollExtent - 100);
        await tester.pump();
        final attempts = f.cubit.pageAttempts;
        final rows = f.cubit.state.people;
        final revision = f.cubit.state.feedRevision;
        final done = navigation.scrollToTop(NavigationScrollTarget.nearby);
        await tester.pump();
        final before = controller.offset;
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.offset, inExclusiveRange(0, before));
        await tester.pumpAndSettle();
        await done;
        expect(controller.offset, 0);
        expect(f.cubit.pageAttempts, attempts);
        expect(f.cubit.refreshCalls, 0);
        expect(f.cubit.state.people, same(rows));
        expect(f.cubit.state.feedRevision, revision);
        expect(tester.takeException(), isNull);
        await f.close(tester);
        navigation.dispose();
      },
    );
  }
  testWidgets('hidden nearby feed ignores navigation scroll commands', (
    tester,
  ) async {
    final navigation = NavigationScrollToTopController();
    final f = await _mount(tester, count: 60, navigation: navigation);
    final controller = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    controller.jumpTo(500);
    f.cubit.show(
      f.cubit.state.copyWith(status: NearbyStatus.visibilityDisabled),
    );
    await tester.pump();
    final offset = controller.offset;
    await navigation.scrollToTop(NavigationScrollTarget.nearby);
    expect(controller.offset, offset);
    expect(f.cubit.refreshCalls, 0);
    await f.close(tester);
    navigation.dispose();
  });
  for (final size in [const Size(360, 800), const Size(844, 390)]) {
    for (final locale in ['ru', 'en']) {
      testWidgets(
        'nearby connection title is passive and compact at $size $locale',
        (tester) async {
          final status = AppConnectionStatus(
            accountSessionController: AccountSessionController(
              initialUserId: 'u',
            ),
            presentationDelay: Duration.zero,
          );
          addTearDown(status.dispose);
          final f = await _mount(
            tester,
            size: size,
            count: 30,
            locale: locale,
            connectionStatus: status,
          );
          final header = find.byType(PrimaryAppBar);
          expect(
            tester.widget<PrimaryAppBar>(header).preferredSize.height,
            PrimaryHeaderGeometry.compactHeight,
          );
          final first = find.byKey(const ValueKey('p0'));
          final before = tester.getRect(first);
          final avatar = find.descendant(
            of: first,
            matching: find.byType(UserAvatar),
          );
          final previousWidget = tester.widget(avatar);
          status.reportNetworkAvailability(false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(AnimatedConnectingText), findsOneWidget);
          expect(tester.getRect(first), before);
          expect(tester.widget(avatar), same(previousWidget));
          expect(f.cubit.refreshCalls, 0);
          expect(f.cubit.loadCalls, 0);
          expect(tester.takeException(), isNull);
          await f.close(tester);
        },
      );
    }
  }
  testWidgets(
    'a profile navigation that does not start leaves labels visible',
    (tester) async {
      final f = await _mount(tester, count: 30, openProfile: (_, _) async {});
      final avatar = find.descendant(
        of: find.byKey(const ValueKey('p0')),
        matching: find.byType(UserAvatar),
      );
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byKey(const ValueKey('nearby-name-p0')),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
  testWidgets(
    'disposing during post-Hero label restoration releases its ticker',
    (tester) async {
      late MaterialPageRoute<void> route;
      final f = await _mount(
        tester,
        count: 30,
        openProfile: (context, _) async {
          route = MaterialPageRoute<void>(builder: (_) => const Scaffold());
          await Navigator.of(context).push(route);
        },
      );
      final avatar = find.descendant(
        of: find.byKey(const ValueKey('p0')),
        matching: find.byType(UserAvatar),
      );
      final navigator = Navigator.of(tester.element(avatar));
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pump();
      double opacity() => tester
          .widget<FadeTransition>(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('nearby-name-p0'),
                    skipOffstage: false,
                  ),
                  matching: find.byType(FadeTransition, skipOffstage: false),
                  skipOffstage: false,
                )
                .first,
          )
          .opacity
          .value;
      // Flutter's Material transition may use spring settling beyond the
      // nominal duration; wait for the label phase, not a fixed route delay.
      for (var frame = 0; frame < 160 && opacity() == 0; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(opacity(), inExclusiveRange(0, 1));
      await f.close(tester);
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets('profile push and pop change only the profile presence scope', (
    tester,
  ) async {
    final presence = _CountingPresence();
    final f = await _mount(
      tester,
      count: 30,
      presenceRepository: presence,
      openProfile: (context, _) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PresenceWatchScope(
              scopeName: 'viewed-profile',
              userIds: ['p0'],
              child: Scaffold(),
            ),
          ),
        );
      },
    );
    expect(presence.setCalls, 1);
    for (var i = 0; i < 3; i++) {
      final avatar = find.descendant(
        of: find.byKey(const ValueKey('p0')),
        matching: find.byType(UserAvatar),
      );
      final navigator = Navigator.of(tester.element(avatar));
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(presence.setCalls, i + 2);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(presence.removeCalls, i + 1);
    }
    expect(
      presence.nearbySetCalls,
      1,
      reason: 'UI fades must not register the feed audience again',
    );
    await f.close(tester);
  });
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      'profile details follow push and pop without replacing avatar at $size',
      (tester) async {
        final f = await _mount(
          tester,
          size: size,
          count: 30,
          openProfile: (context, _) async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
          },
        );
        final avatar = find.descendant(
          of: find.byKey(const ValueKey('p0')),
          matching: find.byType(UserAvatar),
        );
        final avatarElement = tester.element(avatar);
        final otherAvatar = find.descendant(
          of: find.byKey(const ValueKey('p1')),
          matching: find.byType(UserAvatar),
        );
        final navigator = Navigator.of(tester.element(avatar));
        double opacity(String part) => tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of: find.byKey(
                      ValueKey('nearby-$part-p0'),
                      skipOffstage: false,
                    ),
                    matching: find.byType(FadeTransition, skipOffstage: false),
                    skipOffstage: false,
                  )
                  .first,
            )
            .opacity
            .value;
        expect(opacity('name'), 1);
        expect(opacity('presence'), 1);
        for (var attempt = 0; attempt < 2; attempt++) {
          final otherAvatarWidget = tester.widget(otherAvatar);
          await tester.tap(avatar);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 35));
          expect(opacity('name'), inExclusiveRange(0, 1));
          expect(opacity('presence'), closeTo(opacity('name'), .00001));
          expect(
            tester.widget(otherAvatar),
            same(otherAvatarWidget),
            reason:
                'profile navigation must not rebuild untouched avatar widgets',
          );
          final other = tester.widget<FadeTransition>(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('nearby-name-p1'),
                    skipOffstage: false,
                  ),
                  matching: find.byType(FadeTransition, skipOffstage: false),
                  skipOffstage: false,
                )
                .first,
          );
          expect(other.opacity.value, 1);
          final otherPresence = tester.widget<FadeTransition>(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('nearby-presence-p1'),
                    skipOffstage: false,
                  ),
                  matching: find.byType(FadeTransition, skipOffstage: false),
                  skipOffstage: false,
                )
                .first,
          );
          expect(otherPresence.opacity.value, 1);
          await tester.pump(const Duration(milliseconds: 70));
          expect(
            opacity('name'),
            0,
            reason: 'labels must not float over the empty Hero source',
          );
          await tester.pumpAndSettle();
          expect(opacity('name'), 0);
          expect(opacity('presence'), 0);
          navigator.pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 35));
          expect(
            opacity('name'),
            lessThan(.1),
            reason:
                'do not expose labels on the empty avatar placeholder at pop start',
          );
          var sawPartialReturn = false;
          var previousOpacity = 0.0;
          var returnFrames = 0;
          for (var frame = 0; frame < 80 && opacity('name') < 1; frame++) {
            await tester.pump(const Duration(milliseconds: 8));
            expect(opacity('name'), greaterThanOrEqualTo(previousOpacity));
            expect(opacity('name') - previousOpacity, lessThan(.1));
            previousOpacity = opacity('name');
            if (opacity('name') > 0 && opacity('name') < 1) {
              returnFrames++;
              sawPartialReturn = true;
              expect(opacity('presence'), closeTo(opacity('name'), .00001));
            }
          }
          expect(sawPartialReturn, isTrue);
          expect(
            returnFrames,
            greaterThan(12),
            reason:
                'return must span a smooth independent fade, not the last few Hero frames',
          );
          await tester.pumpAndSettle();
          expect(opacity('name'), 1);
          expect(tester.element(avatar), same(avatarElement));
        }
        expect(tester.takeException(), isNull);
        expect(f.cubit.refreshCalls, 0);
        expect(f.cubit.loadCalls, 0);
        await f.close(tester);
      },
    );
  }
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('hidden feed uses existing blur panel at $size', (
      tester,
    ) async {
      final f = await _mount(tester, size: size, count: 30);
      f.cubit.show(
        f.cubit.state.copyWith(status: NearbyStatus.visibilityDisabled),
      );
      await tester.pumpAndSettle();
      expect(find.text('вы скрыты из людей рядом'), findsOneWidget);
      expect(find.text('включить'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets);
      final button = find.widgetWithText(FilledButton, 'включить');
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }

  testWidgets('automatic quota recovery never becomes a repeating poll', (
    tester,
  ) async {
    final f = await _mount(tester, count: 30);
    f.cubit.quotaDenials = 10;
    f.cubit.quotaDelay = const Duration(seconds: 1);
    _position(tester).jumpTo(_position(tester).maxScrollExtent - 140);
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -60));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(f.cubit.pageAttempts, 2);
    await tester.pump(const Duration(minutes: 3));
    await tester.pump();
    expect(f.cubit.pageAttempts, 2);
    expect(f.cubit.loadCalls, 0);
    await f.close(tester);
  });

  for (final cancel in ['none', 'close', 'filter', 'background']) {
    testWidgets(
      'quota-delayed page resumes once and respects cancellation=$cancel',
      (tester) async {
        final f = await _mount(tester, count: 30);
        f.cubit.quotaDenials = 1;
        f.cubit.quotaDelay = const Duration(seconds: 1);
        final position = _position(tester);
        position.jumpTo(position.maxScrollExtent - 140);
        await tester.pump();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -60));
        await tester.pump();
        await tester.pump();
        expect(f.cubit.pageAttempts, 1);
        if (cancel == 'close') await f.close(tester);
        if (cancel == 'filter') {
          f.cubit.show(
            f.cubit.state.copyWith(
              filters: const NearbyFilters(minimumAge: 25),
            ),
          );
          await tester.pump();
        }
        if (cancel == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(f.cubit.loadCalls, cancel == 'none' ? 1 : 0);
        expect(f.cubit.pageAttempts, cancel == 'none' ? 2 : 1);
        if (cancel == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        if (cancel != 'close') await f.close(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'footer activity reuses the grid widgets and stops its hidden ticker',
    (tester) async {
      final f = await _mount(tester, count: 30);
      final avatar = find.descendant(
        of: find.byKey(const ValueKey('p0')),
        matching: find.byType(UserAvatar),
      );
      final original = tester.widget(avatar);
      for (final loading in [true, false, true, false]) {
        f.cubit.show(f.cubit.state.copyWith(isLoadingMore: loading));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(tester.widget(avatar), same(original));
      }
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await f.close(tester);
    },
  );

  testWidgets(
    'nearby retains a decoded avatar across a short offscreen round trip',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('nearby-avatar-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final photo = File(
        'assets/logo/logo_yap_chat.png',
      ).copySync('${directory.path}/photo.png');
      final people = _state(100).people
          .map(
            (person) => NearbyPerson(
              id: person.id,
              username: person.username,
              displayName: person.displayName,
              activeUntil: person.activeUntil,
              avatarStoragePath: 'photo/${person.id}',
              cachedAvatarPath: photo.path,
            ),
          )
          .toList();
      final f = await _mount(
        tester,
        count: 100,
        hasMore: false,
        people: people,
      );
      final avatar = find.descendant(
        of: find.byKey(const ValueKey('p9')),
        matching: find.byType(UserAvatar),
      );
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (tester
            .widgetList<RawImage>(
              find.descendant(of: avatar, matching: find.byType(RawImage)),
            )
            .any((image) => image.image != null)) {
          break;
        }
      }
      final element = tester.element(avatar);
      final frame = tester
          .widget<RawImage>(
            find.descendant(of: avatar, matching: find.byType(RawImage)),
          )
          .image;
      expect(frame, isNotNull);
      _position(tester).jumpTo(900);
      await tester.pump();
      await tester.pump();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      _position(tester).jumpTo(0);
      await tester.pump();
      expect(tester.element(avatar), same(element));
      expect(
        tester
            .widget<RawImage>(
              find.descendant(of: avatar, matching: find.byType(RawImage)),
            )
            .image,
        same(frame),
      );
      expect(
        find.descendant(of: avatar, matching: find.byIcon(Icons.person)),
        findsNothing,
      );
      // Removal is authoritative even if a stale local path is supplied.
      final removed = people
          .map(
            (person) => person.id != 'p9'
                ? person
                : NearbyPerson(
                    id: person.id,
                    username: person.username,
                    displayName: person.displayName,
                    activeUntil: person.activeUntil,
                    cachedAvatarPath: photo.path,
                  ),
          )
          .toList();
      f.cubit.show(f.cubit.state.copyWith(people: removed));
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(of: avatar, matching: find.byIcon(Icons.person)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: avatar, matching: find.byType(Image)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'pull ring continues filling instead of stopping at ninety percent',
    (tester) async {
      final f = await _mount(tester);
      final drag = await tester.startGesture(const Offset(180, 300));
      final values = <double>[];
      for (var i = 0; i < 18; i++) {
        await drag.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
        values.add(
          tester
              .widget<CircularProgressIndicator>(
                find.descendant(
                  of: find.byKey(const ValueKey('nearby_pull_indicator')),
                  matching: find.byKey(
                    const ValueKey('nearby_refresh_progress'),
                  ),
                ),
              )
              .value!,
        );
      }
      expect(
        values.where((value) => value > .9 && value < 1).length,
        greaterThan(2),
      );
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]));
      }
      expect(values.last, 1);
      await drag.up();
      await tester.pumpAndSettle();
      expect(f.cubit.refreshCalls, 1);
      expect(f.cubit.loadCalls, 0);
      await f.close(tester);
    },
  );

  for (final distance in [200.0, 360.0]) {
    testWidgets(
      'complete pull ring agrees with refresh readiness distance=$distance',
      (tester) async {
        final f = await _mount(tester);
        final drag = await tester.startGesture(const Offset(180, 300));
        for (var i = 0; i < 10; i++) {
          await drag.moveBy(Offset(0, distance / 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final ring = tester.widget<CircularProgressIndicator>(
          find.descendant(
            of: find.byKey(const ValueKey('nearby_pull_indicator')),
            matching: find.byKey(const ValueKey('nearby_refresh_progress')),
          ),
        );
        expect(ring.value == 1, distance == 360);
        await drag.up();
        await tester.pumpAndSettle();
        expect(f.cubit.refreshCalls, distance == 360 ? 1 : 0);
        expect(f.cubit.loadCalls, 0);
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }

  testWidgets(
    'page arriving during held bottom overscroll preserves the anchor',
    (tester) async {
      final f = await _mount(tester, count: 30);
      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent - 20);
      await tester.pump();
      final drag = await tester.startGesture(const Offset(180, 500));
      await drag.moveBy(const Offset(0, -110));
      await tester.pump(const Duration(milliseconds: 16));
      final offset = position.pixels;
      final card = find.byKey(const ValueKey('p27'));
      final y = tester.getTopLeft(card).dy;
      f.cubit.show(_state(60));
      await tester.pump();
      await tester.pump();
      expect(position.pixels, closeTo(offset, .01));
      expect(tester.getTopLeft(card).dy, closeTo(y, .01));
      await drag.up();
      await tester.pumpAndSettle();
      expect(f.cubit.refreshCalls, 0);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('new page fades without moving existing cards at $size', (
      tester,
    ) async {
      final f = await _mount(tester, size: size, count: 30);
      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent - 120);
      await tester.pump();
      await tester.pump();
      final old = find.byKey(const ValueKey('p27'));
      final y = tester.getTopLeft(old).dy;
      final element = tester.element(old);
      final offset = position.pixels;
      f.cubit.show(_state(60));
      await tester.pump();
      await tester.pump();
      expect(_cardOpacity(tester, 'p30'), 0);
      final extent = position.maxScrollExtent;
      for (var frame = 0; frame < 18; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getTopLeft(old).dy, closeTo(y, .01));
        expect(position.pixels, closeTo(offset, .01));
        expect(position.maxScrollExtent, closeTo(extent, .01));
        expect(tester.element(old), same(element));
        expect(_cardOpacity(tester, 'p27'), 1);
        if (frame == 5) {
          expect(_cardOpacity(tester, 'p30'), inExclusiveRange(0, 1));
        }
      }
      expect(_cardOpacity(tester, 'p30'), 1);
      position.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('p30')), findsNothing);
      position.jumpTo(offset);
      await tester.pump();
      await tester.pump();
      expect(_cardOpacity(tester, 'p30'), 1);
      expect(f.cubit.loadCalls, 0);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }

  testWidgets('a second fast page does not restart the first page fade', (
    tester,
  ) async {
    final f = await _mount(tester, count: 2);
    f.cubit.show(_state(5));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final before = _cardOpacity(tester, 'p2');
    expect(before, inExclusiveRange(0, 1));
    f.cubit.show(_state(8));
    await tester.pump();
    await tester.pump();
    expect(_cardOpacity(tester, 'p2'), closeTo(before, .001));
    expect(_cardOpacity(tester, 'p5'), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(_cardOpacity(tester, 'p2'), greaterThan(before));
    expect(_cardOpacity(tester, 'p5'), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_cardOpacity(tester, 'p2'), 1);
    expect(_cardOpacity(tester, 'p5'), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await f.close(tester);
  });

  testWidgets('cached and replacement feeds do not replay page entrances', (
    tester,
  ) async {
    final f = await _mount(tester, count: 2);
    expect(_cardOpacity(tester, 'p0'), 1);
    f.cubit.show(_state(5).copyWith(feedRevision: 1));
    await tester.pump();
    await tester.pump();
    expect(_cardOpacity(tester, 'p2'), 1);
    f.cubit.show(
      _state(
        8,
      ).copyWith(feedRevision: 1, filters: const NearbyFilters(minimumAge: 25)),
    );
    await tester.pump();
    await tester.pump();
    expect(_cardOpacity(tester, 'p5'), 1);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets('page entrance respects reduced motion', (tester) async {
    final f = await _mount(tester, count: 2, disableAnimations: true);
    f.cubit.show(_state(5));
    await tester.pump();
    await tester.pump();
    expect(_cardOpacity(tester, 'p2'), 1);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await f.close(tester);
  });

  for (final replace in [false, true]) {
    testWidgets(
      'removing or replacing a page mid-fade is safe replace=$replace',
      (tester) async {
        final f = await _mount(tester, count: 2);
        f.cubit.show(_state(5));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        f.cubit.show(
          replace
              ? _state(2).copyWith(feedRevision: 1)
              : f.cubit.state.copyWith(
                  people: f.cubit.state.people
                      .where((person) => person.id != 'p2')
                      .toList(),
                ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('p2')), findsNothing);
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await f.close(tester);
      },
    );
  }

  for (final fast in [true, false]) {
    testWidgets('refresh return spans frames without a snap fast=$fast', (
      tester,
    ) async {
      final f = await _mount(tester);
      f.cubit.refreshGate = Completer<void>();
      final drag = await tester.startGesture(const Offset(180, 300));
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(0, 36));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      var previousY = tester.getTopLeft(find.byKey(const ValueKey('p0'))).dy;
      var returningFrames = 0;
      for (var frame = 0; frame < 85; frame++) {
        if (frame == (fast ? 3 : 32)) f.cubit.refreshGate!.complete();
        await tester.pump(const Duration(milliseconds: 16));
        final y = tester.getTopLeft(find.byKey(const ValueKey('p0'))).dy;
        final tween = tester.widget<TweenAnimationBuilder<double>>(
          find.byType(TweenAnimationBuilder<double>).first,
        );
        if (tween.tween.end == 0 && f.cubit.refreshCalls == 1) {
          expect((y - previousY).abs(), lessThan(20));
          if ((y - previousY).abs() > .05) returningFrames++;
          expect(tween.duration, isNot(Duration.zero));
        }
        previousY = y;
      }
      expect(returningFrames, greaterThan(8));
      expect(previousY, closeTo(PrimaryHeaderGeometry.compactHeight, .01));
      expect(_position(tester).pixels, 0);
      expect(f.cubit.refreshCalls, 1);
      expect(f.cubit.loadCalls, 0);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('footer keeps the end extent stable at $size', (tester) async {
      final f = await _mount(tester, size: size);
      f.cubit.show(_state(60, hasMore: false));
      await tester.pump();
      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      final offset = position.pixels, maximum = position.maxScrollExtent;
      final last = find.byKey(const ValueKey('p59'));
      final element = tester.element(
        find.descendant(of: last, matching: find.byType(UserAvatar)),
      );
      final y = tester.getTopLeft(last).dy;
      for (final loading in [true, false, true, false]) {
        f.cubit.show(f.cubit.state.copyWith(isLoadingMore: loading));
        await tester.pump(const Duration(milliseconds: 16));
        expect(position.maxScrollExtent, closeTo(maximum, .01));
        expect(position.pixels, closeTo(offset, .01));
        expect(tester.getTopLeft(last).dy, closeTo(y, .01));
        if (loading) {
          final indicator = find.descendant(
            of: find.byKey(const ValueKey('nearby_footer')),
            matching: find.byType(CircularProgressIndicator),
          );
          final media = MediaQuery.of(
            tester.element(find.byType(NearbyPeoplePage)),
          );
          final filtersTop =
              media.size.height -
              FloatingNavigationGeometry.occupiedHeight(media) -
              FloatingNavigationGeometry.controlSpacing -
              50;
          expect(tester.getRect(indicator).bottom, lessThan(filtersTop));
        }
        expect(
          tester.element(
            find.descendant(of: last, matching: find.byType(UserAvatar)),
          ),
          same(element),
        );
      }
      expect(f.cubit.refreshCalls, 0);
      expect(f.cubit.loadCalls, 0);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }

  testWidgets(
    'pull ring crossfades to a spinner and keeps spinning during exit',
    (tester) async {
      final f = await _mount(tester);
      f.cubit.refreshGate = Completer<void>();
      final indicator = find.byKey(const ValueKey('nearby_pull_indicator'));
      final progress = find.descendant(
        of: indicator,
        matching: find.byKey(const ValueKey('nearby_refresh_progress')),
      );
      final spinner = find.descendant(
        of: indicator,
        matching: find.byKey(const ValueKey('nearby_refresh_spinner')),
      );
      final drag = await tester.startGesture(const Offset(180, 300));
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(0, 36));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(progress, findsOneWidget);
      expect(tester.widget<CircularProgressIndicator>(progress).value, 1);
      await drag.up();
      for (var i = 0; i < 30 && f.cubit.refreshCalls == 0; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      expect(spinner, findsOneWidget);
      expect(progress, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 80));
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: spinner, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(progress, findsNothing);
      f.cubit.refreshGate!.complete();
      await tester.pump();
      await tester.pump();
      // The indicator has a minimum visible duration, independent of the RPC.
      for (var i = 0; i < 30; i++) {
        final inset = tester.widget<TweenAnimationBuilder<double>>(
          find.byType(TweenAnimationBuilder<double>).first,
        );
        if (inset.tween.end == 0) break;
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 80));
      expect(_indicatorOpacity(tester, indicator), inExclusiveRange(0, 1));
      expect(tester.widget<CircularProgressIndicator>(spinner).value, isNull);
      await tester.pumpAndSettle();
      expect(_indicatorOpacity(tester, indicator), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(f.cubit.refreshCalls, 1);
      expect(f.cubit.loadCalls, 0);
      await f.close(tester);
    },
  );

  testWidgets(
    'a non-pull refresh indicator also stops repainting when hidden',
    (tester) async {
      final f = await _mount(tester, count: 2);
      final indicator = find.byKey(const ValueKey('nearby_query_indicator'));
      f.cubit.show(f.cubit.state.copyWith(isRefreshing: true));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(_indicatorOpacity(tester, indicator), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_indicatorOpacity(tester, indicator), 1);
      f.cubit.show(f.cubit.state.copyWith(isRefreshing: false));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(_indicatorOpacity(tester, indicator), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(_indicatorOpacity(tester, indicator), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(f.cubit.refreshCalls, 0);
      expect(f.cubit.loadCalls, 0);
      await f.close(tester);
    },
  );

  testWidgets('a cancelled short pull returns without starting a request', (
    tester,
  ) async {
    final f = await _mount(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 50));
    await tester.pumpAndSettle();
    expect(f.cubit.refreshCalls, 0);
    expect(f.cubit.loadCalls, 0);
    expect(_position(tester).pixels, 0);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('p0'))).dy,
      PrimaryHeaderGeometry.compactHeight,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    await f.close(tester);
  });

  testWidgets('leaving during a page fade or refresh does not leak tickers', (
    tester,
  ) async {
    final f = await _mount(tester, count: 2);
    f.cubit.show(_state(5));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    f.cubit.refreshGate = Completer<void>();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 250));
    for (var i = 0; i < 30 && f.cubit.refreshCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(f.cubit.refreshCalls, 1);
    await f.close(tester);
    f.cubit.refreshGate!.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('programmatic layout/filter changes do not trigger pagination', (
    tester,
  ) async {
    final f = await _mount(tester);
    final position = _position(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(f.cubit.loadCalls, 0);
    f.cubit.show(
      _state(
        30,
      ).copyWith(filters: const NearbyFilters(minimumAge: 25), feedRevision: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(position.pixels, 0);
    expect(f.cubit.loadCalls, 0);
    await f.close(tester);
  });

  testWidgets(
    'append retains visible tile position and triggers one user load',
    (tester) async {
      final f = await _mount(tester, count: 30);
      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent - 160);
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -80));
      await tester.pump();
      expect(f.cubit.loadCalls, 1);
      final tile = find.byKey(const ValueKey('p24'));
      final y = tester.getTopLeft(tile).dy;
      final element = tester.element(tile);
      final oldOffset = position.pixels;
      f.cubit.show(_state(60));
      await tester.pump();
      expect(tester.element(tile), same(element));
      expect(tester.getTopLeft(tile).dy, closeTo(y, .1));
      expect(position.pixels, closeTo(oldOffset, .1));
      expect(f.cubit.loadCalls, 1);
      await f.close(tester);
    },
  );

  testWidgets(
    'bottom overscroll never starts a feed refresh, including a short grid',
    (tester) async {
      final f = await _mount(tester, count: 2, hasMore: false);
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 700));
      }
      expect(f.cubit.refreshCalls, 0);
      expect(f.cubit.loadCalls, 0);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  for (final count in [2, 60]) {
    testWidgets(
      'a deliberate top pull starts one refresh without pagination count=$count',
      (tester) async {
        final f = await _mount(tester, count: count);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 180));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(f.cubit.refreshCalls, 1);
        expect(f.cubit.loadCalls, 0);
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }

  testWidgets('pending first load never shows an empty-result banner', (
    tester,
  ) async {
    final f = await _mount(tester, count: 0, hasMore: false);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NearbyPeoplePage)),
    )!;
    f.cubit.show(f.cubit.state.copyWith(isRefreshing: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(l10n.nearbyEmpty), findsNothing);
    f.cubit.show(
      f.cubit.state.copyWith(status: NearbyStatus.failure, isRefreshing: false),
    );
    await tester.pump();
    expect(find.text(l10n.nearbyLoadFailed), findsOneWidget);
    expect(find.text(l10n.nearbyEmpty), findsNothing);
    await f.close(tester);
  });

  testWidgets(
    'reordering a feed preserves the matching avatar instead of reusing an index',
    (tester) async {
      final f = await _mount(tester, count: 30);
      final tile = find.byKey(const ValueKey('p1'));
      final before = tester.element(
        find.descendant(of: tile, matching: find.byType(UserAvatar)),
      );
      final people = List<NearbyPerson>.of(f.cubit.state.people);
      final first = people.removeAt(1);
      people.insert(0, first);
      f.cubit.show(f.cubit.state.copyWith(people: people));
      await tester.pump();
      expect(
        tester.element(
          find.descendant(of: tile, matching: find.byType(UserAvatar)),
        ),
        same(before),
      );
      expect(f.cubit.loadCalls, 0);
      await f.close(tester);
    },
  );
  testWidgets('repeated end-to-end gestures keep a completed grid quiet', (
    tester,
  ) async {
    final f = await _mount(tester, count: 150, hasMore: false);
    for (var i = 0; i < 40; i++) {
      final position = _position(tester);
      if (i >= 20 && position.pixels <= 500) {
        position.jumpTo(position.maxScrollExtent);
      }
      await tester.drag(
        find.byType(CustomScrollView),
        Offset(0, i < 20 ? -450 : 450),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(UserAvatar).evaluate().length, lessThanOrEqualTo(72));
      expect(tester.takeException(), isNull);
    }
    expect(f.cubit.loadCalls, 0);
    expect(f.cubit.refreshCalls, 0);
    await f.close(tester);
  });
  for (final rotate in [false, true]) {
    testWidgets('old pull cannot refresh a replaced viewport rotate=$rotate', (
      tester,
    ) async {
      final f = await _mount(tester);
      final drag = await tester.startGesture(const Offset(180, 300));
      await drag.moveBy(const Offset(0, 150));
      await tester.pump();
      if (rotate) {
        tester.view.physicalSize = const Size(844, 390);
      } else {
        f.cubit.show(
          _state(30).copyWith(
            filters: const NearbyFilters(minimumAge: 25),
            feedRevision: 1,
          ),
        );
      }
      await tester.pump();
      await drag.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(f.cubit.refreshCalls, 0);
      expect(f.cubit.loadCalls, 0);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }
}

NearbyState _state(int count, {bool hasMore = true}) => NearbyState(
  status: NearbyStatus.ready,
  people: [
    for (var i = 0; i < count; i++)
      NearbyPerson(
        id: 'p$i',
        username: 'p$i',
        displayName: 'Person $i',
        activeUntil: DateTime.now().add(const Duration(days: 1)),
      ),
  ],
  hasMore: hasMore,
);
double _cardOpacity(WidgetTester tester, String id) =>
    tester.widget<FadeTransition>(find.byKey(ValueKey(id))).opacity.value;
double _indicatorOpacity(WidgetTester tester, Finder indicator) => tester
    .widget<Opacity>(
      find.descendant(of: indicator, matching: find.byType(Opacity)),
    )
    .opacity;
ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;
Future<_Fixture> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  int count = 60,
  bool hasMore = true,
  bool disableAnimations = false,
  List<NearbyPerson>? people,
  Future<void> Function(BuildContext, String)? openProfile,
  IPresenceRepository? presenceRepository,
  AppConnectionStatus? connectionStatus,
  NavigationScrollToTopController? navigation,
  String locale = 'ru',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final blocks = _Blocks();
  final locations = _Location();
  final tracking = LocationTrackingCoordinator(
    locationRepository: locations,
    talker: Talker(),
  );
  final repo = MockNearbyRepository();
  final cubit = _Cubit(repo, blocks, locations, tracking)
    ..show(_state(count, hasMore: hasMore).copyWith(people: people));
  final blocked = BlocklistCubit(repository: blocks);
  final presence = PresenceCubit(repository: MockPresenceRepository());
  addTearDown(() async {
    await cubit.close();
    await blocked.close();
    await presence.close();
    await tracking.dispose();
  });
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        if (navigation != null)
          RepositoryProvider<NavigationScrollToTopController>.value(
            value: navigation,
          ),
        if (connectionStatus != null)
          RepositoryProvider<AppConnectionStatus>.value(
            value: connectionStatus,
          ),
        RepositoryProvider<INearbyRepository>.value(value: repo),
        RepositoryProvider<IPresenceRepository>.value(
          value: presenceRepository ?? MockPresenceRepository(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<NearbyCubit>.value(value: cubit),
          BlocProvider<BlocklistCubit>.value(value: blocked),
          BlocProvider<PresenceCubit>.value(value: presence),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: NearbyPeoplePage(openProfile: openProfile),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return _Fixture(cubit);
}

class _CountingPresence extends MockPresenceRepository {
  int setCalls = 0, nearbySetCalls = 0, removeCalls = 0;
  @override
  Future<void> setWatchScope(String scopeId, Iterable<String> userIds) async {
    setCalls++;
    if (scopeId.startsWith('nearby:')) nearbySetCalls++;
  }

  @override
  Future<void> removeWatchScope(String scopeId) async {
    removeCalls++;
  }
}

class _Cubit extends NearbyCubit {
  _Cubit(
    INearbyRepository repo,
    IBlocklistRepository blocks,
    ILocationRepository locations,
    LocationTrackingCoordinator tracking,
  ) : super(
        repository: repo,
        locationRepository: locations,
        locationTrackingCoordinator: tracking,
        accountSessionController: AccountSessionController(
          initialUserId: 'owner',
        ),
        blocklistRepository: blocks,
        profileFriendsRepository: MockFriendsRepository(),
      );
  int loadCalls = 0, refreshCalls = 0;
  int quotaDenials = 0, pageAttempts = 0;
  Duration? quotaDelay;
  @override
  Duration? get paginationQuotaRetryDelay =>
      quotaDelay ?? super.paginationQuotaRetryDelay;
  Completer<void>? refreshGate;
  void show(NearbyState state) => emit(state);
  @override
  Future<void> initialize() async {}
  @override
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    pageAttempts++;
    if (quotaDenials > 0) {
      quotaDenials--;
      return;
    }
    quotaDelay = null;
    loadCalls++;
    emit(state.copyWith(isLoadingMore: true));
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
    if (refreshGate case final gate?) {
      emit(state.copyWith(isRefreshing: true));
      await gate.future;
      if (!isClosed) {
        emit(
          state.copyWith(
            isRefreshing: false,
            people: state.people.take(30).toList(),
            feedRevision: state.feedRevision + 1,
          ),
        );
      }
    }
  }
}

class _Location implements ILocationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Blocks extends MockBlocklistRepository {
  @override
  Stream<Set<String>> watchBlockedUserIds() => const Stream.empty();
  @override
  Stream<Set<String>> watchPendingUserIds() => const Stream.empty();
}

class _Fixture {
  _Fixture(this.cubit);
  final _Cubit cubit;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }
}
