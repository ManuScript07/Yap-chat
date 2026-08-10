import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/repositories/repositories.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ChatPage extends StatelessWidget {
  const ChatPage({
    super.key,
    required this.chat,
  });

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatBloc(
        chatRepository: context.read<IChatRepository>(),
      )..add(ChatStarted(chat.id)),
      child: _ChatView(chat: chat),
    );
  }
}

class _ChatView extends StatelessWidget {
  const _ChatView({required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    final topSafeArea = MediaQuery.paddingOf(context).top;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;

    // Проверяем, открыта ли сейчас клавиатура
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    final headerHeight = 64.0 + topSafeArea;
    final inputBarHeight = 70.0 + bottomSafeArea;

    final backgroundColor = context.scaffoldBackgroundColor;
    final colorScheme = context.colorScheme;

    return PopScope(
      canPop: !isKeyboardOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              // 1. Список сообщений
              BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state.status == ChatStatus.loading) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                    );
                  }

                  if (state.messages.isEmpty) {
                    return Center(
                      child: Text(
                        'Нет сообщений',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    );
                  }

                  final items = <ChatListItemElement>[];
                  for (var i = 0; i < state.messages.length; i++) {
                    final currentMessage = state.messages[i];
                    items.add(MessageItemElement(currentMessage));

                    final isLast = i == state.messages.length - 1;
                    if (isLast) {
                      items.add(DateSeparatorElement(currentMessage.timestamp));
                    } else {
                      final nextMessage = state.messages[i + 1];
                      final currentDate = DateTime(
                        currentMessage.timestamp.year,
                        currentMessage.timestamp.month,
                        currentMessage.timestamp.day,
                      );
                      final nextDate = DateTime(
                        nextMessage.timestamp.year,
                        nextMessage.timestamp.month,
                        nextMessage.timestamp.day,
                      );

                      if (currentDate != nextDate) {
                        items.add(DateSeparatorElement(currentMessage.timestamp));
                      }
                    }
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.only(
                      top: headerHeight + 12,
                      bottom: inputBarHeight + 12,
                      left: 16,
                      right: 16,
                    ),
                    itemCount: items.length,

                    // 1. ДОБАВЛЯЕМ ЭТОТ КОЛБЭК: он помогает Flutter найти виджет,
                    // если его индекс изменился (например, при добавлении нового сообщения)
                    findChildIndexCallback: (Key key) {
                      if (key is ValueKey<String>) {
                        final index = items.indexWhere((item) {
                          if (item is MessageItemElement) {
                            return 'msg_${item.message.id}' == key.value;
                          } else if (item is DateSeparatorElement) {
                            return 'date_${item.date.millisecondsSinceEpoch}' == key.value;
                          }
                          return false;
                        });
                        if (index >= 0) return index;
                      }
                      return null;
                    },

                    itemBuilder: (context, index) {
                      final item = items[index];

                      // 2. Генерируем уникальный строковый ключ для каждого элемента
                      final itemKey = switch (item) {
                        MessageItemElement(:final message) => ValueKey<String>('msg_${message.id}'),
                        DateSeparatorElement(:final date) => ValueKey<String>('date_${date.millisecondsSinceEpoch}'),
                      };

                      // 3. Вешаем ключ на самый верхний виджет ячейки (Padding)
                      return Padding(
                        key: itemKey, // <-- КЛЮЧ ДОЛЖЕН БЫТЬ ЗДЕСЬ
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: switch (item) {
                          MessageItemElement(:final message) => MessageBubble(
                            // Здесь ключ уже не нужен, так как он висит на Padding
                            message: message,
                            isNew: !state.initialMessageIds.contains(message.id),
                          ),
                          DateSeparatorElement(:final date) => DateSeparator(date: date),
                        },
                      );
                    },
                  );
                },
              ),

              // 2. Верхнее градиентное затемнение
              _GradientOverlay(
                height: headerHeight + 20,
                isTop: true,
                backgroundColor: backgroundColor,
              ),

              // 3. Нижнее градиентное затемнение
              _GradientOverlay(
                height: inputBarHeight + 20,
                isTop: false,
                backgroundColor: backgroundColor,
              ),

              // 4. Шапка чата
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ChatAppBar(
                  userName: chat.userName,
                  isOnline: chat.isOnline,
                  avatarUrl: chat.avatarUrl,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),

              // 5. Панель ввода сообщения
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: MessageInputBar(
                  onSend: (text) {
                    context.read<ChatBloc>().add(ChatMessageSent(text));
                  },
                  onAddPhoto: () {
                    // TODO: Реализовать добавление фото
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
              colors: [
                backgroundColor,
                backgroundColor.withValues(alpha: 0.0),
              ],
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
