import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.avatarUrl,
    this.avatarImage,
    this.size = 48,
    this.borderRadius = 10,
    this.isOnline = false,
    this.showOnlineBadge = false,
  });

  final String? avatarUrl;
  final ImageProvider? avatarImage;
  final double size;
  final double borderRadius;
  final bool isOnline;
  final bool showOnlineBadge;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = context.colorScheme.primary;
    final iconColor = context.colorScheme.onSurface;
    final primaryBrandColor = context.colorScheme.primary;
    final backgroundColor = context.scaffoldBackgroundColor;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Container(
            width: size,
            height: size,
            color: surfaceColor,
            child: avatarImage != null
                ? Image(image: avatarImage!, fit: BoxFit.cover)
                : avatarUrl != null && avatarUrl!.isNotEmpty
                ? Image(
                    image: _provider(avatarUrl!),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.person, color: iconColor, size: size * 0.65),
                  )
                : Icon(Icons.person, color: iconColor, size: size * 0.65),
          ),
        ),
        if (showOnlineBadge && isOnline)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.32,
              height: size * 0.32,
              decoration: BoxDecoration(
                color: primaryBrandColor,
                shape: BoxShape.circle,
                border: Border.all(color: backgroundColor, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  ImageProvider _provider(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
        ? NetworkImage(value)
        : FileImage(File(value));
  }
}
