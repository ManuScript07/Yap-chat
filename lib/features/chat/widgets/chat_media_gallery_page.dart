import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';
import 'package:yap_chat/ui/widgets/widgets.dart';

class ChatMediaGalleryPage extends StatefulWidget {
  const ChatMediaGalleryPage({
    super.key,
    required this.imagePaths,
    required this.heroTags,
    required this.initialIndex,
    required this.senderName,
    this.senderAvatarUrl,
  });

  final List<String> imagePaths;
  final List<String> heroTags;
  final int initialIndex;
  final String senderName;
  final String? senderAvatarUrl;

  @override
  State<ChatMediaGalleryPage> createState() => _ChatMediaGalleryPageState();
}

class _ChatMediaGalleryPageState extends State<ChatMediaGalleryPage> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isSaving = false;
  bool _isZoomed = false;

  static const _overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_overlayStyle);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_overlayStyle);
    super.dispose();
  }

  void _setZoomed(bool isZoomed) {
    if (_isZoomed == isZoomed || !mounted) return;
    setState(() => _isZoomed = isZoomed);
  }

  Future<void> _saveCurrentImage() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    final isSaved = await MediaService.saveImageToGallery(
      widget.imagePaths[_currentIndex],
    );
    if (!mounted) return;

    setState(() => _isSaving = false);

    showAppSnackBar(
      context,
      message: isSaved
          ? context.l10n.photoHasBeenSavedToGallery
          : context.l10n.failedToSavePhoto,
      type: isSaved ? SnackBarType.info : SnackBarType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                clipBehavior: Clip.hardEdge,
                physics: _isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.imagePaths.length,
                onPageChanged: (index) => setState(() {
                  _currentIndex = index;
                  _isZoomed = false;
                }),
                itemBuilder: (context, index) {
                  final imagePath = widget.imagePaths[index];
                  return _ZoomableGalleryImage(
                    key: ValueKey(widget.heroTags[index]),
                    path: imagePath,
                    heroTag: widget.heroTags[index],
                    onZoomChanged: _setZoomed,
                  );
                },
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 16,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).pop(),
                      width: 44,
                      height: 44,
                      borderRadius: 16,
                      iconSize: 26,
                    ),
                    const SizedBox(width: 12),
                    UserAvatar(
                      avatarUrl: widget.senderAvatarUrl,
                      size: 44,
                      borderRadius: 14,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GlassIconButton(
                      icon: Icons.download_rounded,
                      onTap: _saveCurrentImage,
                      width: 44,
                      height: 44,
                      borderRadius: 16,
                      iconSize: 24,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomableGalleryImage extends StatefulWidget {
  const _ZoomableGalleryImage({
    super.key,
    required this.path,
    required this.heroTag,
    required this.onZoomChanged,
  });

  final String path;
  final String heroTag;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableGalleryImage> createState() => _ZoomableGalleryImageState();
}

class _ZoomableGalleryImageState extends State<_ZoomableGalleryImage> {
  late final TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.addListener(_handleTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    widget.onZoomChanged(scale > 1.01);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1,
        maxScale: 4,
        panEnabled: true,
        boundaryMargin: EdgeInsets.zero,
        clipBehavior: Clip.hardEdge,
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: _ChatImage(path: widget.path),
          ),
        ),
      ),
    );
  }
}

class _ChatImage extends StatelessWidget {
  const _ChatImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Icon(
          Icons.broken_image_rounded,
          color: context.colorScheme.surface,
          size: 48,
        ),
      );
    }

    return Image.file(
      File(path),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Icon(
        Icons.broken_image_rounded,
        color: context.colorScheme.surface,
        size: 48,
      ),
    );
  }
}
