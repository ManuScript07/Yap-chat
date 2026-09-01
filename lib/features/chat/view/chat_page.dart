import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/widgets.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/notifications/notifications.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => ChatBloc(
            chatRepository: context.read<IChatRepository>(),
            chatsRepository: context.read<IChatsRepository>(),
            initialChat: chat,
          )..add(ChatStarted(chat.id)),
        ),
        BlocProvider(
          create: (context) => VoiceRecorderCubit(
            recorderRepository: context.read<IAudioRecorderRepository>(),
            playerRepository: context.read<IAudioPlayerRepository>(),
          ),
        ),
      ],
      child: BlocBuilder<ChatBloc, ChatState>(
        buildWhen: (previous, current) =>
            previous.resolvedChat != current.resolvedChat,
        builder: (context, state) {
          final activeChat = state.resolvedChat ?? chat;
          if (activeChat.isDraft) return _ChatView(chat: activeChat);

          return StreamBuilder<Chat?>(
            key: ValueKey(activeChat.id),
            stream: context.read<IChatsRepository>().watchChat(activeChat.id),
            initialData: activeChat,
            builder: (context, snapshot) =>
                _ChatView(chat: snapshot.data ?? activeChat),
          );
        },
      ),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView({required this.chat});

  final Chat chat;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView>
    with AutoRouteAwareStateMixin<_ChatView>, WidgetsBindingObserver {
  late final ScrollController _scrollController;
  NotificationsCubit? _notificationsCubit;
  late DateTime? _lastSeenAt;
  double? _composerHeight;
  double _lastKeyboardInset = 0;
  bool _hasKeyboardInset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController();
    _lastSeenAt = widget.chat.lastSeenAt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLostAttachment();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasKeyboardInset) {
      _lastKeyboardInset = MediaQuery.viewInsetsOf(context).bottom;
      _hasKeyboardInset = true;
    }
    _notificationsCubit ??= context.read<NotificationsCubit>();
    if (!widget.chat.isDraft) {
      unawaited(_notificationsCubit!.setActiveConversation(widget.chat.id));
    }
  }

  @override
  void didUpdateWidget(covariant _ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat.id != widget.chat.id) {
      if (!oldWidget.chat.isDraft) {
        unawaited(
          _notificationsCubit?.clearActiveConversation(oldWidget.chat.id),
        );
      }
      if (!widget.chat.isDraft) {
        unawaited(_notificationsCubit?.setActiveConversation(widget.chat.id));
      }
    }
    if (oldWidget.chat.lastSeenAt != widget.chat.lastSeenAt) {
      _lastSeenAt = widget.chat.lastSeenAt;
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;

    final view = View.maybeOf(context);
    if (view == null) return;

    final keyboardInset = MediaQueryData.fromView(view).viewInsets.bottom;
    final wasKeyboardOpen = _lastKeyboardInset > 0;
    _lastKeyboardInset = keyboardInset;

    if (wasKeyboardOpen && keyboardInset <= 0) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  void didPush() {
    if (!widget.chat.isDraft) {
      unawaited(_notificationsCubit?.setActiveConversation(widget.chat.id));
    }
  }

  @override
  void didPopNext() {
    if (!widget.chat.isDraft) {
      unawaited(_notificationsCubit?.setActiveConversation(widget.chat.id));
    }
  }

  @override
  void didPushNext() {
    if (!widget.chat.isDraft) {
      unawaited(_notificationsCubit?.clearActiveConversation(widget.chat.id));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!widget.chat.isDraft) {
      unawaited(_notificationsCubit?.clearActiveConversation(widget.chat.id));
    }
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

  void _onComposerHeightChanged(double height) {
    if ((_composerHeight == null ? height : _composerHeight! - height).abs() <
        0.5) {
      return;
    }
    setState(() => _composerHeight = height);
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final action = await showMessageActionsBottomSheet(
      context,
      message: message,
    );
    if (!mounted || action == null) return;

    switch (action) {
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.text));
      case MessageAction.reply:
        context.read<ChatBloc>().add(ChatReplySelected(message));
      case MessageAction.delete:
        context.read<ChatBloc>().add(ChatMessageDeleteRequested(message));
    }
  }

  Future<void> _restoreLostAttachment() async {
    final pendingPath = await context
        .read<ILocalMediaRepository>()
        .consumePendingMedia();
    if (!mounted || pendingPath == null) return;

    final selection = await showAttachmentBottomSheet(
      context,
      chatId: widget.chat.id,
      peerName: widget.chat.userName,
      initiallySelectedPath: pendingPath,
    );
    if (!mounted || selection?.imagePaths == null) return;

    final images = selection!.imagePaths!;
    if (images.isEmpty) return;
    context.read<ChatBloc>().add(ChatMessageImagesSent(images));
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    final topSafeArea = mediaQuery.padding.top;

    const inputContentHeight = 66.0;

    final inputBarHeight = inputContentHeight + mediaQuery.padding.bottom;
    final composerHeight = _composerHeight ?? inputBarHeight;

    final headerHeight = 64.0 + topSafeArea;

    final backgroundColor = context.scaffoldBackgroundColor;
    final presence = context.watch<PresenceCubit>().state;
    final isOnline = widget.chat.blockedByPeer
        ? false
        : widget.chat.peerId.isEmpty
        ? widget.chat.isOnline
        : presence.isOnline(widget.chat.peerId);
    final blocklistState = context.watch<BlocklistCubit>().state;
    final blockedByMe = widget.chat.peerId.isNotEmpty &&
        (blocklistState.blocks(widget.chat.peerId) ||
            (!blocklistState.isLoaded && widget.chat.blockedByMe));

    return BlocListener<PresenceCubit, PresenceState>(
      listenWhen: (previous, current) =>
          previous.isOnline(widget.chat.peerId) &&
          !current.isOnline(widget.chat.peerId),
      listener: (context, state) {
        if (!context.mounted ||
            state.isOnline(widget.chat.peerId) ||
            !widget.chat.showsLastSeen) {
          return;
        }
        setState(() => _lastSeenAt = DateTime.now());
      },
      child: BlocListener<VoiceRecorderCubit, VoiceRecorderState>(
        listenWhen: (previous, current) =>
            previous.permissionStatus != current.permissionStatus &&
            current.permissionStatus != null,
        listener: (context, state) async {
          final permissionStatus = state.permissionStatus;
          if (permissionStatus == null) return;

          await showPermissionDeniedDialog(
            context,
            title: context.l10n.microphonePermissionDenied,
            content: context.l10n.microphonePermissionSettingsDescription,
            onOpenSettings: () {
              context.read<VoiceRecorderCubit>().openAppSettings();
            },
          );

          if (context.mounted) {
            await context.read<VoiceRecorderCubit>().clearPermissionFeedback();
          }
        },
        child: BlocBuilder<VoiceRecorderCubit, VoiceRecorderState>(
          builder: (context, voiceState) => _ChatPopScope(
            voiceState: voiceState,
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
                      composerHeight: composerHeight,
                      canOpenMessageMenu:
                          voiceState.status != VoiceRecorderStatus.recording,
                      onMessageLongPress: _showMessageActions,
                    ),
                    GradientOverlay(
                      height: headerHeight + 20,
                      isTop: true,
                      backgroundColor: backgroundColor,
                    ),
                    GradientOverlay(
                      height: composerHeight + 20,
                      isTop: false,
                      backgroundColor: backgroundColor,
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ChatAppBar(
                        userName: widget.chat.userName,
                        isOnline: isOnline,
                        lastSeenAt: _lastSeenAt,
                        showsLastSeen:
                            !widget.chat.blockedByPeer &&
                            widget.chat.showsLastSeen,
                        avatarUrl: widget.chat.avatarUrl,
                        avatarLoader: widget.chat.blockedByPeer
                            ? null
                            : () => context
                                  .read<IChatsRepository>()
                                  .resolveAvatar(widget.chat),
                        avatarRevision:
                            widget.chat.avatarStoragePath ??
                            widget.chat.avatarUrl,
                        avatarStoragePath: widget.chat.avatarStoragePath,
                        profileId: widget.chat.peerId,
                        onBack: () {
                          Navigator.of(context).maybePop();
                        },
                        onProfileTap: widget.chat.peerId.isEmpty
                            ? null
                            : () => openViewedProfile(
                                context,
                                userId: widget.chat.peerId,
                                originChatId: widget.chat.id,
                              ),
                      ),
                    ),
                    _KeyboardAwareInput(
                      chatId: widget.chat.id,
                      peerName: widget.chat.userName,
                      peerId: widget.chat.peerId,
                      blockedByMe: blockedByMe,
                      onMessageSent: _scrollToBottom,
                      onHeightChanged: _onComposerHeightChanged,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyboardAwareInput extends StatelessWidget {
  const _KeyboardAwareInput({
    required this.chatId,
    required this.peerName,
    required this.peerId,
    required this.blockedByMe,
    required this.onMessageSent,
    required this.onHeightChanged,
  });

  final String chatId;
  final String peerName;
  final String peerId;
  final bool blockedByMe;
  final VoidCallback onMessageSent;
  final ValueChanged<double> onHeightChanged;

  Future<void> _openAttachmentSheet(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();

    final selection = await showAttachmentBottomSheet(
      context,
      chatId: chatId,
      peerName: peerName,
    );

    if (selection?.imagePaths != null &&
        selection!.imagePaths!.isNotEmpty &&
        context.mounted) {
      context.read<ChatBloc>().add(
        ChatMessageImagesSent(selection.imagePaths!),
      );
      onMessageSent();
      return;
    }

    if (selection?.location != null && context.mounted) {
      context.read<ChatBloc>().add(
        ChatLocationSent(
          latitude: selection!.location!.latitude,
          longitude: selection.location!.longitude,
        ),
      );
      onMessageSent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final systemPadding = MediaQuery.paddingOf(context);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: BlocBuilder<ChatBloc, ChatState>(
          buildWhen: (previous, current) =>
              previous.replyToMessage != current.replyToMessage,
          builder: (context, chatState) {
            if (blockedByMe) {
              return SizeReporter(
                onSizeChanged: (size) => onHeightChanged(size.height),
                child: _UnblockComposer(peerName: peerName, peerId: peerId),
              );
            }
            return BlocBuilder<VoiceRecorderCubit, VoiceRecorderState>(
              builder: (context, state) {
                return SizeReporter(
                  onSizeChanged: (size) => onHeightChanged(size.height),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (chatState.replyToMessage case final reply?) ...[
                        Padding(
                          padding: EdgeInsets.only(
                            left: systemPadding.left + 16,
                            right: systemPadding.right + 16,
                          ),
                          child: ReplyComposerPreview(
                            message: reply,
                            peerName: peerName,
                            onClear: () {
                              context.read<ChatBloc>().add(
                                const ChatReplyCleared(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        reverseDuration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            alignment: Alignment.topCenter,
                            child: child,
                          ),
                        ),
                        child: state.hasPendingRecording
                            ? VoiceRecorderBar(
                                key: const ValueKey('voice_recorder_bar'),
                                state: state,
                                onDiscard: () {
                                  context
                                      .read<VoiceRecorderCubit>()
                                      .discardRecording();
                                },
                                onStop: () {
                                  context
                                      .read<VoiceRecorderCubit>()
                                      .stopRecording();
                                },
                                onTogglePreview: () {
                                  context
                                      .read<VoiceRecorderCubit>()
                                      .togglePreviewPlayback();
                                },
                                onSeekUpdate: (position) {
                                  context
                                      .read<VoiceRecorderCubit>()
                                      .previewSeek(position);
                                },
                                onSeekEnd: () {
                                  context
                                      .read<VoiceRecorderCubit>()
                                      .finishPreviewSeeking();
                                },
                                onSend: () async {
                                  final audio = await context
                                      .read<VoiceRecorderCubit>()
                                      .takeRecordingForSending();
                                  if (audio == null || !context.mounted) return;

                                  context.read<ChatBloc>().add(
                                    ChatMessageAudioSent(
                                      audioPath: audio.path,
                                      duration: audio.duration,
                                      waveform: audio.waveform,
                                    ),
                                  );
                                  onMessageSent();
                                },
                              )
                            : MessageInputBar(
                                key: const ValueKey('message_input_bar'),
                                replyToMessageId: chatState.replyToMessage?.id,
                                onSend: (text) {
                                  context.read<ChatBloc>().add(
                                    ChatMessageSent(text),
                                  );
                                  onMessageSent();
                                },
                                onAddPhoto: () => _openAttachmentSheet(context),
                                onVoiceRecord: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  context
                                      .read<VoiceRecorderCubit>()
                                      .startRecording();
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _UnblockComposer extends StatelessWidget {
  const _UnblockComposer({required this.peerName, required this.peerId});

  final String peerName;
  final String peerId;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left + 16,
        8,
        padding.right + 16,
        padding.bottom + 8,
      ),
      child: Material(
        color: context.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _confirm(context),
          child: SizedBox(
            height: 58,
            child: Center(
              child: Text(
                context.l10n.unblockUser,
                style: TextStyle(
                  color: context.colorScheme.onPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    if (peerId.isEmpty) return;
    final confirmed = await showConfirmationDialog(
      context,
      title: context.l10n.unblockUserTitle,
      content: context.l10n.unblockUserContent(peerName),
      confirmLabel: context.l10n.unblockUser,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<IBlocklistRepository>().unblockUser(peerId);
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsActionFailed,
          type: SnackBarType.error,
        );
      }
    }
  }
}

class _ChatPopScope extends StatelessWidget {
  const _ChatPopScope({required this.child, required this.voiceState});

  final Widget child;
  final VoiceRecorderState voiceState;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: !isKeyboardOpen && !voiceState.hasPendingRecording,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (isKeyboardOpen) {
          FocusManager.instance.primaryFocus?.unfocus();
          return;
        }

        if (!voiceState.hasPendingRecording) return;

        final shouldDiscard = await showConfirmationDialog(
          context,
          title: context.l10n.voiceRecordingExitTitle,
          content: context.l10n.voiceRecordingExitDescription,
          confirmLabel: context.l10n.voiceRecordingExitDiscard,
        );
        if (shouldDiscard == true && context.mounted) {
          await context.read<VoiceRecorderCubit>().discardRecording();
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
    required this.composerHeight,
    required this.canOpenMessageMenu,
    required this.onMessageLongPress,
  });

  final ScrollController controller;
  final Chat chat;
  final double headerHeight;
  final double composerHeight;
  final bool canOpenMessageMenu;
  final ValueChanged<ChatMessage> onMessageLongPress;

  @override
  State<_ChatMessages> createState() => _ChatMessagesState();
}

class _ChatMessagesState extends State<_ChatMessages> {
  bool _showScrollToBottom = false;
  int _newMessagesCount = 0;

  Set<String> _knownMessageIds = {};
  bool _initialMessagesLoaded = false;
  DateTime? _latestKnownTimestamp;

  // Для отслеживания направления скролла
  double _lastOffset = 0.0;
  bool _isAnimatingToBottom = false;
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, int> _messageIndexes = {};
  String? _highlightedMessageId;

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
    if (offset >= widget.controller.position.maxScrollExtent - 320) {
      context.read<ChatBloc>().add(const ChatOlderMessagesRequested());
    }
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
      _latestKnownTimestamp = messages.firstOrNull?.timestamp;
      _initialMessagesLoaded = true;
      return;
    }

    final previousLatestTimestamp = _latestKnownTimestamp;
    final newMessages = messages
        .where(
          (message) =>
              !_knownMessageIds.contains(message.id) &&
              (previousLatestTimestamp == null ||
                  !message.timestamp.isBefore(previousLatestTimestamp)),
        )
        .toList();

    _knownMessageIds = currentIds;
    _latestKnownTimestamp = messages.firstOrNull?.timestamp;

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

  GlobalKey _messageKey(String messageId) {
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  Future<void> _jumpToMessage(String messageId) async {
    if (_messageKeys[messageId]?.currentContext == null &&
        widget.controller.hasClients) {
      final messageIndex = _messageIndexes[messageId];
      if (messageIndex != null) {
        final targetOffset = (messageIndex * 120.0)
            .clamp(0.0, widget.controller.position.maxScrollExtent)
            .toDouble();
        await widget.controller.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }

    await _ensureMessageVisible(messageId);
    if (!mounted) return;

    setState(() => _highlightedMessageId = messageId);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted && _highlightedMessageId == messageId) {
      setState(() => _highlightedMessageId = null);
    }
  }

  Future<void> _ensureMessageVisible(String messageId) {
    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null) return Future<void>.value();

    return Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
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
              previous.initialMessageIds != current.initialMessageIds ||
              previous.replyToMessage != current.replyToMessage;
        },
        builder: (context, state) {
          _messageIndexes.clear();
          for (var index = 0; index < state.messages.length; index++) {
            _messageIndexes[state.messages[index].id] = index;
          }
          if (state.status == ChatStatus.loading) {
            return Center(
              child: CircularProgressIndicator(
                color: context.colorScheme.primary,
              ),
            );
          }

          if (state.messages.isEmpty) {
            return AnimatedPadding(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutQuad,
              padding: EdgeInsets.only(
                top: widget.headerHeight + 12,
                bottom:
                    widget.composerHeight +
                    MediaQuery.viewInsetsOf(context).bottom +
                    12,
              ),
              child: EmptyChatState(message: context.l10n.noMessages),
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
                composerHeight: widget.composerHeight,
                messageKeyBuilder: _messageKey,
                highlightedMessageId: _highlightedMessageId,
                onReplyTap: _jumpToMessage,
                onMessageLongPress: widget.canOpenMessageMenu
                    ? widget.onMessageLongPress
                    : null,
              ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                right: 16 + MediaQuery.paddingOf(context).right,
                bottom:
                    widget.composerHeight +
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
    required this.composerHeight,
    required this.messageKeyBuilder,
    required this.highlightedMessageId,
    required this.onReplyTap,
    this.onMessageLongPress,
  });

  final ScrollController controller;
  final Chat chat;
  final List<ChatMessage> messages;
  final Set<String> initialMessageIds;

  final double headerHeight;
  final double composerHeight;
  final GlobalKey Function(String messageId) messageKeyBuilder;
  final String? highlightedMessageId;
  final ValueChanged<String> onReplyTap;
  final ValueChanged<ChatMessage>? onMessageLongPress;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final systemPadding = MediaQuery.paddingOf(context);

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

    final bottomPadding = composerHeight + keyboardHeight + 12.0;

    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: EdgeInsets.only(top: headerHeight + 12.0, bottom: bottomPadding),

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

        final isHighlighted =
            item is MessageItemElement &&
            highlightedMessageId == item.message.id;

        return AnimatedContainer(
          key: item is MessageItemElement
              ? messageKeyBuilder(item.message.id)
              : key,
          duration: const Duration(milliseconds: 180),
          color: isHighlighted
              ? context.colorScheme.primary.withValues(alpha: 0.42)
              : Colors.transparent,
          padding: EdgeInsets.only(
            left: systemPadding.left + 16,
            right: systemPadding.right + 16,
            top: 4,
            bottom: 4,
          ),
          child: switch (item) {
            MessageItemElement(:final message) => MessageBubble(
              message: message,
              isNew: !initialMessageIds.contains(message.id),
              maxWidth: screenWidth * 0.8,
              peerName: chat.userName,
              peerAvatarUrl: chat.avatarUrl,
              peerAvatarLoader: () =>
                  context.read<IChatsRepository>().resolveAvatar(chat),
              onLongPress: onMessageLongPress,
              onReplyTap: message.replyTo == null
                  ? null
                  : () => onReplyTap(message.replyTo!.messageId),
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

        Positioned(
          top: -5,
          right: -5,
          child: AnimatedUnreadBadge(
            count: newMessagesCount,
            color: context.colorScheme.primary,
            textColor: context.scaffoldBackgroundColor,
            size: 22,
            borderColor: context.scaffoldBackgroundColor,
            borderWidth: 1.5,
          ),
        ),
      ],
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
