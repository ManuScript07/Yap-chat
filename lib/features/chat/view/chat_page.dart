import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/view/focused_history_window_cache.dart';
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
    with AutoRouteAwareStateMixin<_ChatView> {
  final GlobalKey<_ChatMessagesState> _messagesKey =
      GlobalKey<_ChatMessagesState>();
  NotificationsCubit? _notificationsCubit;
  late DateTime? _lastSeenAt;
  double? _composerContentHeight;

  @override
  void initState() {
    super.initState();
    _lastSeenAt = widget.chat.lastSeenAt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLostAttachment();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    if (!widget.chat.isDraft) {
      unawaited(_notificationsCubit?.clearActiveConversation(widget.chat.id));
    }
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messagesKey.currentState?.scrollToBottom();
    });
  }

  void _onComposerHeightChanged(double height) {
    final contentHeight = math.max(
      0.0,
      height - MediaQuery.viewPaddingOf(context).bottom,
    );
    if ((_composerContentHeight == null
                ? contentHeight
                : _composerContentHeight! - contentHeight)
            .abs() <
        0.5) {
      return;
    }
    setState(() => _composerContentHeight = contentHeight);
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

    // `padding.bottom` is reduced while Android replaces the navigation-bar
    // inset with the IME inset.  The composer itself must keep a stable height
    // throughout that hand-off; otherwise its bottom part is briefly covered
    // by the keyboard.
    final persistentBottomInset = mediaQuery.viewPadding.bottom;
    final keyboardAvoidanceOffset = math.max(
      0.0,
      mediaQuery.viewInsets.bottom - persistentBottomInset,
    );
    final composerHeight =
        (_composerContentHeight ?? inputContentHeight) + persistentBottomInset;

    final headerHeight = 64.0 + topSafeArea;

    final backgroundColor = context.scaffoldBackgroundColor;
    final presence = context.watch<PresenceCubit>().state;
    final isOnline =
        widget.chat.blockedByPeer ||
            widget.chat.peerIsGloballyBanned ||
            widget.chat.peerIsDeleted
        ? false
        : widget.chat.peerId.isEmpty
        ? widget.chat.isOnline
        : presence.isOnline(widget.chat.peerId);
    final blocklistState = context.watch<BlocklistCubit>().state;
    final blockedByMe =
        widget.chat.peerId.isNotEmpty &&
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
              // The stack owns IME avoidance.  This keeps the keyboard offset
              // and the stable SafeArea height in the same coordinate system.
              // Letting Scaffold resize this route as well reintroduces the
              // transient, partially covered composer on Android.
              resizeToAvoidBottomInset: false,
              body: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _ChatMessages(
                        key: _messagesKey,
                        chat: widget.chat,
                        headerHeight: headerHeight,
                        composerHeight: composerHeight,
                        keyboardAvoidanceOffset: keyboardAvoidanceOffset,
                        canOpenMessageMenu:
                            voiceState.status != VoiceRecorderStatus.recording,
                        onMessageLongPress: _showMessageActions,
                      ),
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
                      bottomOffset: keyboardAvoidanceOffset,
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
                            !widget.chat.peerIsGloballyBanned &&
                            !widget.chat.peerIsDeleted &&
                            widget.chat.showsLastSeen,
                        avatarUrl: widget.chat.avatarUrl,
                        avatarLoader:
                            widget.chat.blockedByPeer ||
                                widget.chat.peerIsGloballyBanned ||
                                widget.chat.peerIsDeleted
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
                        onProfileTap:
                            widget.chat.peerId.isEmpty ||
                                widget.chat.peerIsDeleted
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
                      peerIsGloballyBanned: widget.chat.peerIsGloballyBanned,
                      peerIsDeleted: widget.chat.peerIsDeleted,
                      isBlockActionPending: blocklistState.isPending(
                        widget.chat.peerId,
                      ),
                      keyboardAvoidanceOffset: keyboardAvoidanceOffset,
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
    required this.peerIsGloballyBanned,
    required this.peerIsDeleted,
    required this.isBlockActionPending,
    required this.keyboardAvoidanceOffset,
    required this.onMessageSent,
    required this.onHeightChanged,
  });

  final String chatId;
  final String peerName;
  final String peerId;
  final bool blockedByMe;
  final bool peerIsGloballyBanned;
  final bool peerIsDeleted;
  final bool isBlockActionPending;
  final double keyboardAvoidanceOffset;
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
    final systemPadding = MediaQuery.viewPaddingOf(context);
    final composerMediaQuery = MediaQuery.of(
      context,
    ).copyWith(viewInsets: EdgeInsets.zero);

    return Positioned(
      left: 0,
      right: 0,
      bottom: keyboardAvoidanceOffset,
      child: MediaQuery(
        data: composerMediaQuery,
        child: BlocBuilder<ChatBloc, ChatState>(
          buildWhen: (previous, current) =>
              previous.replyToMessage != current.replyToMessage,
          builder: (context, chatState) {
            if (peerIsGloballyBanned) {
              return SizeReporter(
                onSizeChanged: (size) => onHeightChanged(size.height),
                child: const _GloballyBannedComposer(),
              );
            }
            if (peerIsDeleted) {
              return SizeReporter(
                onSizeChanged: (size) => onHeightChanged(size.height),
                child: _DeletedAccountComposer(chatId: chatId),
              );
            }
            if (blockedByMe) {
              return SizeReporter(
                onSizeChanged: (size) => onHeightChanged(size.height),
                child: _UnblockComposer(
                  peerName: peerName,
                  peerId: peerId,
                  isPending: isBlockActionPending,
                ),
              );
            }
            return BlocBuilder<VoiceRecorderCubit, VoiceRecorderState>(
              builder: (context, state) {
                return SizeReporter(
                  onSizeChanged: (size) => onHeightChanged(size.height),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        reverseDuration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            axisAlignment: -1,
                            child: child,
                          ),
                        ),
                        child: switch (chatState.replyToMessage) {
                          final reply? => Padding(
                            key: ValueKey('reply_${reply.id}'),
                            padding: EdgeInsets.only(
                              left: systemPadding.left + 16,
                              right: systemPadding.right + 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ReplyComposerPreview(
                                  message: reply,
                                  peerName: peerName,
                                  onClear: () {
                                    context.read<ChatBloc>().add(
                                      const ChatReplyCleared(),
                                    );
                                  },
                                ),
                                const SizedBox(height: 4),
                              ],
                            ),
                          ),
                          null => const SizedBox(key: ValueKey('reply_empty')),
                        },
                      ),
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
  const _UnblockComposer({
    required this.peerName,
    required this.peerId,
    required this.isPending,
  });

  final String peerName;
  final String peerId;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final mainColor = context.colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left + 16,
        8,
        padding.right + 16,
        padding.bottom + 8,
      ),
      child: SizedBox(
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: mainColor.withValues(alpha: .4),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(32),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                color: mainColor.withValues(alpha: .15),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(32),
                    onTap: isPending ? null : () => _confirm(context),
                    child: Center(
                      child: isPending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: mainColor,
                              ),
                            )
                          : Text(
                              context.l10n.unblockUser.toLowerCase(),
                              style: TextStyle(
                                color: mainColor.withValues(alpha: .6),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .15,
                              ),
                            ),
                    ),
                  ),
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

/// A global account ban is administered outside the chat.  Keeping this
/// visually identical to the personal-unblock composer avoids a jarring
/// layout jump, while intentionally exposing no action to the viewer.
class _DeletedAccountComposer extends StatefulWidget {
  const _DeletedAccountComposer({required this.chatId});

  final String chatId;

  @override
  State<_DeletedAccountComposer> createState() =>
      _DeletedAccountComposerState();
}

class _DeletedAccountComposerState extends State<_DeletedAccountComposer> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final mainColor = context.colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left + 16,
        8,
        padding.right + 16,
        padding.bottom + 8,
      ),
      child: SizedBox(
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: mainColor.withValues(alpha: .4),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(32),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Material(
                color: mainColor.withValues(alpha: .15),
                child: InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: _isDeleting ? null : _confirmDeletion,
                  child: Center(
                    child: _isDeleting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: mainColor,
                            ),
                          )
                        : Text(
                            context.l10n.chatsDeleteAccountChat,
                            style: TextStyle(
                              color: mainColor.withValues(alpha: .6),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .15,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeletion() async {
    final confirmed = await showConfirmationDialog(
      context,
      title: context.l10n.chatsDeleteTitle(1),
      content: context.l10n.chatsDeleteConfirmation(1),
      confirmLabel: context.l10n.chatsDeleteAccountChat,
    );
    if (!mounted || confirmed != true) return;
    setState(() => _isDeleting = true);
    try {
      await context.read<IChatsRepository>().deleteChats({widget.chatId});
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) setState(() => _isDeleting = false);
    }
  }
}

/// A global account ban is administered outside the chat.  Keeping this
/// visually identical to the personal-unblock composer avoids a jarring
/// layout jump, while intentionally exposing no action to the viewer.
class _GloballyBannedComposer extends StatelessWidget {
  const _GloballyBannedComposer();

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final mainColor = context.colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left + 16,
        8,
        padding.right + 16,
        padding.bottom + 8,
      ),
      child: SizedBox(
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: mainColor.withValues(alpha: .4),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(32),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                color: mainColor.withValues(alpha: .15),
                child: Center(
                  child: Text(
                    context.l10n.chatUserBlocked.toLowerCase(),
                    style: TextStyle(
                      color: mainColor.withValues(alpha: .6),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    super.key,
    required this.chat,
    required this.headerHeight,
    required this.composerHeight,
    required this.keyboardAvoidanceOffset,
    required this.canOpenMessageMenu,
    required this.onMessageLongPress,
  });

  final Chat chat;
  final double headerHeight;
  final double composerHeight;
  final double keyboardAvoidanceOffset;
  final bool canOpenMessageMenu;
  final ValueChanged<ChatMessage> onMessageLongPress;

  @override
  State<_ChatMessages> createState() => _ChatMessagesState();
}

class _ChatMessagesState extends State<_ChatMessages> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _showScrollToBottom = false;
  int _newMessagesCount = 0;

  Set<String> _knownMessageIds = {};
  bool _initialMessagesLoaded = false;
  DateTime? _latestKnownTimestamp;
  final Map<String, DateTime> _newMessageAnimations = {};
  bool _bottomJumpScheduled = false;
  bool _bottomJumpPending = false;
  int _bottomJumpSerial = 0;

  int _lastVisibleIndex = 0;
  bool _isAnimatingToBottom = false;
  bool _isNavigating = false;
  bool _focusLoading = false;
  bool _focusRecheckPending = false;
  bool _focusPageLoading = false;
  bool _focusHasOlder = true;
  bool _focusHasNewer = true;
  bool _focusPaginationArmed = false;
  int _navigationGeneration = 0;
  List<ChatMessage>? _focusMessages;
  List<ChatListItemElement> _displayedItems = const [];
  String? _highlightedMessageId;
  StreamSubscription<ChatHistoryChange>? _historyChangesSubscription;
  final Map<String, Future<ChatMessage>> _focusedMedia = {};
  final Set<String> _deletedFocusIds = {};
  final FocusedHistoryWindowCache _windowCache = FocusedHistoryWindowCache();

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_handleScroll);
    _listenToHistoryChanges();
  }

  void _listenToHistoryChanges() {
    final chatId = widget.chat.id;
    _historyChangesSubscription = context
        .read<IChatRepository>()
        .watchHistoryChanges(chatId)
        .listen((change) {
          if (!mounted || widget.chat.id != chatId) return;
          final deletedId = change.deletedMessageId;
          if (deletedId != null) {
            _removeFocusedMessage(deletedId);
          } else if (change.reconnected) {
            _windowCache.clear();
            if (_focusLoading) {
              _focusRecheckPending = true;
            } else if (_focusMessages != null) {
              unawaited(_refreshFocusedWindow());
            }
          }
        });
  }

  void _removeFocusedMessage(String messageId) {
    _windowCache.clear();
    _deletedFocusIds.add(messageId);
    final current = _focusMessages;
    if (current == null) return;
    _focusedMedia.remove(messageId);
    if (!current.any(
      (message) =>
          message.id == messageId || message.replyTo?.messageId == messageId,
    )) {
      return;
    }
    for (final message in current) {
      if (message.replyTo?.messageId == messageId) {
        _focusedMedia.remove(message.id);
      }
    }
    final remaining = current
        .where((message) => message.id != messageId)
        .map(
          (message) => message.replyTo?.messageId == messageId
              ? message.copyWith(clearReplyTo: true)
              : message,
        )
        .toList(growable: false);
    if (remaining.isEmpty) {
      scrollToBottom(animate: false);
      return;
    }
    setState(() {
      _focusMessages = remaining;
      if (_highlightedMessageId == messageId) {
        _highlightedMessageId = null;
      }
    });
  }

  Future<void> _refreshFocusedWindow() async {
    if (_focusMessages == null || _focusLoading) return;
    final visible =
        _itemPositionsListener.itemPositions.value
            .where(
              (position) =>
                  position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
            )
            .toList(growable: false)
          ..sort((a, b) => a.index.compareTo(b.index));
    String? anchorId;
    for (final position in visible) {
      if (position.index >= _displayedItems.length) continue;
      final item = _displayedItems[position.index];
      if (item is MessageItemElement &&
          _focusMessages!.any((message) => message.id == item.message.id)) {
        anchorId = item.message.id;
        break;
      }
    }
    anchorId ??= _focusMessages!.firstOrNull?.id;
    if (anchorId == null) return;
    final generation = ++_navigationGeneration;
    setState(() => _focusLoading = true);
    try {
      final window = await context.read<IChatRepository>().loadMessageWindow(
        widget.chat.id,
        anchorId,
      );
      if (!mounted || generation != _navigationGeneration) return;
      final current = window
          .where((message) => !_deletedFocusIds.contains(message.id))
          .toList(growable: false);
      if (!current.any((message) => message.id == anchorId)) {
        scrollToBottom();
        return;
      }
      _focusedMedia.clear();
      _windowCache.remember(anchorId, current);
      setState(() {
        _focusMessages = current;
        _focusHasOlder = true;
        _focusHasNewer = true;
        _focusPaginationArmed = false;
        _showScrollToBottom = false;
        _focusPageLoading = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      await _showMessage(anchorId, generation: generation, animate: false);
    } catch (_) {
      // Keep the current window if reconnection happened before the API works.
    } finally {
      if (mounted && generation == _navigationGeneration) {
        setState(() => _focusLoading = false);
        _runPendingFocusRecheck();
      }
    }
  }

  void _runPendingFocusRecheck() {
    if (!_focusRecheckPending || _focusMessages == null) return;
    _focusRecheckPending = false;
    unawaited(_refreshFocusedWindow());
  }

  Future<ChatMessage> _hydrateFocusedMedia(ChatMessage message) =>
      _focusedMedia.putIfAbsent(message.id, () async {
        try {
          return await context.read<IChatRepository>().hydrateWindowMedia(
            message,
          );
        } catch (_) {
          _focusedMedia.remove(message.id);
          rethrow;
        }
      });

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_handleScroll);
    final subscription = _historyChangesSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChatMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat.id != widget.chat.id) {
      final subscription = _historyChangesSubscription;
      if (subscription != null) unawaited(subscription.cancel());
      _listenToHistoryChanges();
      _navigationGeneration++;
      _focusMessages = null;
      _focusedMedia.clear();
      _windowCache.clear();
      _deletedFocusIds.clear();
      _focusLoading = false;
      _focusRecheckPending = false;
      _focusPageLoading = false;
      _focusPaginationArmed = false;
      _highlightedMessageId = null;
      _knownMessageIds = {};
      _initialMessagesLoaded = false;
      _newMessageAnimations.clear();
      _lastVisibleIndex = 0;
    }
  }

  void _handleScroll() {
    if (_isAnimatingToBottom || _isNavigating || _bottomJumpPending) return;
    final visible = _itemPositionsListener.itemPositions.value
        .where(
          (position) =>
              position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
        )
        .toList(growable: false);
    if (visible.isEmpty || _displayedItems.isEmpty) return;
    final first = visible.map((position) => position.index).reduce(math.min);
    final last = visible.map((position) => position.index).reduce(math.max);

    if (last >= _displayedItems.length - 4) {
      if (_focusMessages == null) {
        context.read<ChatBloc>().add(const ChatOlderMessagesRequested());
      } else if (_focusPaginationArmed) {
        unawaited(_loadFocusOlder());
      }
    }
    if (_focusMessages != null) {
      if (_focusPaginationArmed && first <= 3) {
        unawaited(_loadFocusNewer());
      }
      if (_focusPaginationArmed &&
          _isFocusedWindowAtBottom &&
          !_focusHasNewer &&
          !_focusPageLoading) {
        scrollToBottom(animate: false);
        return;
      }
      _lastVisibleIndex = first;
      return;
    }

    if (first == 0) {
      if (_showScrollToBottom || _newMessagesCount != 0) {
        setState(() {
          _showScrollToBottom = false;
          _newMessagesCount = 0;
        });
      }
      _lastVisibleIndex = first;
      return;
    }

    if (first > _lastVisibleIndex) {
      if (_showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
    } else if (first < _lastVisibleIndex) {
      if (!_showScrollToBottom) {
        setState(() => _showScrollToBottom = true);
      }
    }
    _lastVisibleIndex = first;
  }

  void _handleMessagesChanged(List<ChatMessage> messages) {
    final currentIds = messages.map((message) => message.id).toSet();

    // An empty cache can be emitted before the first server page arrives.
    // Treat that first populated page as history, not as new animations.
    if (!_initialMessagesLoaded || _knownMessageIds.isEmpty) {
      _knownMessageIds = currentIds;
      _latestKnownTimestamp = messages.firstOrNull?.timestamp;
      _initialMessagesLoaded = messages.isNotEmpty;
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

    if (_focusMessages != null) {
      final incomingCount = newMessages
          .where((message) => !message.isMine)
          .length;
      if (incomingCount > 0) {
        setState(() {
          _showScrollToBottom = true;
          _newMessagesCount += incomingCount;
        });
      }
      return;
    }

    final now = DateTime.now();
    _newMessageAnimations.removeWhere(
      (_, started) =>
          now.difference(started) >= const Duration(milliseconds: 250),
    );
    for (final message in newMessages) {
      _newMessageAnimations[message.id] = now;
    }

    final hasMine = newMessages.any((m) => m.isMine);
    final isAtBottom = _lastVisibleIndex == 0;

    if (hasMine) {
      _jumpToBottomAfterBuild();
    } else if (!isAtBottom) {
      // Пришло чужое сообщение, а мы находимся высоко в истории.
      // ВСЕГДА показываем кнопку и увеличиваем счетчик.
      setState(() {
        _showScrollToBottom = true;
        _newMessagesCount += newMessages.length;
      });
    } else {
      _jumpToBottomAfterBuild();
    }
  }

  double _animationProgressFor(String messageId) {
    final started = _newMessageAnimations[messageId];
    if (started == null) return 1;
    final elapsed = DateTime.now().difference(started).inMicroseconds;
    return (elapsed / const Duration(milliseconds: 250).inMicroseconds).clamp(
      0.0,
      1.0,
    );
  }

  void _jumpToBottomAfterBuild() {
    if (_bottomJumpScheduled) return;
    _bottomJumpScheduled = true;
    _bottomJumpPending = true;
    final serial = ++_bottomJumpSerial;
    final generation = _navigationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomJumpScheduled = false;
      if (mounted &&
          generation == _navigationGeneration &&
          _focusMessages == null &&
          _itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: 0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (serial != _bottomJumpSerial) return;
        _bottomJumpPending = false;
        if (!mounted ||
            generation != _navigationGeneration ||
            _focusMessages != null) {
          return;
        }
        _lastVisibleIndex = 0;
        if (_showScrollToBottom || _newMessagesCount != 0) {
          setState(() {
            _showScrollToBottom = false;
            _newMessagesCount = 0;
          });
        }
      });
    });
  }

  void scrollToBottom({bool animate = true}) {
    final generation = ++_navigationGeneration;
    final wasFocused = _focusMessages != null;
    if (wasFocused) {
      // The focused window can be many pages away from the recent timeline.
      // Animating to its own index zero and then replacing the list causes a
      // second, visible jump (and can briefly display an empty viewport).
      _leaveFocusedWindow();
      return;
    }
    if (_newMessagesCount != 0 ||
        _showScrollToBottom ||
        _focusLoading ||
        _focusPageLoading) {
      setState(() {
        _newMessagesCount = 0;
        _showScrollToBottom = false;
        _focusLoading = false;
        _focusPageLoading = false;
      });
    }
    if (!_itemScrollController.isAttached) return;
    _isAnimatingToBottom = true;
    _itemScrollController
        .scrollTo(
          index: 0,
          alignment: _bottomAlignment,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (mounted && generation == _navigationGeneration) {
            _isAnimatingToBottom = false;
            _lastVisibleIndex = 0;
          }
        });
  }

  double get _bottomAlignment {
    final height = context.size?.height ?? MediaQuery.sizeOf(context).height;
    if (height <= 0) return 0;
    final bottomPadding =
        widget.composerHeight + widget.keyboardAvoidanceOffset + 12;
    return (bottomPadding / height).clamp(0.0, 1.0);
  }

  bool get _isFocusedWindowAtBottom =>
      _itemPositionsListener.itemPositions.value.any(
        (position) =>
            position.index == 0 &&
            position.itemTrailingEdge > 0 &&
            position.itemLeadingEdge <= _bottomAlignment + 0.02,
      );

  void _leaveFocusedWindow() {
    _isAnimatingToBottom = false;
    _isNavigating = false;
    _focusedMedia.clear();
    _deletedFocusIds.clear();
    _focusRecheckPending = false;
    setState(() {
      _focusMessages = null;
      _focusPaginationArmed = false;
      _highlightedMessageId = null;
      _newMessagesCount = 0;
      _showScrollToBottom = false;
      _focusLoading = false;
      _focusPageLoading = false;
      _lastVisibleIndex = 0;
    });
    _jumpToBottomAfterBuild();
  }

  int? _indexForMessage(String messageId) {
    for (var i = 0; i < _displayedItems.length; i++) {
      final item = _displayedItems[i];
      if (item is MessageItemElement && item.message.id == messageId) return i;
    }
    return null;
  }

  Future<void> _jumpToMessage(String messageId) async {
    if (_focusLoading) return;
    final generation = ++_navigationGeneration;
    _isAnimatingToBottom = false;
    final recentMessages = context.read<ChatBloc>().state.messages;
    if (_focusMessages?.any((message) => message.id == messageId) == true) {
      setState(() {
        _focusPaginationArmed = false;
        _showScrollToBottom = false;
      });
      await _showMessage(messageId, generation: generation);
      return;
    }
    if (recentMessages.any((message) => message.id == messageId)) {
      _focusedMedia.clear();
      _deletedFocusIds.clear();
      setState(() {
        _focusMessages = null;
        _focusPaginationArmed = false;
        _showScrollToBottom = false;
        _newMessagesCount = 0;
        _focusPageLoading = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      await _showMessage(messageId, generation: generation);
      return;
    }

    _deletedFocusIds.clear();
    final cachedWindow = _windowCache.find(messageId);
    if (cachedWindow == null) setState(() => _focusLoading = true);
    try {
      final window =
          cachedWindow ??
          await context.read<IChatRepository>().loadMessageWindow(
            widget.chat.id,
            messageId,
          );
      if (!mounted || generation != _navigationGeneration) return;
      final visibleWindow = window
          .where((message) => !_deletedFocusIds.contains(message.id))
          .toList(growable: false);
      if (!visibleWindow.any((message) => message.id == messageId)) {
        showAppSnackBar(context, message: context.l10n.messageNotAvailable);
        return;
      }
      if (cachedWindow == null) {
        _windowCache.remember(messageId, visibleWindow);
      }
      _focusedMedia.clear();
      setState(() {
        _focusMessages = visibleWindow;
        _focusHasOlder = true;
        _focusHasNewer = true;
        _focusPaginationArmed = false;
        _focusPageLoading = false;
        _newMessagesCount = 0;
        _showScrollToBottom = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      await _showMessage(messageId, generation: generation, animate: false);
    } catch (_) {
      if (mounted && generation == _navigationGeneration) {
        showAppSnackBar(
          context,
          message: context.l10n.messageJumpFailed,
          type: SnackBarType.error,
        );
      }
    } finally {
      if (cachedWindow == null &&
          mounted &&
          generation == _navigationGeneration) {
        setState(() => _focusLoading = false);
        _runPendingFocusRecheck();
      }
    }
  }

  Future<void> _showMessage(
    String messageId, {
    required int generation,
    bool animate = true,
  }) async {
    if (!mounted || generation != _navigationGeneration) return;
    final index = _indexForMessage(messageId);
    if (index == null || !_itemScrollController.isAttached) return;
    _isNavigating = true;
    try {
      if (animate) {
        await _itemScrollController.scrollTo(
          index: index,
          alignment: 0.5,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      } else {
        _itemScrollController.jumpTo(index: index, alignment: 0.5);
      }
    } finally {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && generation == _navigationGeneration) {
        _isNavigating = false;
      }
    }
    if (!mounted || generation != _navigationGeneration) return;
    final visibleIndices = _itemPositionsListener.itemPositions.value
        .where(
          (position) =>
              position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
        )
        .map((position) => position.index);
    _lastVisibleIndex = visibleIndices.isEmpty
        ? index
        : visibleIndices.reduce(math.min);
    setState(() => _highlightedMessageId = messageId);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted &&
          generation == _navigationGeneration &&
          _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<void> _loadFocusOlder() async {
    final messages = _focusMessages;
    if (messages == null ||
        messages.isEmpty ||
        _focusPageLoading ||
        !_focusHasOlder) {
      return;
    }
    _focusPageLoading = true;
    final generation = _navigationGeneration;
    try {
      final page = await context.read<IChatRepository>().loadWindowOlder(
        widget.chat.id,
        messages.last,
      );
      if (!mounted ||
          generation != _navigationGeneration ||
          _focusMessages == null) {
        return;
      }
      final existing = _focusMessages!.map((message) => message.id).toSet();
      setState(() {
        _focusMessages = [
          ..._focusMessages!,
          ...page.where(
            (message) =>
                !existing.contains(message.id) &&
                !_deletedFocusIds.contains(message.id),
          ),
        ];
        _focusHasOlder = page.length == 60;
      });
    } catch (_) {
      // Keep the cursor intact: the next scroll can retry the same page.
    } finally {
      if (generation == _navigationGeneration) _focusPageLoading = false;
    }
  }

  Future<void> _loadFocusNewer() async {
    final messages = _focusMessages;
    if (messages == null ||
        messages.isEmpty ||
        _focusPageLoading ||
        !_focusHasNewer) {
      return;
    }
    _focusPageLoading = true;
    final generation = _navigationGeneration;
    final visible =
        _itemPositionsListener.itemPositions.value
            .where(
              (position) =>
                  position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
            )
            .toList(growable: false)
          ..sort((a, b) => a.index.compareTo(b.index));
    final anchor = visible.firstOrNull;
    final anchorItem = anchor == null || anchor.index >= _displayedItems.length
        ? null
        : _displayedItems[anchor.index];
    final anchorId = anchorItem is MessageItemElement
        ? anchorItem.message.id
        : null;
    try {
      final page = await context.read<IChatRepository>().loadWindowNewer(
        widget.chat.id,
        messages.first,
      );
      if (!mounted ||
          generation != _navigationGeneration ||
          _focusMessages == null) {
        return;
      }
      final existing = _focusMessages!.map((message) => message.id).toSet();
      setState(() {
        _focusMessages = [
          ...page.where(
            (message) =>
                !existing.contains(message.id) &&
                !_deletedFocusIds.contains(message.id),
          ),
          ..._focusMessages!,
        ];
        _focusHasNewer = page.length == 60;
      });
      if (page.isNotEmpty && anchorId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              generation != _navigationGeneration ||
              !_itemScrollController.isAttached) {
            return;
          }
          final index = _indexForMessage(anchorId);
          if (index != null) {
            _itemScrollController.jumpTo(
              index: index,
              alignment: anchor!.itemLeadingEdge.clamp(0.0, 1.0),
            );
          }
        });
      }
      if (!_focusHasNewer && page.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _navigationGeneration) return;
          if (_isFocusedWindowAtBottom) scrollToBottom(animate: false);
        });
      }
    } catch (_) {
      // Keep the cursor intact: the next scroll can retry the same page.
    } finally {
      if (generation == _navigationGeneration) _focusPageLoading = false;
    }
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
          if (state.status == ChatStatus.loading && _focusMessages == null) {
            return Center(
              child: CircularProgressIndicator(
                color: context.colorScheme.primary,
              ),
            );
          }

          if (state.messages.isEmpty && _focusMessages == null) {
            return AnimatedPadding(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutQuad,
              padding: EdgeInsets.only(
                top: widget.headerHeight + 12,
                bottom:
                    widget.composerHeight + widget.keyboardAvoidanceOffset + 12,
              ),
              child: EmptyChatState(message: context.l10n.noMessages),
            );
          }

          // Отрезаем новые сообщения из отрисовки, пока не проскроллим вниз,
          // чтобы интерфейс не дергался
          List<ChatMessage> displayedMessages =
              _focusMessages ?? state.messages;
          if (_focusMessages == null &&
              _newMessagesCount > 0 &&
              state.messages.length >= _newMessagesCount) {
            displayedMessages = state.messages.skip(_newMessagesCount).toList();
          }
          _displayedItems = _buildChatTimelineItems(displayedMessages);
          return Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (_focusMessages == null ||
                      notification.metrics.axis != Axis.vertical ||
                      notification.depth != 0) {
                    return false;
                  }
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _focusPaginationArmed = true;
                  } else if (notification is ScrollUpdateNotification &&
                      notification.dragDetails != null &&
                      (notification.scrollDelta ?? 0) < 0 &&
                      !_showScrollToBottom) {
                    _focusPaginationArmed = true;
                    final generation = _navigationGeneration;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted &&
                          generation == _navigationGeneration &&
                          _focusMessages != null &&
                          !_showScrollToBottom) {
                        setState(() => _showScrollToBottom = true);
                      }
                    });
                  }
                  return false;
                },
                child: _MessagesList(
                  key: ValueKey(
                    _focusMessages == null
                        ? 'recent_messages'
                        : 'focus_messages',
                  ),
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  chat: widget.chat,
                  items: _displayedItems,
                  animationProgressFor: _animationProgressFor,
                  headerHeight: widget.headerHeight,
                  bottomPadding:
                      widget.composerHeight +
                      widget.keyboardAvoidanceOffset +
                      12,
                  highlightedMessageId: _highlightedMessageId,
                  hydrateFocusedMedia: _focusMessages == null
                      ? null
                      : _hydrateFocusedMedia,
                  retryFocusedMedia: () => setState(() {}),
                  onReplyTap: _jumpToMessage,
                  onMessageLongPress: widget.canOpenMessageMenu
                      ? widget.onMessageLongPress
                      : null,
                ),
              ),

              if (_focusLoading)
                Positioned.fill(
                  child: ColoredBox(
                    color: context.scaffoldBackgroundColor.withValues(
                      alpha: 0.25,
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: context.colorScheme.primary,
                      ),
                    ),
                  ),
                ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                right: 16 + MediaQuery.paddingOf(context).right,
                bottom:
                    widget.composerHeight + widget.keyboardAvoidanceOffset + 20,
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
                          onPressed: scrollToBottom,
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

List<ChatListItemElement> _buildChatTimelineItems(List<ChatMessage> messages) {
  final items = <ChatListItemElement>[];
  for (var index = 0; index < messages.length; index++) {
    final message = messages[index];
    items.add(MessageItemElement(message));
    final next = index + 1 < messages.length ? messages[index + 1] : null;
    if (next == null ||
        message.timestamp.year != next.timestamp.year ||
        message.timestamp.month != next.timestamp.month ||
        message.timestamp.day != next.timestamp.day) {
      items.add(DateSeparatorElement(message.timestamp));
    }
  }
  return items;
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({
    super.key,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.chat,
    required this.items,
    required this.animationProgressFor,
    required this.headerHeight,
    required this.bottomPadding,
    required this.highlightedMessageId,
    required this.onReplyTap,
    required this.hydrateFocusedMedia,
    required this.retryFocusedMedia,
    this.onMessageLongPress,
  });

  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final Chat chat;
  final List<ChatListItemElement> items;
  final double Function(String messageId) animationProgressFor;

  final double headerHeight;
  final double bottomPadding;
  final String? highlightedMessageId;
  final ValueChanged<String> onReplyTap;
  final Future<ChatMessage> Function(ChatMessage)? hydrateFocusedMedia;
  final VoidCallback retryFocusedMedia;
  final ValueChanged<ChatMessage>? onMessageLongPress;

  Widget _buildMessage(
    BuildContext context,
    ChatMessage message,
    double maxWidth,
  ) {
    Widget bubble(ChatMessage displayMessage) => MessageBubble(
      message: displayMessage,
      initialAnimationProgress: hydrateFocusedMedia == null
          ? animationProgressFor(displayMessage.id)
          : 1,
      maxWidth: maxWidth,
      peerName: chat.userName,
      peerAvatarUrl: chat.avatarUrl,
      peerAvatarLoader: () =>
          context.read<IChatsRepository>().resolveAvatar(chat),
      onLongPress: onMessageLongPress,
      onReplyTap: displayMessage.replyTo == null
          ? null
          : () => onReplyTap(displayMessage.replyTo!.messageId),
    );

    final loader = hydrateFocusedMedia;
    final needsMedia =
        message.type == MessageType.image &&
            message.mediaStoragePaths.isNotEmpty ||
        message.type == MessageType.audio && message.audioStoragePath != null;
    if (loader == null || !needsMedia) return bubble(message);
    return FutureBuilder<ChatMessage>(
      future: loader(message),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return bubble(snapshot.data!);
        }
        return _FocusedMediaPlaceholder(
          message: message,
          maxWidth: maxWidth,
          hasError: snapshot.hasError,
          onRetry: retryFocusedMedia,
          onLongPress: onMessageLongPress == null
              ? null
              : () => onMessageLongPress!(message),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final systemPadding = MediaQuery.paddingOf(context);

    return ScrollablePositionedList.builder(
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      reverse: true,
      padding: EdgeInsets.only(top: headerHeight + 12.0, bottom: bottomPadding),

      itemCount: items.length,

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
          key: key,
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
            MessageItemElement(:final message) => _buildMessage(
              context,
              message,
              screenWidth * 0.8,
            ),

            DateSeparatorElement(:final date) => DateSeparator(date: date),
          },
        );
      },
    );
  }
}

class _FocusedMediaPlaceholder extends StatelessWidget {
  const _FocusedMediaPlaceholder({
    required this.message,
    required this.maxWidth,
    required this.hasError,
    required this.onRetry,
    required this.onLongPress,
  });

  final ChatMessage message;
  final double maxWidth;
  final bool hasError;
  final VoidCallback onRetry;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isImage = message.type == MessageType.image;
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: hasError ? onRetry : null,
        child: Container(
          width: isImage
              ? maxWidth.clamp(160.0, 300.0)
              : maxWidth.clamp(160.0, 286.0),
          height: isImage ? 190 : 64,
          decoration: BoxDecoration(
            color: message.isMine
                ? context.colorScheme.primary
                : AppColors.incomingBubble,
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: hasError
              ? Icon(
                  Icons.refresh_rounded,
                  color: context.colorScheme.onPrimary,
                )
              : SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: message.isMine
                        ? context.colorScheme.onPrimary
                        : context.colorScheme.primary,
                  ),
                ),
        ),
      ),
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
