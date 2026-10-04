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

class MessageReactions extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final groups = <ReactionCode, List<MessageReaction>>{};
    for (final reaction in message.reactionState.reactions) {
      groups.putIfAbsent(reaction.code, () => []).add(reaction);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final group in groups.entries)
            Builder(
              builder: (context) {
                final selected = group.value.any(
                  (r) => r.userId == currentUserId,
                );
                final background = selected
                    ? (message.isMine
                          ? context.scaffoldBackgroundColor
                          : context.colorScheme.primary)
                    : (message.isMine
                          ? context.scaffoldBackgroundColor.withValues(
                              alpha: .25,
                            )
                          : context.colorScheme.primary.withValues(alpha: .15));
                return Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Semantics(
                    button: onSelected != null,
                    selected: selected,
                    label: group.key.wireName,
                    child: Material(
                      color: background,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: onSelected == null
                            ? null
                            : () => onSelected!(group.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReactionIcon(group.key, size: 24),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 22 + (group.value.length - 1) * 15,
                                height: 22,
                                child: Stack(
                                  children: [
                                    for (var i = 0; i < group.value.length; i++)
                                      Positioned(
                                        left: i * 15.0,
                                        child: UserAvatar(
                                          key: ValueKey(group.value[i].userId),
                                          size: 22,
                                          borderRadius: 11,
                                          avatarUrl:
                                              group.value[i].userId ==
                                                  currentUserId
                                              ? ownAvatarUrl
                                              : peerAvatarUrl,
                                          avatarImage:
                                              group.value[i].userId ==
                                                  currentUserId
                                              ? ownAvatarImage
                                              : null,
                                          avatarLoader:
                                              group.value[i].userId ==
                                                  currentUserId
                                              ? null
                                              : peerAvatarLoader,
                                          preferAvatarLoader:
                                              group.value[i].userId !=
                                              currentUserId,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
