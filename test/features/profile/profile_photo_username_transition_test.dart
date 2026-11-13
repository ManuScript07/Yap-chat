import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'plaque fades only for gallery and waits for the return flight reduced=$reducedMotion',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        late BuildContext scopeContext;
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: child!,
            ),
            home: Scaffold(
              body: ProfilePhotoTransitionScope(
                builder: (context) {
                  scopeContext = context;
                  return ProfilePhotoUsernameTransition(
                    child: GestureDetector(
                      onTap: () => taps++,
                      child: const Text('username'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final plaque = find.byType(
          ProfilePhotoUsernameTransition,
          skipOffstage: false,
        );
        final opacity = find.descendant(
          of: plaque,
          matching: find.byType(AnimatedOpacity, skipOffstage: false),
        );
        double alpha() =>
            tester.renderObject<RenderAnimatedOpacity>(opacity).opacity.value;
        bool ignoresTaps() => tester
            .widget<IgnorePointer>(
              find.descendant(
                of: plaque,
                matching: find.byType(IgnorePointer, skipOffstage: false),
              ),
            )
            .ignoring;
        expect(alpha(), 1);
        await tester.tap(find.text('username'));
        expect(taps, 1);

        // Opening any other page must leave the plaque's own opacity intact.
        navigator.currentState!.push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const Scaffold(body: Text('other page')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(alpha(), 1);
        expect(ignoresTaps(), isFalse);
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(alpha(), 1);
        await tester.pumpAndSettle();

        var navigationCompleted = false;
        ProfilePhotoTransitionScope.openGallery(
          scopeContext,
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 260),
            reverseTransitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (_, _, _) => const Scaffold(body: Text('photo')),
          ),
        ).then((_) => navigationCompleted = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          alpha(),
          reducedMotion ? 0 : closeTo(1, .001),
          reason: 'Opening must not instantly remove the plaque.',
        );
        expect(ignoresTaps(), isTrue);
        var previous = alpha();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(alpha(), lessThanOrEqualTo(previous));
          if (!reducedMotion && i == 2) {
            expect(alpha(), inExclusiveRange(0, 1));
          }
          previous = alpha();
        }
        expect(alpha(), 0);
        await tester.pumpAndSettle();
        expect(alpha(), 0);

        navigator.currentState!.pop();
        await tester.pump();
        expect(navigationCompleted, isFalse);
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          alpha(),
          0,
          reason: 'Returning photo must land before the plaque appears.',
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(ignoresTaps(), isFalse);
        if (reducedMotion) {
          expect(alpha(), 1);
        } else {
          expect(alpha(), 0);
          await tester.pump(const Duration(milliseconds: 60));
          expect(alpha(), inExclusiveRange(0, 1));
        }
        await tester.pumpAndSettle();
        expect(navigationCompleted, isTrue);
        expect(alpha(), 1);
        await tester.tap(find.text('username'));
        expect(taps, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'closing immediately reverses a partial fade without an opacity jump',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext scopeContext;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: ProfilePhotoTransitionScope(
              builder: (context) {
                scopeContext = context;
                return const ProfilePhotoUsernameTransition(
                  child: Text('username'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final opacity = find.byType(AnimatedOpacity, skipOffstage: false);
      double alpha() =>
          tester.renderObject<RenderAnimatedOpacity>(opacity).opacity.value;
      var completed = false;
      ProfilePhotoTransitionScope.openGallery(
        scopeContext,
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, _, _) => const Scaffold(body: Text('photo')),
        ),
      ).then((_) => completed = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(alpha(), inExclusiveRange(0, 1));
      navigator.currentState!.pop();
      await tester.pump();
      var previous = alpha();
      for (var i = 0; i < 30; i++) {
        final wasRevealing =
            tester.widget<AnimatedOpacity>(opacity).opacity == 1;
        await tester.pump(const Duration(milliseconds: 16));
        final current = alpha();
        expect(
          (current - previous).abs(),
          lessThan(.4),
          reason: 'Never snap to 0 or 1 when interrupted.',
        );
        if (wasRevealing) {
          expect(current, greaterThanOrEqualTo(previous - .001));
        }
        previous = current;
      }
      expect(completed, isTrue);
      expect(alpha(), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated taps open one gallery and disposal releases its scope',
    (tester) async {
      late BuildContext scopeContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfilePhotoTransitionScope(
              builder: (context) {
                scopeContext = context;
                return const ProfilePhotoUsernameTransition(
                  child: Text('username'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var finished = false;
      final first = ProfilePhotoTransitionScope.openGallery(
        scopeContext,
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const Scaffold(body: Text('first gallery')),
        ),
      ).then((_) => finished = true);
      final duplicate = ProfilePhotoTransitionScope.openGallery(
        scopeContext,
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) =>
              const Scaffold(body: Text('duplicate gallery')),
        ),
      );
      await tester.pumpAndSettle();
      await duplicate;
      expect(find.text('first gallery'), findsOneWidget);
      expect(find.text('duplicate gallery'), findsNothing);
      expect(finished, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await first;
      expect(finished, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile arrival and departure never add a plaque fade or delay',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('source')),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, _, _) => Scaffold(
            body: ProfilePhotoTransitionScope(
              builder: (_) =>
                  const ProfilePhotoUsernameTransition(child: Text('username')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final opacity = find.byType(AnimatedOpacity);
      double alpha() =>
          tester.renderObject<RenderAnimatedOpacity>(opacity).opacity.value;
      expect(alpha(), 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(alpha(), 1);
      await tester.pumpAndSettle();
      expect(alpha(), 1);
      navigator.currentState!.pop();
      await tester.pump();
      expect(alpha(), 1);
      // The existing profile route alone owns its transition.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
