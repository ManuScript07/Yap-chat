import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

class ReactionIcon extends StatelessWidget {
  const ReactionIcon(this.code, {super.key, this.size = 26});
  final ReactionCode code;
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    code.assetPath,
    width: size,
    height: size,
    semanticsLabel: code.wireName,
  );
}

/// Shared by hydrated bubbles and distant-media placeholders. Keeping the
/// same bar height avoids a reaction-induced jump when media finishes loading.
class ConversationMessageReactions extends StatelessWidget {
  const ConversationMessageReactions({
    super.key,
    required this.message,
    this.peerAvatarUrl,
    this.peerAvatarLoader,
    this.onSelected,
  });

  final ChatMessage message;
  final String? peerAvatarUrl;
  final Future<String?> Function()? peerAvatarLoader;
  final ValueChanged<ReactionCode>? onSelected;

  @override
  Widget build(BuildContext context) {
    final identity = context
        .select<AuthBloc, (String, String?, ImageProvider?)>((bloc) {
          final auth = bloc.state;
          final profile = auth.profile;
          final primary = profile?.primaryPhoto;
          final bytes = primary?.bytes ?? profile?.avatarBytes;
          return (
            auth.session?.userId ?? '',
            primary?.avatarUrl ??
                profile?.avatarUrl ??
                (profile?.yandexAvatarDisabled != true
                    ? auth.session?.avatarUrl
                    : null),
            bytes == null ? null : MemoryImage(bytes),
          );
        });
    return MessageReactions(
      message: message,
      currentUserId: identity.$1,
      ownAvatarUrl: identity.$2,
      ownAvatarImage: identity.$3,
      peerAvatarUrl: peerAvatarUrl,
      peerAvatarLoader: peerAvatarLoader,
      onSelected: onSelected,
    );
  }
}

class MessageReactions extends StatefulWidget {
  const MessageReactions({
    super.key,
    required this.message,
    required this.currentUserId,
    this.ownAvatarUrl,
    this.ownAvatarImage,
    this.peerAvatarUrl,
    this.peerAvatarLoader,
    this.onSelected,
  });
  final ChatMessage message;
  final String currentUserId;
  final String? ownAvatarUrl, peerAvatarUrl;
  final ImageProvider? ownAvatarImage;
  final Future<String?> Function()? peerAvatarLoader;
  final ValueChanged<ReactionCode>? onSelected;

  @override
  State<MessageReactions> createState() => _MessageReactionsState();

  static List<List<MessageReaction>> groupsFor(MessageReactionState state) {
    final ordered = state.reactions.indexed.toList()
      ..sort((a, b) {
        final order = a.$2.position.compareTo(b.$2.position);
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    final groups = <ReactionCode, List<MessageReaction>>{};
    for (final entry in ordered) {
      groups.putIfAbsent(entry.$2.code, () => []).add(entry.$2);
    }
    return groups.values.toList();
  }

  static double widthFor(MessageReactionState state) {
    final groups = groupsFor(state);
    return groups.fold<double>(
          0,
          (width, group) => width + 68 + (group.length - 1) * 15,
        ) +
        (groups.length - 1).clamp(0, 1) * 5;
  }
}

class _MessageReactionsState extends State<MessageReactions> {
  final _retiring = <String, (MessageReaction, double)>{};
  final _retiringPills = <String, (List<MessageReaction>, double)>{};
  Timer? _retireTimer;

  List<(List<MessageReaction>, double)> _pillGroups(
    MessageReactionState state,
  ) {
    final result = <(List<MessageReaction>, double)>[];
    var left = 0.0;
    for (final group in MessageReactions.groupsFor(state)) {
      result.add((group, left));
      left += 73 + (group.length - 1) * 15;
    }
    return result;
  }

  List<(MessageReaction, double)> _avatars(MessageReactionState state) {
    final result = <(MessageReaction, double)>[];
    var left = 0.0;
    for (final group in MessageReactions.groupsFor(state)) {
      for (var i = 0; i < group.length; i++) {
        result.add((group[i], left + 38 + i * 15));
      }
      left += 73 + (group.length - 1) * 15;
    }
    return result;
  }

  @override
  void didUpdateWidget(covariant MessageReactions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.message.reactionState.reactions
        .map((r) => r.userId)
        .toSet();
    _retiring.removeWhere((id, _) => active.contains(id));
    final activePills = _pillGroups(
      widget.message.reactionState,
    ).map((entry) => entry.$1.first.userId).toSet();
    _retiringPills.removeWhere((id, _) => activePills.contains(id));
    for (final entry in _pillGroups(oldWidget.message.reactionState)) {
      if (!activePills.contains(entry.$1.first.userId)) {
        _retiringPills[entry.$1.first.userId] = entry;
      }
    }
    for (final avatar in _avatars(oldWidget.message.reactionState)) {
      if (!active.contains(avatar.$1.userId)) {
        _retiring[avatar.$1.userId] = avatar;
      }
    }
    if (_retiring.isNotEmpty || _retiringPills.isNotEmpty) {
      _retireTimer?.cancel();
      _retireTimer = Timer(const Duration(milliseconds: 260), () {
        if (mounted) {
          setState(() {
            _retiring.clear();
            _retiringPills.clear();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _retireTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final currentUserId = widget.currentUserId;
    final onSelected = widget.onSelected;
    final avatars = _avatars(message.reactionState);
    final pills = <Widget>[];
    for (final (group, left) in [
      ..._retiringPills.values,
      ..._pillGroups(message.reactionState),
    ]) {
      final retiring = _retiringPills.containsKey(group.first.userId);
      final code = group.first.code;
      final selected = group.any((r) => r.userId == currentUserId);
      final base = message.isMine
          ? AppColors.incomingBubble
          : context.colorScheme.primary;
      final width = 68.0 + (group.length - 1) * 15;
      pills.add(
        AnimatedPositioned(
          key: ValueKey('pill:${group.first.userId}'),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          left: left,
          top: 0,
          width: width,
          height: 32,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: retiring ? 0 : 1),
            duration: const Duration(milliseconds: 240),
            builder: (_, value, child) => IgnorePointer(
              ignoring: retiring,
              child: Opacity(
                opacity: value,
                child: Transform.scale(scale: .9 + .1 * value, child: child),
              ),
            ),
            child: Semantics(
              button: onSelected != null && !retiring,
              selected: selected,
              label: code.wireName,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                decoration: BoxDecoration(
                  color: selected
                      ? base
                      : base.withValues(alpha: message.isMine ? .25 : .15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onSelected == null ? null : () => onSelected(code),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: .85,
                                    end: 1,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: ReactionIcon(
                            code,
                            size: 24,
                            key: ValueKey(code),
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
    // Global avatar keys survive joining/splitting emoji groups. The newest
    // avatar is painted last, so its edge overlaps the older avatar.
    avatars.addAll(_retiring.values);
    avatars.sort((a, b) => a.$1.position.compareTo(b.$1.position));
    final width = avatars.fold<double>(
      MessageReactions.widthFor(message.reactionState),
      (width, avatar) => avatar.$2 + 22 > width ? avatar.$2 + 22 : width,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        height: 32,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ...pills,
            for (final (reaction, offset) in avatars)
              AnimatedPositioned(
                key: ValueKey('avatar:${reaction.userId}'),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                left: offset,
                top: 5,
                width: 22,
                height: 22,
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: _retiring.containsKey(reaction.userId) ? 0 : 1,
                    ),
                    duration: const Duration(milliseconds: 240),
                    builder: (_, value, child) => Opacity(
                      opacity: value,
                      child: Transform.scale(
                        scale: .9 + .1 * value,
                        child: child,
                      ),
                    ),
                    child: UserAvatar(
                      key: ValueKey(reaction.userId),
                      size: 22,
                      borderRadius: 11,
                      avatarUrl: reaction.userId == currentUserId
                          ? widget.ownAvatarUrl
                          : widget.peerAvatarUrl,
                      avatarImage: reaction.userId == currentUserId
                          ? widget.ownAvatarImage
                          : null,
                      avatarLoader: reaction.userId == currentUserId
                          ? null
                          : widget.peerAvatarLoader,
                      preferAvatarLoader: reaction.userId != currentUserId,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
