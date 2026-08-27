import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/chat_media_gallery_page.dart';
import 'package:yap_chat/features/chat/widgets/chat_media_hero.dart';
import 'package:yap_chat/core/core.dart';

class MessageMediaGrid extends StatelessWidget {
  const MessageMediaGrid({
    super.key,
    required this.message,
    required this.maxWidth,
    required this.senderName,
    this.senderAvatarUrl,
  });

  final ChatMessage message;
  final double maxWidth;
  final String senderName;
  final String? senderAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final chunks = <List<String>>[];
    for (var start = 0; start < message.mediaUrls.length; start += 5) {
      final end = (start + 5).clamp(0, message.mediaUrls.length).toInt();
      chunks.add(message.mediaUrls.sublist(start, end));
    }

    return Column(
      children: [
        for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) ...[
          if (chunkIndex > 0) const SizedBox(height: 4),
          _MediaAlbum(
            paths: chunks[chunkIndex],
            startIndex: chunkIndex * 5,
            message: message,
            maxWidth: maxWidth,
            senderName: senderName,
            senderAvatarUrl: senderAvatarUrl,
          ),
        ],
      ],
    );
  }
}

class _MediaAlbum extends StatelessWidget {
  const _MediaAlbum({
    required this.paths,
    required this.startIndex,
    required this.message,
    required this.maxWidth,
    required this.senderName,
    this.senderAvatarUrl,
  });

  final List<String> paths;
  final int startIndex;
  final ChatMessage message;
  final double maxWidth;
  final String senderName;
  final String? senderAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final albumSize = maxWidth.clamp(160.0, 300.0).toDouble();

    return RepaintBoundary(
      key: ValueKey('${message.id}:album:$startIndex'),
      child: SizedBox(
        width: albumSize,
        height: paths.length == 1 ? albumSize * .72 : albumSize,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: switch (paths.length) {
            1 => _tile(context, 0),
            2 => Row(
              children: [
                _expandedTile(context, 0),
                _gap(),
                _expandedTile(context, 1),
              ],
            ),
            3 => Row(
              children: [
                Expanded(flex: 2, child: _tile(context, 0)),
                _gap(),
                Expanded(
                  child: Column(
                    children: [
                      _expandedTile(context, 1),
                      _gap(),
                      _expandedTile(context, 2),
                    ],
                  ),
                ),
              ],
            ),
            4 => _fourTileGrid(context, [0, 1, 2, 3]),
            5 => Row(
              children: [
                Expanded(child: _tile(context, 0)),
                _gap(),
                Expanded(child: _fourTileGrid(context, [1, 2, 3, 4])),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _fourTileGrid(BuildContext context, List<int> indices) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _expandedTile(context, indices[0]),
              _gap(),
              _expandedTile(context, indices[1]),
            ],
          ),
        ),
        _gap(),
        Expanded(
          child: Row(
            children: [
              _expandedTile(context, indices[2]),
              _gap(),
              _expandedTile(context, indices[3]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gap() => const SizedBox(width: 3, height: 3);

  Widget _expandedTile(BuildContext context, int index) {
    return Expanded(child: _tile(context, index));
  }

  Widget _tile(BuildContext context, int index) {
    final path = paths[index];
    final absoluteIndex = startIndex + index;
    final isSending = message.status == MessageStatus.sending;
    final isError = message.status == MessageStatus.error;

    return KeyedSubtree(
      key: ValueKey('${message.id}:media:$absoluteIndex'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ChatMediaHero(
            path: path,
            heroTag: chatMediaHeroTag(message.id, absoluteIndex),
            fit: BoxFit.cover,
            cacheWidth: path.startsWith('http') ? null : 900,
          ),
          if (!isSending && !isError)
            Material(
              color: Colors.transparent,
              child: InkWell(onTap: () => _openGallery(context, absoluteIndex)),
            ),
          if (isSending)
            ColoredBox(
              color: context.scaffoldBackgroundColor.withValues(alpha: 0.4),
              child: Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    color: context.colorScheme.primary,
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
          if (isError)
            ColoredBox(
              color: context.scaffoldBackgroundColor.withValues(alpha: 0.4),
              child: Center(
                child: Material(
                  color: context.colorScheme.primary,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.read<ChatBloc>().add(
                      ChatMessageRetryRequested(message),
                    ),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.refresh_rounded,
                        color: context.colorScheme.surface,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openGallery(BuildContext context, int index) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final aspectRatio = await resolveImageAspectRatio(
      context,
      chatMediaImageProvider(
        message.mediaUrls[index],
        cacheWidth: message.mediaUrls[index].startsWith('http') ? null : 900,
      ),
    );
    if (!context.mounted) return;
    final aspectRatios = List<double?>.filled(message.mediaUrls.length, null);
    aspectRatios[index] = aspectRatio;

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => ChatMediaGalleryPage(
          imagePaths: message.mediaUrls,
          heroTags: List.generate(
            message.mediaUrls.length,
            (imageIndex) => chatMediaHeroTag(message.id, imageIndex),
          ),
          initialIndex: index,
          senderName: senderName,
          senderAvatarUrl: senderAvatarUrl,
          imageAspectRatios: aspectRatios,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        ),
      ),
    );
  }
}

String chatMediaHeroTag(String messageId, int imageIndex) {
  return 'chat-media-$messageId-$imageIndex';
}
