import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/chats/chats.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/utils/utils.dart';

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets('selection limit feedback is localized $locale', (
      tester,
    ) async {
      final repository = _Repository();
      final bloc = ChatsBloc(chatsRepository: repository);
      addTearDown(bloc.close);
      bloc.add(
        ChatsSubscriptionUpdated([
          for (var i = 0; i < 51; i++) _chat('$i', false),
        ]),
      );
      for (var i = 0; i < 50; i++) {
        bloc.add(ChatSelectionToggled('$i'));
      }
      await tester.pumpWidget(
        RepositoryProvider<IChatsRepository>.value(
          value: repository,
          child: BlocProvider.value(
            value: bloc,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ChatsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      bloc.add(const ChatSelectionToggled('50'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ChatsPage));
      expect(
        find.text(AppLocalizations.of(context)!.chatsSelectionLimit(50)),
        findsOneWidget,
      );
      expect(bloc.state.selectedChatIds, hasLength(50));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final size in [
    const Size(320, 720),
    const Size(390, 780),
    const Size(780, 390),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('mute icon survives long name $size scale=$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const name =
            'Очень длинное имя пользователя с длинной фамилией Long display name';
        final chat = _chat('a', true).copyWith(userName: name);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: ChatListItem(
                  chat: chat,
                  onTap: () {},
                  onLongPress: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final icon = tester.widget<Icon>(
          find.byIcon(Icons.notifications_off_rounded),
        );
        final context = tester.element(find.byType(ChatListItem));
        final time = tester.widget<Text>(
          find.text(TimeFormatter.format(context, chat.lastMessageTime)),
        );
        expect(icon.color, time.style!.color);
        final iconRect = tester.getRect(
          find.byIcon(Icons.notifications_off_rounded),
        );
        final nameRect = tester.getRect(find.text(name));
        final timeRect = tester.getRect(find.byWidget(time));
        expect(iconRect.left, greaterThanOrEqualTo(nameRect.right + 3));
        expect(iconRect.right, lessThan(timeRect.left));
        expect(iconRect.right, lessThanOrEqualTo(size.width));
        final ink = tester.widget<InkWell>(find.byType(InkWell));
        expect(ink.splashFactory, NoSplash.splashFactory);
        expect(ink.highlightColor, Colors.transparent);
        expect(ink.hoverColor, Colors.transparent);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('toolbar updates when a non-first selected row changes mute', (
    tester,
  ) async {
    final repository = _Repository();
    final bloc = ChatsBloc(chatsRepository: repository);
    addTearDown(bloc.close);
    bloc.add(ChatsSubscriptionUpdated([_chat('a', false), _chat('b', false)]));
    bloc.add(const ChatSelectionToggled('a'));
    bloc.add(const ChatSelectionToggled('b'));
    await tester.pumpWidget(
      RepositoryProvider<IChatsRepository>.value(
        value: repository,
        child: BlocProvider.value(value: bloc, child: _app(const ChatsPage())),
      ),
    );
    await tester.pumpAndSettle();
    final toolbar = find.byType(SelectionToolbar);
    expect(
      find.descendant(
        of: toolbar,
        matching: find.byIcon(Icons.notifications_off_rounded),
      ),
      findsOneWidget,
    );
    bloc.add(ChatsSubscriptionUpdated([_chat('a', false), _chat('b', true)]));
    await tester.pumpAndSettle();
    final enable = find.descendant(
      of: toolbar,
      matching: find.byIcon(Icons.notifications_active_rounded),
    );
    expect(enable, findsOneWidget);
    await tester.tap(enable);
    await tester.pumpAndSettle();
    expect(repository.calls, [
      {'b'},
    ]);
    expect(repository.target, false);
    final context = tester.element(find.byType(ChatsPage));
    expect(
      find.text(AppLocalizations.of(context)!.chatsNotificationsEnabled),
      findsOneWidget,
    );
    expect(bloc.state.chats.every((chat) => !chat.isMuted), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'short name keeps icon adjacent and selection tint survives taps',
    (tester) async {
      var taps = 0;
      var longPresses = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ChatListItem(
              chat: _chat('Ann', true),
              isSelected: true,
              onTap: () => taps++,
              onLongPress: () => longPresses++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.getRect(find.text('Ann'));
      final icon = tester.getRect(find.byIcon(Icons.notifications_off_rounded));
      expect(icon.left - text.right, closeTo(4, .01));
      final ink = tester.widget<InkWell>(find.byType(InkWell));
      expect((ink.child as Container).color!.a, closeTo(.1, .01));
      await tester.tap(find.text('Ann'));
      await tester.longPress(find.text('Ann'));
      expect(taps, 1);
      expect(longPresses, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(Widget home) => MaterialApp(
  theme: ThemeData.dark(),
  locale: const Locale('ru'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Chat _chat(String id, bool muted) => Chat(
  id: id,
  userName: id,
  lastMessage: 'preview',
  lastMessageTime: DateTime(2026),
  unreadCount: 1,
  isOnline: false,
  isLastMessageFromMe: false,
  isMuted: muted,
);

class _Repository extends MockChatsRepository {
  final calls = <Set<String>>[];
  bool? target;
  @override
  Future<void> setMuted(Set<String> ids, {required bool isMuted}) async {
    calls.add(Set.of(ids));
    target = isMuted;
  }
}
