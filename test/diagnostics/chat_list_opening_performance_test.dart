import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/message_bubble.dart';
import 'package:yap_chat/l10n/app_localizations.dart';

typedef OpeningListFactory =
    Widget Function(
      int count,
      IndexedWidgetBuilder builder,
      Key Function(int) keyBuilder,
    );

Widget keyedOpeningList(
  int count,
  IndexedWidgetBuilder builder,
  Key Function(int) keyBuilder,
) => ScrollablePositionedList.builder(
  itemCount: count,
  itemBuilder: builder,
  itemKeyBuilder: keyBuilder,
  reverse: true,
  padding: const EdgeInsets.only(top: 110, bottom: 90),
);

Widget unkeyedOpeningList(
  int count,
  IndexedWidgetBuilder builder,
  Key Function(int) keyBuilder,
) => ScrollablePositionedList.builder(
  itemCount: count,
  itemBuilder: builder,
  reverse: true,
  padding: const EdgeInsets.only(top: 110, bottom: 90),
);

void main() => runOpeningDiagnostics({
  'fork-keyed': keyedOpeningList,
  'fork-unkeyed': unkeyedOpeningList,
});

/// Opt-in CPU probes, not an Android/profile FPS benchmark. The optional map
/// allows an isolated upstream copy to run in the same process and same order.
/// Neither native media, network, SQLite, nor GPU time is measured here.
void runOpeningDiagnostics(Map<String, OpeningListFactory> factories) {
  for (final scenario in [(false, false), (true, false), (true, true)]) {
    final (realBubbles, rebuildDuringOpening) = scenario;
    testWidgets(
      'diagnostic opening route realBubbles=$realBubbles rebuild=$rebuildDuringOpening',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final auth = _Auth();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp(
              navigatorKey: navigator,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: Text('chat-list')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final first = <String, List<int>>{};
        final total = <String, List<int>>{};
        final work = <String, Set<String>>{};
        final entries = factories.entries.toList();
        final messages = List.generate(
          60,
          (i) => ChatMessage(
            id: '$i',
            chatId: 'chat',
            senderId: i.isEven ? 'me' : 'peer',
            isMine: i.isEven,
            text: i % 3 == 0
                ? 'Longer message with https://example.com and @username, '
                      'several lines of text to exercise actual bubble layout.'
                : 'Message $i',
            timestamp: DateTime(2026, 10, 21, 12, i),
          ),
        );
        // Rotate A/B/C order to avoid attributing monotonic JIT warming to one
        // variant. First six passes of every variant are excluded from stats.
        for (var pass = 0; pass < 42; pass++) {
          for (var j = 0; j < entries.length; j++) {
            final entry = entries[(j + pass) % entries.length];
            var builds = 0;
            var keys = 0;
            final builtIndices = <int>{};
            final revision = ValueNotifier(0);
            Widget createList() => entry.value(
              messages.length,
              (_, i) {
                builds++;
                builtIndices.add(i);
                return AnimatedContainer(
                  key: ValueKey('msg_$i'),
                  duration: const Duration(milliseconds: 180),
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: realBubbles
                      ? MessageBubble(
                          message: messages[i],
                          initialAnimationProgress: 1,
                          maxWidth: 300,
                          peerName: 'Peer',
                          onReaction: (_, _) {},
                        )
                      : SizedBox(height: 64, child: Text(messages[i].text)),
                );
              },
              (i) {
                keys++;
                return ValueKey('msg_$i');
              },
            );
            final route = PageRouteBuilder<void>(
              transitionDuration: const Duration(milliseconds: 200),
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => Scaffold(
                body: ValueListenableBuilder<int>(
                  valueListenable: revision,
                  builder: (_, _, _) => createList(),
                ),
              ),
              transitionsBuilder: (_, animation, _, child) {
                final curve = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                );
                return SlideTransition(
                  position: Tween(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(curve),
                  child: FadeTransition(opacity: curve, child: child),
                );
              },
            );
            final stopwatch = Stopwatch()..start();
            unawaited(navigator.currentState!.push(route));
            await tester.pump();
            final firstMicros = stopwatch.elapsedMicroseconds;
            for (var frame = 0; frame < 16; frame++) {
              if (rebuildDuringOpening && frame < 2) revision.value++;
              await tester.pump(const Duration(milliseconds: 16));
            }
            stopwatch.stop();
            expect(tester.takeException(), isNull);
            expect(builtIndices.length, lessThan(messages.length));
            if (pass >= 6) {
              first.putIfAbsent(entry.key, () => []).add(firstMicros);
              total
                  .putIfAbsent(entry.key, () => [])
                  .add(stopwatch.elapsedMicroseconds);
              work
                  .putIfAbsent(entry.key, () => {})
                  .add(
                    'builds=$builds unique=${builtIndices.length} keys=$keys',
                  );
            }
            navigator.currentState!.pop();
            await tester.pumpAndSettle();
            revision.dispose();
          }
        }
        for (final name in factories.keys) {
          // ignore: avoid_print
          print(
            'CHAT_OPEN realBubbles=$realBubbles rebuild=$rebuildDuringOpening variant=$name '
            'firstUs=${_stats(first[name]!)} transitionCpuUs=${_stats(total[name]!)} '
            'work=${work[name]}',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      skip: !const bool.fromEnvironment('CHAT_OPENING_DIAGNOSTIC'),
    );
  }
}

String _stats(List<int> values) {
  final sorted = [...values]..sort();
  return 'median:${sorted[sorted.length ~/ 2]},p95:${sorted[(sorted.length * .95).ceil() - 1]}';
}

class _Auth implements AuthBloc {
  @override
  AuthState get state => const AuthState(
    status: AuthStatus.authenticated,
    session: AuthSession(userId: 'me'),
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
