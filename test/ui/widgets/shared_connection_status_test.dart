import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/utils/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['RobotoFlex', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
    }
  });

  for (final locale in ['ru', 'en']) {
    for (final size in [
      const Size(320, 720),
      const Size(360, 800),
      const Size(780, 390),
    ]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('shared headers fit $locale $size scale=$scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final status = _status();
          addTearDown(status.dispose);
          var actions = 0;
          var backs = 0;
          var profiles = 0;
          var surroundingBuilds = 0;
          await tester.pumpWidget(
            _app(
              locale: locale,
              scale: scale,
              child: Builder(
                builder: (context) => PrimaryAppBar(
                  title: context.l10n.navChats,
                  actionIcon: Icons.add_comment_rounded,
                  onActionPressed: () {},
                ),
              ),
            ),
          );
          final ordinaryTitleRect = tester.getRect(
            find.descendant(
              of: find.byType(PrimaryAppBar),
              matching: find.byType(Text),
            ),
          );
          final ordinaryActionRect = tester.getRect(find.byType(IconButton));
          await tester.pumpWidget(
            RepositoryProvider<AppConnectionStatus>.value(
              value: status,
              child: _app(
                locale: locale,
                scale: scale,
                child: Builder(
                  builder: (context) {
                    surroundingBuilds++;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PrimaryAppBar(
                          title: context.l10n.navChats,
                          titleWidget: ConnectionStatusTitle(
                            title: context.l10n.navChats,
                          ),
                          actionIcon: Icons.add_comment_rounded,
                          onActionPressed: () => actions++,
                        ),
                        ChatAppBar(
                          userName: 'Очень длинное имя Long display name',
                          isOnline: true,
                          onBack: () => backs++,
                          onProfileTap: () => profiles++,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
          final primary = find.byType(PrimaryAppBar);
          final chat = find.byType(ChatAppBar);
          final action = find.byType(IconButton);
          final avatar = find.byType(UserAvatar);
          final title = find.byType(ConnectionStatusTitle);
          final connectionStatus = find.descendant(
            of: chat,
            matching: find.byType(ConnectionStatusBuilder),
          );
          expect(connectionStatus, findsOneWidget);
          final statusSwitcher = find.descendant(
            of: connectionStatus,
            matching: find.byType(AnimatedStatusSwitcher),
          );
          expect(statusSwitcher, findsOneWidget);
          final l10n = AppLocalizations.of(tester.element(chat))!;
          final primaryRect = tester.getRect(primary);
          final chatRect = tester.getRect(chat);
          final actionRect = tester.getRect(action);
          final avatarRect = tester.getRect(avatar);
          final titleRect = tester.getRect(title);
          final statusRect = tester.getRect(statusSwitcher);
          final builds = surroundingBuilds;
          expect(titleRect.height, closeTo(52 * scale, .01));
          expect(tester.getRect(find.text(l10n.navChats)), ordinaryTitleRect);
          expect(actionRect, ordinaryActionRect);
          final ordinary = tester.widget<Text>(find.text(l10n.navChats));
          expect(ordinary.style, AppTextStyles.titleLargeFlex);
          expect(ordinary.overflow, TextOverflow.ellipsis);
          expect(
            find.ancestor(
              of: find.text(l10n.navChats),
              matching: find.byType(FittedBox),
            ),
            findsNothing,
          );

          status.reportNetworkAvailability(false);
          await tester.pump();
          final connectingTitle = find.descendant(
            of: primary,
            matching: find.byType(AnimatedConnectingText),
          );
          final connectingStatus = find.descendant(
            of: connectionStatus,
            matching: find.byType(AnimatedConnectingText),
          );
          for (var frame = 0; frame < 10; frame++) {
            await tester.pump(const Duration(milliseconds: 30));
            final titleLabel = tester.getRect(connectingTitle);
            final statusLabel = tester.getRect(connectingStatus);
            expect(titleLabel.left, closeTo(titleRect.left, .01));
            expect(titleLabel.right, lessThanOrEqualTo(actionRect.left + .01));
            expect(statusLabel.left, closeTo(statusRect.left, .01));
            expect(
              statusLabel.right,
              lessThanOrEqualTo(statusRect.right + .01),
            );
            expect(
              statusLabel.height,
              lessThanOrEqualTo(statusRect.height + .01),
            );
            expect(tester.getRect(primary), primaryRect);
            expect(tester.getRect(chat), chatRect);
            expect(tester.getRect(action), actionRect);
            expect(tester.getRect(avatar), avatarRect);
            expect(tester.getRect(statusSwitcher), statusRect);
            expect(tester.takeException(), isNull);
          }
          final style = tester
              .widget<AnimatedConnectingText>(connectingStatus)
              .style;
          expect(
            tester
                .widget<AnimatedConnectingText>(connectingTitle)
                .style
                .fontSize,
            36,
          );
          expect(
            style.color,
            Theme.of(tester.element(connectingStatus)).colorScheme.onSurface,
          );
          expect(style.fontWeight, FontWeight.w400);
          expect(style.fontSize, 14);
          expect(tester.widget<ChatAppBar>(chat).isOnline, isTrue);
          expect(surroundingBuilds, builds);
          status.setForeground(false);
          await tester.pump(const Duration(milliseconds: 100));
          expect(connectingTitle, findsOneWidget);
          expect(connectingStatus, findsOneWidget);
          expect(find.text(l10n.navChats), findsNothing);
          expect(find.text(l10n.chatOnlineStatus), findsNothing);
          status.setForeground(true);
          await tester.pump(const Duration(milliseconds: 100));
          expect(connectingTitle, findsOneWidget);
          expect(connectingStatus, findsOneWidget);
          await tester.tap(action);
          await tester.tap(find.byIcon(Icons.arrow_back_rounded));
          await tester.tap(avatar);
          expect(actions, 1);
          expect(backs, 1);
          expect(profiles, 1);

          // Reversals preserve the start edge and fixed label/header geometry.
          for (final available in [true, false, true]) {
            status.reportNetworkAvailability(available);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 45));
            expect(tester.getRect(action), actionRect);
            expect(tester.getRect(chat), chatRect);
            expect(tester.getRect(statusSwitcher), statusRect);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpAndSettle();
          expect(find.text(l10n.navChats), findsOneWidget);
          expect(find.text(l10n.chatOnlineStatus), findsOneWidget);
          expect(
            tester.widget<Text>(find.text(l10n.chatOnlineStatus)).style!.color,
            AppColors.incomingBubble,
          );
          expect(
            tester
                .widget<Text>(find.text(l10n.chatOnlineStatus))
                .style!
                .fontWeight,
            FontWeight.w600,
          );
          expect(find.byType(AnimatedConnectingText), findsNothing);
          expect(surroundingBuilds, builds);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('late consumer immediately receives retained shared status', (
    tester,
  ) async {
    final status = _status();
    addTearDown(status.dispose);
    final showChat = ValueNotifier(false);
    addTearDown(showChat.dispose);
    await tester.pumpWidget(
      RepositoryProvider<AppConnectionStatus>.value(
        value: status,
        child: _app(
          child: ValueListenableBuilder<bool>(
            valueListenable: showChat,
            builder: (context, visible, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PrimaryAppBar(
                  title: 'чатикс',
                  titleWidget: ConnectionStatusTitle(title: 'чатикс'),
                ),
                if (visible)
                  const ChatAppBar(userName: 'Peer', isOnline: false),
              ],
            ),
          ),
        ),
      ),
    );
    status.reportNetworkAvailability(false);
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedConnectingText), findsOneWidget);
    showChat.value = true;
    await tester.pump();
    expect(find.byType(AnimatedConnectingText), findsNWidgets(2));
    final chatLabel = find.descendant(
      of: find.byType(ChatAppBar),
      matching: find.byType(AnimatedConnectingText),
    );
    final style = tester.widget<AnimatedConnectingText>(chatLabel).style;
    expect(style.fontWeight, FontWeight.w400);
    expect(style.color, tester.element(chatLabel).colorScheme.onSurface);
    status.reportNetworkAvailability(true);
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedConnectingText), findsNothing);
    expect(find.text('не в сети'), findsOneWidget);
    // Removing listeners does not dispose the shared service.
    showChat.value = false;
    await tester.pumpAndSettle();
    status.reportNetworkAvailability(false);
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedConnectingText), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    status.reportNetworkAvailability(true);
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['ru', 'en']) {
    testWidgets('no provider retains ordinary titles and last seen $locale', (
      tester,
    ) async {
      final lastSeen = DateTime.now().subtract(const Duration(hours: 2));
      await tester.pumpWidget(
        _app(
          locale: locale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PrimaryAppBar(
                title: 'ordinary',
                titleWidget: ConnectionStatusTitle(title: 'ordinary'),
              ),
              ChatAppBar(
                userName: 'Peer',
                isOnline: false,
                lastSeenAt: lastSeen,
              ),
            ],
          ),
        ),
      );
      final context = tester.element(find.byType(ChatAppBar));
      expect(find.text('ordinary'), findsOneWidget);
      expect(
        find.text(TimeFormatter.formatLastSeen(context, lastSeen)),
        findsOneWidget,
      );
      expect(find.byType(AnimatedConnectingText), findsNothing);
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'connecting stays neutral and restores the latest actual peer status',
    (tester) async {
      final status = _status();
      addTearDown(status.dispose);
      final online = ValueNotifier(true);
      addTearDown(online.dispose);
      final lastSeen = DateTime.now().subtract(const Duration(minutes: 10));
      await tester.pumpWidget(
        RepositoryProvider<AppConnectionStatus>.value(
          value: status,
          child: _app(
            child: ValueListenableBuilder<bool>(
              valueListenable: online,
              builder: (context, isOnline, _) => ChatAppBar(
                userName: 'Peer',
                isOnline: isOnline,
                lastSeenAt: lastSeen,
              ),
            ),
          ),
        ),
      );
      status.reportNetworkAvailability(false);
      await tester.pumpAndSettle();
      expect(online.value, isTrue);
      expect(
        tester
            .widget<AnimatedConnectingText>(find.byType(AnimatedConnectingText))
            .style
            .color,
        Theme.of(tester.element(find.byType(ChatAppBar))).colorScheme.onSurface,
      );
      online.value = false;
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ChatAppBar));
      final connecting = tester.widget<AnimatedConnectingText>(
        find.byType(AnimatedConnectingText),
      );
      expect(connecting.style.color, context.colorScheme.onSurface);
      expect(connecting.style.fontWeight, FontWeight.w400);
      status.reportNetworkAvailability(true);
      await tester.pumpAndSettle();
      expect(online.value, isFalse);
      expect(
        find.text(TimeFormatter.formatLastSeen(context, lastSeen)),
        findsOneWidget,
      );
      expect(find.byType(AnimatedConnectingText), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

AppConnectionStatus _status() => AppConnectionStatus(
  accountSessionController: AccountSessionController(initialUserId: 'u'),
  presentationDelay: Duration.zero,
);

Widget _app({required Widget child, String locale = 'ru', double scale = 1}) =>
    MaterialApp(
      theme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
      ),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
          padding:
              MediaQuery.sizeOf(context).width >
                  MediaQuery.sizeOf(context).height
              ? const EdgeInsets.only(left: 28, right: 12)
              : const EdgeInsets.only(top: 24),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(alignment: Alignment.topCenter, child: child),
      ),
    );
