import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/widgets/animated_status_switcher.dart';

class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    this.avatarUrl,
    this.avatarImage,
    this.avatarLoader,
    this.avatarRevision,
    this.size = 48,
    this.borderRadius = 10,
    this.isOnline = false,
    this.showOnlineBadge = false,
  });

  final String? avatarUrl;
  final ImageProvider? avatarImage;
  final Future<String?> Function()? avatarLoader;
  final Object? avatarRevision;
  final double size;
  final double borderRadius;
  final bool isOnline;
  final bool showOnlineBadge;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Future<String?>? _avatarFuture;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarRevision != widget.avatarRevision ||
        oldWidget.avatarUrl != widget.avatarUrl) {
      _loadAvatar();
    }
  }

  void _loadAvatar() {
    _avatarFuture = widget.avatarLoader?.call();
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = context.colorScheme.primary;
    final iconColor = context.colorScheme.onSurface;
    final primaryBrandColor = context.colorScheme.primary;
    final backgroundColor = context.scaffoldBackgroundColor;

    final targetWidth = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Container(
            width: widget.size,
            height: widget.size,
            color: surfaceColor,
            child: widget.avatarImage != null
                ? _image(
                    widget.avatarImage!,
                    targetWidth: targetWidth,
                    iconColor: iconColor,
                  )
                : FutureBuilder<String?>(
                    future: _avatarFuture,
                    builder: (context, snapshot) {
                      final value = snapshot.data ?? widget.avatarUrl;
                      if (value == null || value.isEmpty) {
                        return Icon(
                          Icons.person,
                          color: iconColor,
                          size: widget.size * 0.65,
                        );
                      }
                      return _image(
                        _provider(value),
                        targetWidth: targetWidth,
                        iconColor: iconColor,
                      );
                    },
                  ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: AnimatedStatusSwitcher(
            child: widget.showOnlineBadge && widget.isOnline
                ? Container(
                    key: const ValueKey('online-badge'),
                    width: widget.size * 0.32,
                    height: widget.size * 0.32,
                    decoration: BoxDecoration(
                      color: primaryBrandColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: backgroundColor, width: 2),
                    ),
                  )
                : const SizedBox(key: ValueKey('online-badge-hidden')),
          ),
        ),
      ],
    );
  }

  Widget _image(
    ImageProvider provider, {
    required int targetWidth,
    required Color iconColor,
  }) => Image(
    image: ResizeImage.resizeIfNeeded(targetWidth, null, provider),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) =>
        Icon(Icons.person, color: iconColor, size: widget.size * 0.65),
  );

  ImageProvider _provider(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
        ? NetworkImage(value)
        : FileImage(File(value));
  }
}
