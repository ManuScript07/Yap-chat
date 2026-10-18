import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    this.initialAvatarPath,
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

  /// File location restored with the row's metadata, not a remote fallback.
  final String? initialAvatarPath;
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
  bool _isMissingFileReloadScheduled = false;
  bool _hasImageFrame = false;
  Object? _scope;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarRevision != widget.avatarRevision ||
        oldWidget.avatarUrl != widget.avatarUrl ||
        oldWidget.initialAvatarPath != widget.initialAvatarPath ||
        (oldWidget.avatarImage != null && widget.avatarImage == null) ||
        _scope != _currentScope ||
        (oldWidget.avatarLoader == null) != (widget.avatarLoader == null)) {
      _loadAvatar();
    }
  }

  bool get _hasAvatarSource =>
      widget.avatarImage != null ||
      widget.avatarRevision != null ||
      widget.avatarUrl?.isNotEmpty == true;

  String? get _avatarValue =>
      _resolvedAvatarPath ??
      (widget.preferAvatarLoader && _isAvatarLoading ? null : widget.avatarUrl);

  Object? get _currentScope {
    final account = context.read<AccountSessionController?>();
    if (account?.userId == null) return null;
    final snapshot = account!.capture();
    return (snapshot.userId, snapshot.generation);
  }

  Object? get _cacheKey {
    final revision = widget.avatarRevision ?? widget.avatarUrl;
    return revision == null ? null : (_scope, revision);
  }

  void _loadAvatar() {
    final loader = widget.avatarLoader;
    final generation = ++_loadGeneration;
    // An authoritative removal must not retain the preceding photo while a
    // list's loader resolves null, nor allow an earlier load to restore it.
    final scope = _currentScope;
    if (!_hasAvatarSource || _scope != scope) {
      _resolvedAvatarPath = null;
      _hasImageFrame = false;
    }
    _scope = scope;
    final cacheKey = _cacheKey;
    final initialPath = widget.initialAvatarPath;
    if (_hasAvatarSource &&
        initialPath != null &&
        _isExistingLocalFile(initialPath)) {
      _resolvedAvatarPath = initialPath;
      _isAvatarLoading = false;
      if (cacheKey != null) _rememberResolvedPath(cacheKey, initialPath);
      // The disk-cache fast path skips the resolver's LRU touch. Preserve it
      // for mounted avatars only, without scanning the cache or delaying paint.
      File(initialPath).setLastModified(DateTime.now()).ignore();
      return;
    }
    final cachedPath = cacheKey == null ? null : _resolvedAvatarPaths[cacheKey];
    if (cachedPath != null && _isExistingLocalFile(cachedPath)) {
      _resolvedAvatarPath = cachedPath;
      _isAvatarLoading = false;
      return;
    }
    if (cachedPath != null) _resolvedAvatarPaths.remove(cacheKey);
    if (loader == null) {
      _resolvedAvatarPath = null;
      _isAvatarLoading = false;
      return;
    }

    _isAvatarLoading = true;
    Future<String?>.sync(loader).then(
      (value) async {
        if (!mounted || generation != _loadGeneration) return;
        // Keep the current Image mounted until the replacement has a decoded
        // frame. Changing the path first leaves a blank interval even when the
        // replacement already exists on disk.
        if (value != null && value.isNotEmpty) {
          var failed = false;
          await precacheImage(
            ResizeImage.resizeIfNeeded(
              (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil(),
              null,
              _provider(value),
            ),
            context,
            onError: (_, _) => failed = true,
          );
          if (!mounted || generation != _loadGeneration) return;
          if (failed) {
            setState(() => _isAvatarLoading = false);
            return;
          }
        }
        setState(() {
          if (value != null || !_hasAvatarSource) _resolvedAvatarPath = value;
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

  static void _rememberResolvedPath(Object key, String path) {
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
    final value = _avatarValue;
    if (value == null || value.isEmpty) {
      return Icon(Icons.person, color: iconColor, size: widget.size * 0.65);
    }
    return _image(
      _provider(value),
      targetWidth: targetWidth,
      iconColor: iconColor,
      renderedValue: value,
    );
  }

  Widget _image(
    ImageProvider provider, {
    required int targetWidth,
    required Color iconColor,
    String? renderedValue,
  }) => Image(
    image: ResizeImage.resizeIfNeeded(targetWidth, null, provider),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
      if (wasSynchronouslyLoaded || frame != null) _hasImageFrame = true;
      // gaplessPlayback retains the previous frame during a replacement. Do
      // not hide that frame with a restarted opacity animation.
      return _hasImageFrame
          ? child
          : Center(
              child: Icon(
                Icons.person,
                color: iconColor,
                size: widget.size * 0.65,
              ),
            );
    },
    errorBuilder: (_, _, _) {
      if (renderedValue != null) _reloadMissingCachedFile(renderedValue);
      return Center(
        child: Icon(Icons.person, color: iconColor, size: widget.size * 0.65),
      );
    },
  );

  bool _isExistingLocalFile(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  void _reloadMissingCachedFile(String renderedValue) {
    if (_isMissingFileReloadScheduled ||
        !_canReloadMissingCachedFile(renderedValue)) {
      return;
    }
    _isMissingFileReloadScheduled = true;

    // An Image.errorBuilder can run while this widget is building.  Delay the
    // state update so that a cache eviction never causes a setState-during-
    // build exception, and coalesce repeated image error callbacks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isMissingFileReloadScheduled = false;
      if (!mounted || !_canReloadMissingCachedFile(renderedValue)) return;

      final cacheKey = _cacheKey;
      if (cacheKey != null && _resolvedAvatarPaths[cacheKey] == renderedValue) {
        _resolvedAvatarPaths.remove(cacheKey);
      }
      setState(_loadAvatar);
    });
  }

  bool _canReloadMissingCachedFile(String renderedValue) =>
      !_isAvatarLoading &&
      widget.avatarLoader != null &&
      _resolvedAvatarPath == renderedValue &&
      !_isExistingLocalFile(renderedValue);

  ImageProvider _provider(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
        ? NetworkImage(value)
        : FileImage(File(value));
  }
}
