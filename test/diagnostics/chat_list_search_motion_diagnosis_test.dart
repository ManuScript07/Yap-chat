// Regression checks against production UI/Bloc/avatars with controlled snapshots.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/ui/ui.dart';

final _reports = <Map<String, Object?>>[];

void main() {
  setUpAll(() async {
    AppTextStyles.chatName = const TextStyle(fontSize: 18, height: 1.33);
    AppTextStyles.messagePreview = const TextStyle(fontSize: 16, height: 1.25);
    AppTextStyles.metadata = const TextStyle(fontSize: 14, height: 1.14);
    AppTextStyles.badgeText = const TextStyle(fontSize: 14, height: 1.14);
    await (FontLoader(
      'RobotoFlex',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });
  tearDownAll(() {
    File(
      'tmp/chat_list_search_motion_diagnosis.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_reports));
  });

  testWidgets('keyed rows move smoothly while retaining their element', (
    tester,
  ) async {
    final source = _Source();
    final bloc = ChatsBloc(chatsRepository: source);
    addTearDown(bloc.close);
    addTearDown(source.close);
    final rows = [_chat('one'), _chat('two'), _chat('three')];
    await _mount(tester, source, bloc, rows);
    final row = find.byKey(const ValueKey('three'));
    final element = tester.element(row);
    final before = tester.getTopLeft(row).dy;
    final firstSlot = tester.getTopLeft(find.byKey(const ValueKey('one'))).dy;
    source.publish([
      rows.last.copyWith(lastMessage: 'new incoming'),
      ...rows.take(2),
    ]);
    final positions = <double>[];
    for (final delay in [0, 16, 32, 64, 160]) {
      await tester.pump(Duration(milliseconds: delay));
      positions.add(tester.getTopLeft(row).dy);
    }
    expect(tester.element(row), same(element));
    expect((before - positions.last).abs(), greaterThan(80));
    expect(positions.first, closeTo(before, .01));
    expect(positions[2], inExclusiveRange(positions.last, before));
    expect(positions.last, closeTo(firstSlot, .01));
    _reports.add({
      'case': 'reorder',
      'before_y': before,
      'frames_y': positions,
      'element_retained': true,
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final evict in [false, true]) {
    testWidgets('diagnose search avatar remount evicted=$evict', (
      tester,
    ) async {
      final path = 'tmp/chat_search_avatar_probe_$evict.png';
      final file = File('assets/logo/logo_yap_chat.png').copySync(path);
      addTearDown(file.deleteSync);
      final source = _Source();
      final bloc = ChatsBloc(chatsRepository: source);
      addTearDown(bloc.close);
      addTearDown(source.close);
      final chat = _chat('one').copyWith(
        avatarStoragePath: 'diagnosis/$evict/avatar.png',
        cachedAvatarPath: file.absolute.path,
      );
      await _mount(tester, source, bloc, [chat]);
      await _decode(tester);
      final original = tester.element(find.byType(UserAvatar));
      bloc.add(const ChatsSearchChanged('one'));
      await tester.pump();
      source.publish([], query: 'one', ready: false, refreshing: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final hiddenRows = find.byType(ChatListItem).evaluate().length;
      final spinner = find.byType(CircularProgressIndicator).evaluate().length;
      expect(hiddenRows, 1);
      expect(
        spinner,
        0,
        reason: 'Fast reads retain rows without flashing a loader.',
      );
      if (evict) {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
      source.publish([chat], query: 'one');
      await tester.pump();
      await tester.pump();
      final restored = tester.element(find.byType(UserAvatar));
      final decoded = tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((w) => w.image != null);
      final placeholder = find.byIcon(Icons.person).evaluate().isNotEmpty;
      expect(restored, same(original));
      expect(decoded, true);
      expect(placeholder, false);
      _reports.add({
        'case': 'avatar_remount',
        'image_cache_evicted': evict,
        'hidden_rows': hiddenRows,
        'spinner_visible': spinner > 0,
        'element_retained': true,
        'decoded_first_frame': decoded,
        'placeholder_first_frame': placeholder,
        'resolver_calls': source.avatarLoads,
      });
      await _decode(tester);
      expect(
        source.avatarLoads,
        0,
        reason:
            'The file still exists: this is frame lifetime, not a network load.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('diagnose avatar returning from empty search evicted=$evict', (
      tester,
    ) async {
      final path = 'tmp/chat_search_exit_avatar_probe_$evict.png';
      final file = File('assets/logo/logo_yap_chat.png').copySync(path);
      addTearDown(file.deleteSync);
      final source = _Source();
      final bloc = ChatsBloc(chatsRepository: source);
      addTearDown(bloc.close);
      addTearDown(source.close);
      final chat = _chat('one').copyWith(
        avatarStoragePath: 'exit/$evict/photo.png',
        cachedAvatarPath: file.absolute.path,
      );
      await _mount(tester, source, bloc, [chat]);
      await _decode(tester);
      final original = tester.element(find.byType(UserAvatar));
      bloc.add(const ChatsSearchChanged('missing'));
      await tester.pump();
      source.publish([], query: 'missing');
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChatListItem), findsNothing);
      if (evict) {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
      bloc.add(const ChatsSearchChanged(''));
      await tester.pump();
      await tester.pump();
      final noChats = find
          .text(
            AppLocalizations.of(
              tester.element(find.byType(ChatsPage)),
            )!.noChats,
          )
          .evaluate()
          .isNotEmpty;
      expect(noChats, false);
      final falseEmptyText = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(EmptyChatState),
              matching: find.byType(Text),
            ),
          )
          .map((w) => w.data)
          .toList();
      source.publish([chat]);
      await tester.pump();
      await tester.pump();
      for (
        var frame = 0;
        frame < 40 && find.byType(UserAvatar).evaluate().isEmpty;
        frame++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      final decoded = tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((w) => w.image != null);
      final placeholder = find.byIcon(Icons.person).evaluate().isNotEmpty;
      expect(tester.element(find.byType(UserAvatar)), isNot(same(original)));
      expect(decoded, true);
      expect(placeholder, false);
      _reports.add({
        'case': 'empty_search_exit',
        'image_cache_evicted': evict,
        'false_empty_main': noChats,
        'intermediate_text': falseEmptyText,
        'decoded_first_frame': decoded,
        'placeholder_first_frame': placeholder,
        'resolver_calls': source.avatarLoads,
      });
      await _decode(tester);
      expect(source.avatarLoads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('movement retargets, inserts, removes and keeps avatar state', (
    tester,
  ) async {
    final source = _Source();
    final bloc = ChatsBloc(chatsRepository: source);
    addTearDown(bloc.close);
    addTearDown(source.close);
    final rows = [_chat('one'), _chat('two'), _chat('three')];
    await _mount(tester, source, bloc, rows);
    final three = find.byKey(const ValueKey('three'));
    final original = tester.element(three);
    final firstSlot = tester.getTopLeft(find.byKey(const ValueKey('one'))).dy;
    final secondSlot = tester.getTopLeft(find.byKey(const ValueKey('two'))).dy;
    source.publish([rows[2], rows[0], rows[1]]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final midway = tester.getTopLeft(three).dy;
    source.publish([rows[1], rows[2], rows[0]]);
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(three).dy, closeTo(midway, 1));
    await tester.pump(const Duration(milliseconds: 280));
    expect(tester.getTopLeft(three).dy, closeTo(secondSlot, 1));
    source.publish([rows[2], rows[0]]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('two')), findsNothing);
    expect(tester.getTopLeft(three).dy, closeTo(secondSlot, 1));
    await tester.pump(const Duration(milliseconds: 280));
    expect(tester.getTopLeft(three).dy, closeTo(firstSlot, 1));
    source.publish([_chat('four'), rows[2], rows[0]]);
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(three).dy, closeTo(firstSlot, 1));
    // A tap on an overlapping moving row must not open the wrong conversation.
    await tester.tap(three, warnIfMissed: false);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 280));
    expect(tester.getTopLeft(three).dy, closeTo(secondSlot, 1));
    expect(tester.element(three), same(original));
    await tester.longPress(three);
    await tester.pump();
    await tester.pump();
    expect(bloc.state.selectedChatIds, {'three'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion updates order without blocking selection', (
    tester,
  ) async {
    final source = _Source();
    final bloc = ChatsBloc(chatsRepository: source);
    addTearDown(bloc.close);
    addTearDown(source.close);
    final rows = [_chat('one'), _chat('two'), _chat('three')];
    await _mount(tester, source, bloc, rows, disableAnimations: true);
    final firstSlot = tester.getTopLeft(find.byKey(const ValueKey('one'))).dy;
    source.publish([rows[2], rows[0], rows[1]]);
    await tester.pump();
    await tester.pump();
    final three = find.byKey(const ValueKey('three'));
    expect(tester.getTopLeft(three).dy, closeTo(firstSlot, .01));
    await tester.longPress(three);
    await tester.pump();
    expect(bloc.state.selectedChatIds, {'three'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'manual scrolling cooperates with movement and keeps rows interactive',
    (tester) async {
      final source = _Source();
      final bloc = ChatsBloc(chatsRepository: source);
      addTearDown(bloc.close);
      addTearDown(source.close);
      final rows = [for (var i = 0; i < 50; i++) _chat('row-$i')];
      await _mount(tester, source, bloc, rows);
      source.publish([rows[2], rows[0], rows[1], ...rows.skip(3)]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('row-3'));
      await tester.longPress(row);
      await tester.pump();
      expect(bloc.state.selectedChatIds, {'row-3'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('short list accepts edge drags before and after search', (
    tester,
  ) async {
    final source = _Source();
    final bloc = ChatsBloc(chatsRepository: source);
    addTearDown(bloc.close);
    addTearDown(source.close);
    final rows = [_chat('one'), _chat('two')];
    await _mount(tester, source, bloc, rows);
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(position().maxScrollExtent, 0);
    expect(position().physics.shouldAcceptUserOffset(position()), true);
    bloc.add(const ChatsSearchChanged('one'));
    await tester.pump();
    source.publish([rows.first], query: 'one');
    await tester.pumpAndSettle();
    expect(position().physics.shouldAcceptUserOffset(position()), true);
    bloc.add(const ChatsSearchChanged(''));
    await tester.pump();
    source.publish(rows);
    await tester.pumpAndSettle();
    expect(position().physics.shouldAcceptUserOffset(position()), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('drag after clearing search does not snap the moving row', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    final source = _Source();
    final bloc = ChatsBloc(chatsRepository: source);
    addTearDown(bloc.close);
    addTearDown(source.close);
    final rows = [for (var i = 0; i < 6; i++) _chat('row-$i')];
    await _mount(tester, source, bloc, rows);
    await tester.showKeyboard(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'row-3');
    await tester.pump();
    source.publish([rows[3]], query: 'row-3');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    source.publish(rows);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final row = find.byKey(const ValueKey('row-3'));
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    final before = tester.getTopLeft(row).dy + scroll.pixels;
    final gesture = await tester.startGesture(const Offset(350, 300));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    final after = tester.getTopLeft(row).dy + scroll.pixels;
    expect(
      after,
      closeTo(before, 1),
      reason: 'drag must not finish row motion in one frame',
    );
    source.publish([rows[0], rows[3], rows[1], rows[2], ...rows.skip(4)]);
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(row).dy + scroll.pixels,
      closeTo(after, 1),
      reason: 'a new reorder during the same drag must retarget smoothly',
    );
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning from search never cancels an already active drag', (
    tester,
  ) async {
    final source = _Source();
    final bloc = ChatsBloc(chatsRepository: source);
    addTearDown(bloc.close);
    addTearDown(source.close);
    final rows = [for (var i = 0; i < 20; i++) _chat('row-$i')];
    await _mount(tester, source, bloc, rows);
    bloc.add(const ChatsSearchChanged('row'));
    await tester.pump();
    source.publish(rows.take(4).toList(), query: 'row');
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    final gesture = await tester.startGesture(const Offset(350, 300));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(scroll.isScrollingNotifier.value, true);
    bloc.add(const ChatsSearchChanged(''));
    await tester.pump();
    source.publish(rows);
    await tester.pump();
    await tester.pump();
    expect(scroll.isScrollingNotifier.value, true);
    final before = scroll.pixels;
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(scroll.pixels, greaterThan(before));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (count, hiddenBeforeDrag) in [
    (2, false),
    (2, true),
    (6, false),
    (20, false),
  ]) {
    testWidgets(
      'keyboard dismissal has no visual rebound rows=$count zeroBeforeDrag=$hiddenBeforeDrag',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.reset);
        final source = _Source();
        final bloc = ChatsBloc(chatsRepository: source);
        addTearDown(bloc.close);
        addTearDown(source.close);
        final rows = [for (var i = 0; i < count; i++) _chat('row-$i')];
        await _mount(tester, source, bloc, rows);
        await tester.showKeyboard(find.byType(TextField));
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        final scroll = tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              ),
            )
            .position;
        scroll.jumpTo(scroll.maxScrollExtent);
        await tester.pumpAndSettle();
        final first = find.byType(ChatListItem).evaluate().firstWhere((
          element,
        ) {
          final y = tester.getTopLeft(find.byWidget(element.widget)).dy;
          return y >= 130 && y < 500;
        });
        final row = find.byKey(
          ValueKey((first.widget as ChatListItem).chat.id),
        );
        final frames = <Map<String, Object?>>[];
        var anchorCorrections = 0;
        void listen() {
          if (StackTrace.current.toString().contains('_preserveAnchor')) {
            anchorCorrections++;
          }
        }

        scroll.addListener(listen);
        void record() {
          final list = tester.widget<ListView>(find.byType(ListView));
          frames.add({
            'inset': tester.view.viewInsets.bottom,
            'pixels': scroll.pixels,
            'max': scroll.maxScrollExtent,
            'row_y': tester.getTopLeft(row).dy,
            'padding': (list.padding! as EdgeInsets).bottom,
            'anchor_corrections': anchorCorrections,
          });
        }

        record();
        final gesture = await tester.startGesture(const Offset(350, 300));
        if (hiddenBeforeDrag) {
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pump();
        }
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
        record();
        final insets = hiddenBeforeDrag
            ? [0.0]
            : [300.0, 260.0, 220.0, 180.0, 140.0, 100.0, 60.0, 20.0, 0.0];
        for (final inset in insets) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump(const Duration(milliseconds: 16));
          record();
        }
        await gesture.up();
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          record();
        }
        scroll.removeListener(listen);
        File(
          'tmp/chats_ime_dismissal_probe_${count}_$hiddenBeforeDrag.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(frames));
        expect(
          anchorCorrections,
          0,
          reason:
              'keyboard-only geometry must not trigger data anchor corrections',
        );
        if (count == 2) {
          final initialY = frames.first['row_y']! as double;
          for (final frame in frames) {
            expect(
              frame['row_y'],
              closeTo(initialY, .2),
              reason:
                  'a keyboard-dismiss gesture must not stretch a fitting list',
            );
          }
          // The ordinary native edge effect remains available on the next drag,
          // after the keyboard has closed and the inset has settled.
          final edgeDrag = await tester.startGesture(const Offset(350, 300));
          await edgeDrag.moveBy(const Offset(0, -30));
          await tester.pump();
          expect(tester.getTopLeft(row).dy, lessThan(initialY - 1));
          await edgeDrag.up();
          await tester.pumpAndSettle();
        } else {
          for (var i = 1; i < frames.length; i++) {
            expect(
              frames[i]['row_y']! as double,
              greaterThanOrEqualTo((frames[i - 1]['row_y']! as double) - .2),
              reason:
                  'clamping a shrinking bottom inset must not reverse direction',
            );
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Samsung three-row IME dismissal never enters temporary scroll space',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.viewPadding = const FakeViewPadding(bottom: 45, top: 103);
      addTearDown(tester.view.reset);
      final source = _Source();
      final bloc = ChatsBloc(chatsRepository: source);
      addTearDown(bloc.close);
      addTearDown(source.close);
      await _mount(tester, source, bloc, [
        for (var i = 0; i < 3; i++) _chat('row-$i'),
      ]);
      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 1031);
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final row = find.byKey(const ValueKey('row-0'));
      final origin = tester.getTopLeft(row).dy;
      expect(scroll.maxScrollExtent, 0);
      // Logical inset/timing samples recorded from the real Samsung, not a
      // single artificial 320 -> 0 transition. Start at zero, not at the end.
      const metrics = <(int, double)>[
        (0, 342.6666666667),
        (8, 340),
        (18, 334),
        (26, 325),
        (33, 312.3333333333),
        (42, 291.3333333333),
        (51, 267),
        (60, 239),
        (68, 207),
        (77, 181),
        (84, 158),
        (92, 135),
        (100, 118),
        (109, 103),
        (116, 88.6666666667),
        (126, 76.6666666667),
        (134, 66.6666666667),
        (141, 57),
        (150, 49.3333333333),
        (158, 42),
        (167, 35.6666666667),
        (175, 30),
        (183, 25.3333333333),
        (192, 20.6666666667),
        (200, 17),
        (208, 13.6666666667),
        (218, 11),
        (225, 8.3333333333),
        (233, 6.3333333333),
        (243, 4.3333333333),
        (258, 2),
        (267, 1),
        (283, .3333333333),
        (292, 0),
      ];
      final gesture = await tester.startGesture(const Offset(300, 333));
      await gesture.moveBy(const Offset(0, -30));
      var previousMs = 0;
      for (final (ms, inset) in metrics) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset * 3);
        await gesture.moveBy(const Offset(0, -6));
        await tester.pump(Duration(milliseconds: ms - previousMs));
        previousMs = ms;
        expect(scroll.pixels, closeTo(0, .01));
        expect(tester.getTopLeft(row).dy, closeTo(origin, .2));
      }
      await gesture.up();
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.maxScrollExtent, 0);
        expect(scroll.pixels, closeTo(0, .01));
        expect(tester.getTopLeft(row).dy, closeTo(origin, .2));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '1000-row promotion preserves the anchor on every animation frame',
    (tester) async {
      final source = _Source();
      final bloc = ChatsBloc(chatsRepository: source);
      addTearDown(bloc.close);
      addTearDown(source.close);
      final rows = [for (var i = 0; i < 1000; i++) _chat('row-$i')];
      await _mount(tester, source, bloc, rows);
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      scroll.jumpTo(scroll.maxScrollExtent / 2);
      await tester.pump();
      await tester.pump();
      final item = find.byType(ChatListItem).evaluate().firstWhere((element) {
        final y = tester.getTopLeft(find.byWidget(element.widget)).dy;
        return y >= 130 && y < 300;
      });
      final anchor = find.byKey(
        ValueKey((item.widget as ChatListItem).chat.id),
      );
      final before = tester.getTopLeft(anchor).dy;
      source.publish([rows.last, ...rows.take(rows.length - 1)]);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
        expect(find.byType(ChatListItem).evaluate().length, lessThan(35));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('empty search restores a deep main offset on its first layout', (
    tester,
  ) async {
    final file = File(
      'assets/logo/logo_yap_chat.png',
    ).copySync('tmp/chat_search_deep_avatar.png');
    addTearDown(file.deleteSync);
    final topFile = File(
      'assets/logo/logo_yap_chat.png',
    ).copySync('tmp/chat_search_deep_top_avatar.png');
    addTearDown(topFile.deleteSync);
    final source = _Source();
    final bloc = ChatsBloc(chatsRepository: source);
    addTearDown(bloc.close);
    addTearDown(source.close);
    final rows = [
      for (var i = 0; i < 200; i++)
        _chat('row-$i').copyWith(
          avatarStoragePath: 'deep/$i/photo.png',
          cachedAvatarPath: i >= 85 && i <= 115
              ? file.absolute.path
              : topFile.absolute.path,
        ),
    ];
    await _mount(tester, source, bloc, rows);
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    position().jumpTo(position().maxScrollExtent / 2);
    await tester.pump();
    await tester.pump();
    await _decode(tester);
    final before = position().pixels;
    bloc.add(const ChatsSearchChanged('missing'));
    await tester.pump();
    source.publish([], query: 'missing');
    await tester.pump();
    await tester.pump();
    expect(find.byType(ListView), findsNothing);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    bloc.add(const ChatsSearchChanged(''));
    await tester.pump();
    source.publish(rows);
    await tester.pump();
    await tester.pump();
    for (
      var frame = 0;
      frame < 40 && find.byType(ListView).evaluate().isEmpty;
      frame++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      // Real file decoding runs outside the fake clock. Do not exhaust the
      // presentation's 120 ms fake timer faster than that real I/O can finish.
      await tester.pump();
    }
    expect(position().pixels, closeTo(before, 1));
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
      true,
    );
    expect(find.byIcon(Icons.person), findsNothing);
    expect(source.avatarLoads, 0);
    await tester.pump(const Duration(milliseconds: 280));
    expect(position().pixels, closeTo(before, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final logoutBeforeDelivery in [false, true]) {
    testWidgets(
      'logout cancels pending presentation beforeDelivery=$logoutBeforeDelivery',
      (tester) async {
        final file = File(
          'assets/logo/logo_yap_chat.png',
        ).copySync('tmp/avatar_logout_$logoutBeforeDelivery.png');
        addTearDown(file.deleteSync);
        final account = AccountSessionController(initialUserId: 'owner');
        final source = _Source();
        final bloc = ChatsBloc(chatsRepository: source);
        addTearDown(bloc.close);
        addTearDown(source.close);
        final chat = _chat('one').copyWith(
          avatarStoragePath: 'logout/photo.png',
          cachedAvatarPath: file.absolute.path,
        );
        await _mount(tester, source, bloc, [chat], account: account);
        await _decode(tester);
        bloc.add(const ChatsSearchChanged('missing'));
        await tester.pump();
        source.publish([], query: 'missing');
        await tester.pump();
        await tester.pump();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        bloc.add(const ChatsSearchChanged(''));
        await tester.pump();
        if (logoutBeforeDelivery) account.setAuthenticatedUser(null);
        source.publish([chat]);
        await tester.pump();
        await tester.pump();
        if (!logoutBeforeDelivery) account.setAuthenticatedUser(null);
        for (var frame = 0; frame < 12; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(ChatListItem), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final revoked in [false, true]) {
    testWidgets(
      'local avatar preparation rejects superseded data revoked=$revoked',
      (tester) async {
        final file = File(
          'assets/logo/logo_yap_chat.png',
        ).copySync('tmp/avatar_cancel_presentation_$revoked.png');
        addTearDown(file.deleteSync);
        final source = _Source();
        final bloc = ChatsBloc(chatsRepository: source);
        addTearDown(bloc.close);
        addTearDown(source.close);
        final chat = _chat('one').copyWith(
          avatarStoragePath: 'cancel/$revoked/photo',
          cachedAvatarPath: file.absolute.path,
        );
        await _mount(tester, source, bloc, [chat]);
        await _decode(tester);
        bloc.add(const ChatsSearchChanged('missing'));
        await tester.pump();
        source.publish([], query: 'missing');
        await tester.pump();
        await tester.pump();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        bloc.add(const ChatsSearchChanged(''));
        await tester.pump();
        source.publish([chat]);
        await tester.pump();
        await tester.pump();
        if (revoked) {
          source.publish([chat.copyWith(blockedByPeer: true)]);
        } else {
          bloc.add(const ChatsSearchChanged('other'));
          await tester.pump();
          source.publish([], query: 'other');
        }
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          if (revoked) {
            expect(find.byType(Image), findsNothing);
          } else {
            expect(find.byType(ChatListItem), findsNothing);
          }
          expect(tester.takeException(), isNull);
        }
        expect(source.avatarLoads, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Chat _chat(String id) => Chat(
  id: id,
  userName: id,
  lastMessage: 'preview',
  lastMessageTime: DateTime(2026),
  unreadCount: 0,
  isOnline: false,
  isLastMessageFromMe: false,
);

Future<void> _mount(
  WidgetTester tester,
  _Source source,
  ChatsBloc bloc,
  List<Chat> rows, {
  bool disableAnimations = false,
  AccountSessionController? account,
}) async {
  bloc.add(const ChatsLoadStarted());
  await tester.pumpWidget(
    RepositoryProvider<IChatsRepository>.value(
      value: source,
      child: RepositoryProvider<AccountSessionController>.value(
        value: account ?? AccountSessionController(initialUserId: 'test-owner'),
        child: BlocProvider.value(
          value: bloc,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disableAnimations),
              child: child!,
            ),
            theme: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.blue,
                onSurface: Colors.white,
              ),
            ),
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ChatsPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  source.publish(rows);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    if (tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((w) => w.image != null)) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  fail('Local image did not decode');
}

class _Source implements IChatsRepository, IChatsListRepository {
  final _views = StreamController<ChatListViewState>.broadcast();
  int avatarLoads = 0;
  void publish(
    List<Chat> rows, {
    String query = '',
    bool ready = true,
    bool refreshing = false,
  }) => _views.add(
    ChatListViewState(
      chats: rows,
      query: query,
      ready: ready,
      isRefreshing: refreshing,
    ),
  );
  @override
  Stream<ChatListViewState> watchChatList() => _views.stream;
  @override
  Future<void> setChatListQuery(String query) async {}
  @override
  void setChatListObservedIds(Set<String> visible, Set<String> selected) {}
  @override
  Future<void> loadMoreChatList({bool retry = false}) async {}
  @override
  Future<String?> resolveAvatar(Chat chat) async {
    avatarLoads++;
    return chat.cachedAvatarPath;
  }

  Future<void> close() => _views.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
