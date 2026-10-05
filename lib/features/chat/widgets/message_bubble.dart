import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/widgets/message_media_grid.dart';
import 'package:yap_chat/features/chat/widgets/audio_message_content.dart';
import 'package:yap_chat/features/chat/widgets/message_reply_preview.dart';
import 'package:yap_chat/features/chat/widgets/reply_preview_mode.dart';
import 'package:yap_chat/features/chat/widgets/message_status_icon.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/features/chat/widgets/message_reactions.dart';
import 'package:yap_chat/features/chat/widgets/animated_reaction_section.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.initialAnimationProgress,
    required this.maxWidth,
    required this.peerName,
    this.peerAvatarUrl,
    this.peerAvatarLoader,
    this.onLongPress,
    this.onReplyTap,
    this.replyPreviewMode = ReplyPreviewMode.direct,
    this.onReaction,
  });

  final ChatMessage message;
  final double initialAnimationProgress;
  final double maxWidth;
  final String peerName;
  final String? peerAvatarUrl;
  final Future<String?> Function()? peerAvatarLoader;
  final ValueChanged<ChatMessage>? onLongPress;
  final VoidCallback? onReplyTap;
  final ReplyPreviewMode replyPreviewMode;
  final void Function(ReactionCode code, bool toggle)? onReaction;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  static final _timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _startEntrance(widget.initialAnimationProgress);
  }

  void _startEntrance(double progress) {
    _controller.value = progress.clamp(0.0, 1.0);
    if (_controller.value < 1.0) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.message.id != widget.message.id) {
      _startEntrance(widget.initialAnimationProgress);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isImage =
        message.type == MessageType.image && message.mediaUrls.isNotEmpty;
    final isLocation =
        message.type == MessageType.location &&
        message.latitude != null &&
        message.longitude != null;
    final isAudio =
        message.type == MessageType.audio &&
        message.audioUrl != null &&
        message.audioUrl!.isNotEmpty;

    final bubbleColor = message.isMine
        ? context.colorScheme.primary
        : AppColors.incomingBubble;

    final textColor = message.isMine
        ? context.scaffoldBackgroundColor
        : context.colorScheme.onSecondaryContainer;

    final timeColor = message.isMine
        ? context.scaffoldBackgroundColor
        : AppColors.incomingTime;

    final iconColor = message.isMine
        ? context.scaffoldBackgroundColor
        : AppColors.incomingTime;

    final timeStatusWidth = message.isMine ? 66.0 : 44.0;
    final replyWidth = switch (message.type) {
      MessageType.image =>
        (widget.maxWidth - 6).clamp(160.0, 300.0).toDouble() + 6,
      MessageType.audio => widget.maxWidth.clamp(160.0, 286.0).toDouble(),
      MessageType.location => widget.maxWidth.clamp(160.0, 300.0).toDouble(),
      MessageType.text => widget.maxWidth,
    };

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Align(
          alignment: message.type == MessageType.text
              ? (message.isMine ? Alignment.topRight : Alignment.topLeft)
              : (message.isMine ? Alignment.centerRight : Alignment.centerLeft),
          heightFactor: message.type == MessageType.text ? 1 : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onDoubleTap: widget.onReaction == null
                    ? null
                    : () => widget.onReaction!(ReactionCode.heart, true),
                onLongPress: widget.onLongPress == null
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        widget.onLongPress!(message);
                      },
                child: Container(
                  constraints: BoxConstraints(maxWidth: widget.maxWidth),
                  width: message.replyTo == null ? null : replyWidth,
                  padding: EdgeInsets.all(
                    isImage || isLocation || isAudio ? 3 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: message.replyTo == null
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.stretch,
                    children: [
                      if (message.replyTo case final reply?) ...[
                        Padding(
                          padding: isImage || isLocation || isAudio
                              ? const EdgeInsets.fromLTRB(9, 9, 9, 0)
                              : EdgeInsets.zero,
                          child: MessageReplyPreview(
                            reply: reply,
                            peerName: widget.peerName,
                            isMessageMine: message.isMine,
                            mode: widget.replyPreviewMode,
                            onTap: widget.onReplyTap,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      isImage
                          ? _buildImageMessage(context, textColor)
                          : isLocation
                          ? _buildLocationMessage(context)
                          : isAudio
                          ? AudioMessageContent(message: message)
                          : _buildTextMessage(
                              context,
                              textColor,
                              timeColor,
                              iconColor,
                              timeStatusWidth,
                            ),
                      if (isImage || isLocation || isAudio)
                        AnimatedReactionSection(
                          visible: message.reactionState.reactions.isNotEmpty,
                          child: Padding(
                            padding: isImage
                                ? const EdgeInsets.fromLTRB(4, 8, 4, 9)
                                : EdgeInsets.fromLTRB(
                                    isAudio ? 12 : 14,
                                    4,
                                    isAudio ? 12 : 14,
                                    8,
                                  ),
                            child: _buildReactions(context),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_showsExternalRetry(message))
                Positioned(
                  left: -36,
                  bottom: 0,
                  child: _ExternalRetryButton(
                    onPressed: () => _retryMessage(context, message),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextMessage(
    BuildContext context,
    Color textColor,
    Color timeColor,
    Color iconColor,
    double timeStatusWidth,
  ) {
    final hasReactions = widget.message.reactionState.reactions.isNotEmpty;
    final text = _buildMessageContent(context, textColor, timeStatusWidth);
    final available = (widget.maxWidth - 24).clamp(0.0, double.infinity);
    final reactionWidth = MessageReactions.widthFor(
      widget.message.reactionState,
    );
    var naturalWidth = 0.0;
    var footerStatusWidth = timeStatusWidth;
    var footerStatusHeight = widget.message.isMine ? 18.0 : 14.0;
    if (hasReactions) {
      final painter = TextPainter(
        text: TextSpan(
          text: '${widget.message.text} ',
          style: _messageTextSpan(textColor, timeStatusWidth).style,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: available);
      naturalWidth = (painter.width + timeStatusWidth).clamp(0.0, available);
      painter.dispose();
      final statusPainter = TextPainter(
        text: TextSpan(
          text: _timeFormat.format(widget.message.timestamp),
          style: DefaultTextStyle.of(
            context,
          ).style.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      footerStatusWidth =
          statusPainter.width + (widget.message.isMine ? 22 : 0);
      footerStatusHeight = statusPainter.height > footerStatusHeight
          ? statusPainter.height
          : footerStatusHeight;
      statusPainter.dispose();
    }
    final width = widget.message.replyTo != null
        ? available
        : (reactionWidth + footerStatusWidth + 8).clamp(
            naturalWidth,
            available,
          );
    final sharesStatusRow = reactionWidth + footerStatusWidth + 8 <= width;
    final reservedBottom = sharesStatusRow ? 0.0 : footerStatusHeight + 4;
    // Only reactions animate. Time/status stays mounted once, outside the
    // reveal, at the bottom-right of the growing content stack.
    final reactions = _buildReactions(context);
    return SizedBox(
      width: widget.message.replyTo == null ? null : double.infinity,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              text,
              AnimatedReactionSection(
                visible: hasReactions,
                reservedBottom: reservedBottom,
                child: hasReactions
                    ? SizedBox(
                        width: width,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: 6,
                            right: sharesStatusRow ? footerStatusWidth + 8 : 0,
                            bottom: reservedBottom,
                          ),
                          child: reactions,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: _buildTimeStatus(context, timeColor, iconColor),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationMessage(BuildContext context) {
    final message = widget.message;

    final textColor = message.isMine
        ? context.scaffoldBackgroundColor
        : context.colorScheme.onSecondaryContainer;

    final iconColor = message.isMine
        ? context.scaffoldBackgroundColor
        : context.colorScheme.primary;

    final timeColor = message.isMine
        ? context.scaffoldBackgroundColor
        : AppColors.incomingTime;

    // Ширина, которую нужно зарезервировать под время + статус.
    final timeStatusWidth = message.isMine ? 66.0 : 44.0;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _openLocation(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(right: timeStatusWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_rounded, size: 36, color: iconColor),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.isMine
                              ? context.l10n.locationMessageYou
                              : context.l10n.locationMessageIncoming,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              right: 0,
              bottom: 0,
              child: _buildTimeStatus(
                context,
                timeColor,
                message.isMine
                    ? context.scaffoldBackgroundColor
                    : context.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactions(BuildContext context) {
    return ConversationMessageReactions(
      message: widget.message,
      peerAvatarUrl: widget.peerAvatarUrl,
      peerAvatarLoader: widget.peerAvatarLoader,
      onSelected: widget.onReaction == null
          ? null
          : (code) => widget.onReaction!(code, true),
    );
  }

  Future<void> _openLocation(BuildContext context) async {
    final message = widget.message;
    final latitude = message.latitude;
    final longitude = message.longitude;
    if (latitude == null || longitude == null) return;

    final uri = Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.locationOpenError,
        type: SnackBarType.error,
      );
    }
  }

  Widget _buildImageMessage(BuildContext context, Color textColor) {
    final message = widget.message;
    final ownAvatar = context.select<AuthBloc, (String?, Uint8List?)>((bloc) {
      final profile = bloc.state.profile;
      final primaryPhoto = profile?.primaryPhoto;
      final avatarUrl = primaryPhoto?.avatarUrl ?? profile?.avatarUrl;
      final avatarBytes = primaryPhoto?.bytes ?? profile?.avatarBytes;
      final hasOwnAvatar =
          (avatarUrl?.isNotEmpty ?? false) || avatarBytes != null;
      final fallbackAvatarUrl =
          !hasOwnAvatar && profile?.yandexAvatarDisabled != true
          ? bloc.state.session?.avatarUrl
          : null;
      return (avatarUrl ?? fallbackAvatarUrl, avatarBytes);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            MessageMediaGrid(
              message: message,
              maxWidth: widget.maxWidth - 6,
              senderName: message.isMine
                  ? context.l10n.chatsMessagePrefixYou
                  : widget.peerName,
              senderAvatarUrl: message.isMine
                  ? ownAvatar.$1
                  : widget.peerAvatarUrl,
              senderAvatarLoader: message.isMine
                  ? null
                  : widget.peerAvatarLoader,
              senderAvatarImage: message.isMine && ownAvatar.$2 != null
                  ? MemoryImage(ownAvatar.$2!)
                  : null,
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: _buildImageTimeStatus(context),
            ),
          ],
        ),
        if (message.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              message.text,
              style: TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.w400,
                height: 1.2,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImageTimeStatus(BuildContext context) {
    final message = widget.message;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.scaffoldBackgroundColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _timeFormat.format(message.timestamp),
              style: TextStyle(
                color: context.colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (message.isMine) ...[
              const SizedBox(width: 4),
              _buildStatusIcon(context.colorScheme.onSurface),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimeStatus(
    BuildContext context,
    Color timeColor,
    Color iconColor,
  ) {
    final message = widget.message;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _timeFormat.format(message.timestamp),
          style: TextStyle(
            color: timeColor,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        if (message.isMine) ...[
          const SizedBox(width: 4),
          _buildStatusIcon(iconColor),
        ],
      ],
    );
  }

  Widget _buildMessageContent(
    BuildContext context,
    Color textColor,
    double timeStatusWidth,
  ) {
    return Text.rich(_messageTextSpan(textColor, timeStatusWidth));
  }

  TextSpan _messageTextSpan(Color textColor, double timeStatusWidth) =>
      TextSpan(
        text: widget.message.text,
        style: AppTextStyles.messageBody.copyWith(color: textColor),
        children: [
          WidgetSpan(child: SizedBox(width: timeStatusWidth, height: 1)),
        ],
      );

  Widget _buildStatusIcon(Color color) {
    return MessageStatusIcon(status: widget.message.status, color: color);
  }

  bool _showsExternalRetry(ChatMessage message) =>
      message.isMine &&
      message.status == MessageStatus.error &&
      message.type != MessageType.image &&
      message.type != MessageType.audio;

  void _retryMessage(BuildContext context, ChatMessage message) {
    HapticFeedback.selectionClick();
    context.read<ChatBloc>().add(ChatMessageRetryRequested(message));
  }
}

class _ExternalRetryButton extends StatelessWidget {
  const _ExternalRetryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Повторить отправку',
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onPressed,
          radius: 19,
          containedInkWell: false,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(
              Icons.refresh_rounded,
              size: 21,
              color: context.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
