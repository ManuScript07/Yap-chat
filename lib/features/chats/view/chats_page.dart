

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:yap_chat/router/router.gr.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/features/chats/chats.dart';
import 'package:yap_chat/core/core.dart';
import 'dart:math' as math;

@RoutePage()
class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final Set<String> _selectedChatIds = {};

  bool get _isSelectionMode => _selectedChatIds.isNotEmpty;

  void _toggleSelection(String chatId) {
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedChatIds.clear();
    });
  }

  final List<Chat> _mockChats = [
    Chat(
      id: '1',
      userName: 'Алексей Иванов',
      lastMessage: 'Привет! Как дела?',
      lastMessageTime: DateTime.now().subtract(const Duration(minutes: 5)),
      unreadCount: 2,
      isOnline: true,
      isLastMessageFromMe: false,
      isMuted: false,
    ),
    Chat(
      id: '2',
      userName: 'Марина Петрова',
      lastMessage: 'Завтра в силе?',
      lastMessageTime: DateTime.now().subtract(const Duration(hours: 2)),
      unreadCount: 0,
      isOnline: false,
      isLastMessageFromMe: true,
      isMuted: true,
    ),
    Chat(
      id: '3',
      userName: 'Разработка Групп',
      lastMessage: 'Скиньте отчет по проекту до конца дня, пожалуйста.',
      lastMessageTime: DateTime.now().subtract(const Duration(days: 1)),
      unreadCount: 15,
      isOnline: true,
      isLastMessageFromMe: false,
      isMuted: false,
    ),
    Chat(
      id: '4',
      userName: 'Игорь С.',
      lastMessage: 'Ок, договорились',
      lastMessageTime: DateTime(2026, 7, 6, 12, 0),
      unreadCount: 0,
      isOnline: false,
      isLastMessageFromMe: false,
      isMuted: false,
    ),
    Chat(
      id: '5',
      userName: 'Служба поддержки',
      lastMessage: 'Ваш запрос №12345 был успешно обработан.',
      lastMessageTime: DateTime.now().subtract(const Duration(days: 4)),
      unreadCount: 0,
      isOnline: true,
      isLastMessageFromMe: false,
      isMuted: false,
    ),
    Chat(
      id: '6',
      userName: 'Служба поддержки 2',
      lastMessage: 'Ваш запрос №12346 был успешно обработан.',
      lastMessageTime: DateTime(2026, 1, 7, 12, 0),
      unreadCount: 0,
      isOnline: true,
      isLastMessageFromMe: false,
      isMuted: false,
    ),
    Chat(
      id: '7',
      userName: 'Служба поддержки 3',
      lastMessage: 'Ваш запрос №12347 был успешно обработан.',
      lastMessageTime: DateTime(2025, 7, 6, 12, 0),
      unreadCount: 0,
      isOnline: true,
      isLastMessageFromMe: false,
      isMuted: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    final rawBottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final effectiveBottomPadding = math.max(rawBottomPadding, 16.0);

    const navBarHeight = 70.0;
    const navBarBottomOffset = 16.0;
    const searchBarSpacing = 16.0;
    const searchBarHeight = 50.0;

    final baseOffset = effectiveBottomPadding + navBarBottomOffset + navBarHeight + searchBarSpacing;

    final searchBarBottomOffset = isKeyboardOpen
        ? keyboardHeight + 16.0
        : baseOffset;

    final glowBottomOffset = isKeyboardOpen
        ? keyboardHeight
        : 0.0;

    // Logic for notifications toggle icon
    bool firstSelectedMuted = false;
    if (_selectedChatIds.isNotEmpty) {
      final firstId = _selectedChatIds.first;
      firstSelectedMuted = _mockChats.firstWhere((c) => c.id == firstId).isMuted;
    }

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: context.scaffoldBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: _isSelectionMode
            ? SelectionToolbar(
          selectedCount: _selectedChatIds.length,
          onClose: _exitSelectionMode,
          isMuted: firstSelectedMuted,
          onToggleNotifications: () {},
          onMarkAsRead: () {},
          onDelete: () {},
        )
            : PrimaryAppBar(
          title: context.l10n.navChats,
          actionIcon: Icons.add_comment_rounded,
          onActionPressed: () => context.router.push(const NewChatRoute()),
        ),
        body: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Список чатов
            ListView.builder(
              padding: EdgeInsets.only(
                top: 130,
                bottom: searchBarBottomOffset + searchBarHeight + 16,
              ),
              itemCount: _mockChats.length,
              itemBuilder: (context, index) {
                final chat = _mockChats[index];
                final isSelected = _selectedChatIds.contains(chat.id);
                return ChatListItem(
                  chat: chat,
                  isSelected: isSelected,
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(chat.id);
                    } else {
                      context.router.push(ChatRoute(chat: chat));
                    }
                  },
                  onLongPress: () {
                    if (!_isSelectionMode) {
                      _toggleSelection(chat.id);
                    }
                  },
                );
              },
            ),

            // Свечение
            AnimatedPositioned(
              duration: const Duration(milliseconds: 0),
              curve: Curves.easeOutQuad,
              left: 0,
              right: 0,
              bottom: glowBottomOffset,
              child: const BottomAmbientGlow(),
            ),

            // Поисковая строка
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutQuad,
              left: 0,
              right: 0,
              bottom: _isSelectionMode ? -100 : searchBarBottomOffset,
              child: GlassSearchBar(
                hintText: context.l10n.searchHintChats,
                onChanged: (value) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}
