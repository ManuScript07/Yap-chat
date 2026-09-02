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
    this.preferAvatarLoader = false,
    this.avatarRevision,
    this.size = 48,
    this.borderRadius = 10,
    this.isOnline = false,
    this.showOnlineBadge = false,
  });

  final String? avatarUrl;
  final ImageProvider? avatarImage;
  final Future<String?> Function()? avatarLoader;

  /// Avoids a simultaneous direct network image request while [avatarLoader]
  /// is filling the disk cache. On loader failure, [avatarUrl] remains the
  /// fallback.
  final bool preferAvatarLoader;
  final Object? avatarRevision;
  final double size;
  final double borderRadius;
  final bool isOnline;
  final bool showOnlineBadge;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  static const _resolvedAvatarCacheLimit = 200;
  static final _resolvedAvatarPaths = <Object, String>{};

  String? _resolvedAvatarPath;
  int _loadGeneration = 0;
  bool _isAvatarLoading = false;

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
    final loader = widget.avatarLoader;
    final generation = ++_loadGeneration;
    final cacheKey = widget.avatarRevision ?? widget.avatarUrl;
    final cachedPath = cacheKey == null ? null : _resolvedAvatarPaths[cacheKey];
    if (cachedPath != null) {
      _resolvedAvatarPath = cachedPath;
      _isAvatarLoading = false;
      return;
    }
    if (loader == null) {
      _resolvedAvatarPath = null;
      _isAvatarLoading = false;
      return;
    }

    _isAvatarLoading = true;
    Future<String?>.sync(loader).then(
      (value) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _resolvedAvatarPath = value;
          _isAvatarLoading = false;
          if (cacheKey != null && value != null && value.isNotEmpty) {
            _rememberResolvedPath(cacheKey, value);
          }
        });
      },
      onError: (_, _) {
        if (!mounted || generation != _loadGeneration) return;
        // Keep the last successfully rendered avatar on transient failures.
        setState(() => _isAvatarLoading = false);
      },
    );
  }

  void _rememberResolvedPath(Object key, String path) {
    _resolvedAvatarPaths.remove(key);
    _resolvedAvatarPaths[key] = path;
    if (_resolvedAvatarPaths.length > _resolvedAvatarCacheLimit) {
      _resolvedAvatarPaths.remove(_resolvedAvatarPaths.keys.first);
    }
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
                : _avatar(targetWidth: targetWidth, iconColor: iconColor),
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

  Widget _avatar({required int targetWidth, required Color iconColor}) {
    final value =
        _resolvedAvatarPath ??
        (widget.preferAvatarLoader && _isAvatarLoading
            ? null
            : widget.avatarUrl);
    if (value == null || value.isEmpty) {
      if (_isAvatarLoading) return const SizedBox.expand();
      return Icon(Icons.person, color: iconColor, size: widget.size * 0.65);
    }
    return _image(
      _provider(value),
      targetWidth: targetWidth,
      iconColor: iconColor,
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
    frameBuilder: _revealImageFrame,
    errorBuilder: (_, _, _) => Center(
      child: Icon(Icons.person, color: iconColor, size: widget.size * 0.65),
    ),
  );

  ImageProvider _provider(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
        ? NetworkImage(value)
        : FileImage(File(value));
  }
}

Widget _revealImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  final isReady = wasSynchronouslyLoaded || frame != null;
  return AnimatedOpacity(
    opacity: isReady ? 1 : 0,
    duration: wasSynchronouslyLoaded
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    child: child,
  );
}
