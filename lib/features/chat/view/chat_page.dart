import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ChatBloc(chatRepository: context.read<IChatRepository>())
            ..add(ChatStarted(chat.id)),
      child: _ChatView(chat: chat),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView({required this.chat});

  final Chat chat;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLostAttachment();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _restoreLostAttachment() async {
    final pendingPath = await context
        .read<ILocalMediaRepository>()
        .consumePendingMedia();
    if (!mounted || pendingPath == null) return;

    final images = await showAttachmentBottomSheet(
      context,
      chatId: widget.chat.id,
      initiallySelectedPath: pendingPath,
    );
    if (!mounted || images == null || images.isEmpty) return;

    context.read<ChatBloc>().add(ChatMessageImagesSent(images));
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    final topSafeArea = mediaQuery.padding.top;

    const inputContentHeight = 66.0;

    final inputBarHeight = inputContentHeight + mediaQuery.padding.bottom;

    final headerHeight = 64.0 + topSafeArea;

    final backgroundColor = context.scaffoldBackgroundColor;

    return _ChatPopScope(
      child: Scaffold(
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: false,

        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: Stack(
            children: [
              _ChatMessages(
                controller: _scrollController,
                chat: widget.chat,
                headerHeight: headerHeight,
                inputBarHeight: inputBarHeight,
              ),

              _GradientOverlay(
                height: headerHeight + 20,
                isTop: true,
                backgroundColor: backgroundColor,
              ),

              _GradientOverlay(
                height: inputBarHeight + 20,
                isTop: false,
                backgroundColor: backgroundColor,
              ),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ChatAppBar(
                  userName: widget.chat.userName,
                  isOnline: widget.chat.isOnline,
                  avatarUrl: widget.chat.avatarUrl,
                  onBack: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),

              _KeyboardAwareInput(
                chatId: widget.chat.id,
                onMessageSent: _scrollToBottom,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyboardAwareInput extends StatelessWidget {
  const _KeyboardAwareInput({
    required this.chatId,
    required this.onMessageSent,
  });

  final String chatId;
  final VoidCallback onMessageSent;

  Future<void> _openAttachmentSheet(BuildContext context) async {
    final images = await showAttachmentBottomSheet(context, chatId: chatId);

    if (images != null && images.isNotEmpty && context.mounted) {
      context.read<ChatBloc>().add(ChatMessageImagesSent(images));
      onMessageSent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: MessageInputBar(
          onSend: (text) {
            context.read<ChatBloc>().add(ChatMessageSent(text));
            onMessageSent();
          },
          // 2. Вызываем вынесенный метод
          onAddPhoto: () => _openAttachmentSheet(context),
        ),
      ),
    );
  }
}

class _ChatPopScope extends StatelessWidget {
  const _ChatPopScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: !isKeyboardOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: child,
    );
  }
}

class _ChatMessages extends StatefulWidget {
  const _ChatMessages({
    required this.controller,
    required this.chat,
    required this.headerHeight,
    required this.inputBarHeight,
  });

  final ScrollController controller;
  final Chat chat;
  final double headerHeight;
  final double inputBarHeight;

  @override
  State<_ChatMessages> createState() => _ChatMessagesState();
}

class _ChatMessagesState extends State<_ChatMessages> {
  bool _showScrollToBottom = false;
  int _newMessagesCount = 0;

  Set<String> _knownMessageIds = {};
  bool _initialMessagesLoaded = false;

  // Для отслеживания направления скролла
  double _lastOffset = 0.0;
  bool _isAnimatingToBottom = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() {
    // Если мы сейчас программно скроллим вниз — игнорируем события,
    // чтобы кнопка не появлялась случайно в процессе анимации.
    if (!widget.controller.hasClients || _isAnimatingToBottom) return;

    final offset = widget.controller.offset;
    final isAtBottom = offset <= 20;

    // Если достигли низа — всегда прячем кнопку и сбрасываем счетчик
    if (isAtBottom) {
      if (_showScrollToBottom || _newMessagesCount != 0) {
        setState(() {
          _showScrollToBottom = false;
          _newMessagesCount = 0;
        });
      }
      _lastOffset = offset;
      return;
    }

    // Вычисляем разницу:
    // delta > 0 значит offset растет (мы листаем ВВЕРХ к истории)
    // delta < 0 значит offset падает (мы листаем ВНИЗ к новым сообщениям)
    final delta = offset - _lastOffset;

    if (delta > 2.0) {
      // Пользователь скроллит ВВЕРХ — прячем кнопку
      if (_showScrollToBottom) {
        setState(() {
          _showScrollToBottom = false;
        });
      }
    } else if (delta < -2.0) {
      // Пользователь скроллит ВНИЗ — показываем кнопку
      if (!_showScrollToBottom) {
        setState(() {
          _showScrollToBottom = true;
        });
      }
    }

    _lastOffset = offset;
  }

  void _handleMessagesChanged(List<ChatMessage> messages) {
    final currentIds = messages.map((message) => message.id).toSet();

    if (!_initialMessagesLoaded) {
      _knownMessageIds = currentIds;
      _initialMessagesLoaded = true;
      return;
    }

    final newMessages = messages
        .where((message) => !_knownMessageIds.contains(message.id))
        .toList();

    _knownMessageIds = currentIds;

    if (newMessages.isEmpty) return;

    final hasMine = newMessages.any((m) => m.isMine);
    final isAtBottom =
        !widget.controller.hasClients || widget.controller.offset <= 20;

    if (hasMine) {
      _scrollToBottom();
    } else if (!isAtBottom) {
      // Пришло чужое сообщение, а мы находимся высоко в истории.
      // ВСЕГДА показываем кнопку и увеличиваем счетчик.
      setState(() {
        _showScrollToBottom = true;
        _newMessagesCount += newMessages.length;
      });
    } else {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_newMessagesCount != 0 || _showScrollToBottom) {
      setState(() {
        _newMessagesCount = 0;
        _showScrollToBottom = false;
      });
    }

    if (!widget.controller.hasClients) return;

    // Включаем блокировку, чтобы _handleScroll не мешал
    _isAnimatingToBottom = true;

    widget.controller
        .animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          // Снимаем блокировку по завершении анимации
          _isAnimatingToBottom = false;
        });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatBloc, ChatState>(
      listenWhen: (previous, current) => previous.messages != current.messages,
      listener: (context, state) {
        _handleMessagesChanged(state.messages);
      },
      child: BlocBuilder<ChatBloc, ChatState>(
        buildWhen: (previous, current) {
          return previous.status != current.status ||
              previous.messages != current.messages ||
              previous.initialMessageIds != current.initialMessageIds;
        },
        builder: (context, state) {
          if (state.status == ChatStatus.loading) {
            return Center(
              child: CircularProgressIndicator(
                color: context.colorScheme.primary,
              ),
            );
          }

          if (state.messages.isEmpty) {
            return Center(
              child: Text(
                context.l10n.noMessages,
                style: TextStyle(
                  color: context.colorScheme.onSurfaceVariant,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            );
          }

          // Отрезаем новые сообщения из отрисовки, пока не проскроллим вниз,
          // чтобы интерфейс не дергался
          List<ChatMessage> displayedMessages = state.messages;
          if (_newMessagesCount > 0 &&
              state.messages.length >= _newMessagesCount) {
            displayedMessages = state.messages.skip(_newMessagesCount).toList();
          }

          return Stack(
            children: [
              _MessagesList(
                controller: widget.controller,
                chat: widget.chat,
                messages: displayedMessages,
                initialMessageIds: state.initialMessageIds,
                headerHeight: widget.headerHeight,
                inputBarHeight: widget.inputBarHeight,
              ),

              Positioned(
                right: 16,
                bottom:
                    widget.inputBarHeight +
                    MediaQuery.viewInsetsOf(context).bottom +
                    20,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  reverseDuration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.85,
                          end: 1.0,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _showScrollToBottom
                      ? _ScrollToBottomButton(
                          key: const ValueKey('scroll_to_bottom'),
                          newMessagesCount: _newMessagesCount,
                          onPressed: _scrollToBottom,
                        )
                      : const SizedBox(
                          key: ValueKey('scroll_to_bottom_hidden'),
                          width: 50,
                          height: 50,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({
    required this.controller,
    required this.chat,
    required this.messages,
    required this.initialMessageIds,
    required this.headerHeight,
    required this.inputBarHeight,
  });

  final ScrollController controller;
  final Chat chat;
  final List<ChatMessage> messages;
  final Set<String> initialMessageIds;

  final double headerHeight;
  final double inputBarHeight;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    final items = <ChatListItemElement>[];
    final itemIndexByKey = <String, int>{};

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];

      final messageItem = MessageItemElement(message);

      itemIndexByKey['msg_${message.id}'] = items.length;
      items.add(messageItem);

      final isLast = i == messages.length - 1;

      if (isLast) {
        final separator = DateSeparatorElement(message.timestamp);

        itemIndexByKey['date_${message.timestamp.millisecondsSinceEpoch}'] =
            items.length;

        items.add(separator);

        continue;
      }

      final current = message.timestamp;
      final next = messages[i + 1].timestamp;

      final sameDay =
          current.year == next.year &&
          current.month == next.month &&
          current.day == next.day;

      if (!sameDay) {
        final separator = DateSeparatorElement(message.timestamp);

        itemIndexByKey['date_${message.timestamp.millisecondsSinceEpoch}'] =
            items.length;

        items.add(separator);
      }
    }

    final bottomPadding = inputBarHeight + keyboardHeight + 12.0;

    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: EdgeInsets.only(
        top: headerHeight + 12.0,
        bottom: bottomPadding,
        left: 16.0,
        right: 16.0,
      ),

      itemCount: items.length,

      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          return itemIndexByKey[key.value];
        }

        return null;
      },

      itemBuilder: (context, index) {
        final item = items[index];

        final key = switch (item) {
          MessageItemElement(:final message) => ValueKey<String>(
            'msg_${message.id}',
          ),

          DateSeparatorElement(:final date) => ValueKey<String>(
            'date_${date.millisecondsSinceEpoch}',
          ),
        };

        return Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: switch (item) {
            MessageItemElement(:final message) => MessageBubble(
              message: message,
              isNew: !initialMessageIds.contains(message.id),
              maxWidth: screenWidth * 0.8,
              peerName: chat.userName,
              peerAvatarUrl: chat.avatarUrl,
            ),

            DateSeparatorElement(:final date) => DateSeparator(date: date),
          },
        );
      },
    );
  }
}

class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({
    super.key,
    required this.newMessagesCount,
    required this.onPressed,
  });

  final int newMessagesCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlassIconButton(
          icon: Icons.keyboard_arrow_down_rounded,
          onTap: onPressed,
          width: 50,
          height: 50,
          borderRadius: 36,
          iconSize: 36,
        ),

        if (newMessagesCount > 0)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: context.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.scaffoldBackgroundColor,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                newMessagesCount > 99 ? '99+' : '$newMessagesCount',
                style: TextStyle(
                  color: context.scaffoldBackgroundColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Переиспользуемый виджет для градиентных оверлеев
class _GradientOverlay extends StatelessWidget {
  final double height;
  final bool isTop;
  final Color backgroundColor;

  const _GradientOverlay({
    required this.height,
    required this.isTop,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [backgroundColor, backgroundColor.withValues(alpha: 0.0)],
            ),
          ),
        ),
      ),
    );
  }
}

sealed class ChatListItemElement {}

class MessageItemElement extends ChatListItemElement {
  MessageItemElement(this.message);

  final ChatMessage message;
}

class DateSeparatorElement extends ChatListItemElement {
  DateSeparatorElement(this.date);

  final DateTime date;
}
