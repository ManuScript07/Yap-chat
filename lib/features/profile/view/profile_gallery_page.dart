import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/ui/ui.dart';

class ProfileGalleryPage extends StatefulWidget {
  const ProfileGalleryPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.displayName,
    this.imageAspectRatios = const [],
  });

  final List<ProfilePhoto> photos;
  final int initialIndex;
  final String displayName;
  final List<double?> imageAspectRatios;

  @override
  State<ProfileGalleryPage> createState() => _ProfileGalleryPageState();
}

class _ProfileGalleryPageState extends State<ProfileGalleryPage> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;
  bool _isSaving = false;
  bool _showChrome = true;
  bool _disableHeroes = false;
  bool _canPop = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _precachePhotos());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final overlayStyle = _overlayStyle(context);
    final systemPadding = MediaQuery.paddingOf(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final addedAt = widget.photos[_currentIndex].updatedAt?.toLocal();
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          backgroundColor: context.scaffoldBackgroundColor,
          extendBody: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _showChrome = !_showChrome),
                  child: HeroMode(
                    enabled: !_disableHeroes,
                    child: PageView.builder(
                      controller: _pageController,
                      clipBehavior: Clip.hardEdge,
                      allowImplicitScrolling: true,
                      physics: _isZoomed
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(),
                      itemCount: widget.photos.length,
                      onPageChanged: (index) => setState(() {
                        _currentIndex = index;
                        _isZoomed = false;
                      }),
                      itemBuilder: (context, index) => RepaintBoundary(
                        child: _ZoomableProfilePhoto(
                          key: ValueKey(widget.photos[index].identity),
                          photo: widget.photos[index],
                          initialAspectRatio:
                              index < widget.imageAspectRatios.length
                              ? widget.imageAspectRatios[index]
                              : null,
                          onZoomChanged: (value) {
                            if (_isZoomed != value && mounted) {
                              setState(() => _isZoomed = value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: systemPadding.top + 16,
                left: systemPadding.left + 16,
                right: systemPadding.right + 16,
                child: IgnorePointer(
                  ignoring: !_showChrome,
                  child: AnimatedOpacity(
                    opacity: _showChrome ? 1 : 0,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeInOut,
                    child: Row(
                      children: [
                        GlassIconButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: _close,
                          width: 44,
                          height: 44,
                          borderRadius: 16,
                          iconSize: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: .4,
                                ),
                              ),
                              if (addedAt != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat(
                                    'd MMMM yyyy',
                                    Localizations.localeOf(context).toString(),
                                  ).format(addedAt),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: .68,
                                    ),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: .2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        GlassIconButton(
                          icon: Icons.download_rounded,
                          onTap: _isSaving ? () {} : _saveCurrent,
                          width: 44,
                          height: 44,
                          borderRadius: 16,
                          iconSize: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: systemPadding.top + (isLandscape ? 18 : 76),
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_showChrome,
                  child: AnimatedOpacity(
                    opacity: _showChrome ? 1 : 0,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeInOut,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colorScheme.scrim.withValues(
                            alpha: .52,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            context.l10n.profilePhotoCounter(
                              _currentIndex + 1,
                              widget.photos.length,
                            ),
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SystemUiOverlayStyle _overlayStyle(BuildContext context) {
    final transparent = context.scaffoldBackgroundColor.withValues(alpha: 0);
    return SystemUiOverlayStyle(
      statusBarColor: transparent,
      systemNavigationBarColor: transparent,
      systemNavigationBarDividerColor: transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  void _close() {
    if (_canPop) return;
    setState(() {
      _disableHeroes = _currentIndex != widget.initialIndex;
      _canPop = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _precachePhotos() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    for (final photo in widget.photos) {
      final bytes = photo.bytes;
      final url = photo.avatarUrl;
      final ImageProvider? provider = bytes != null
          ? MemoryImage(bytes)
          : url != null && url.isNotEmpty
          ? NetworkImage(url)
          : null;
      if (provider == null) continue;
      await precacheImage(provider, context, onError: (_, _) {});
      if (!mounted) return;
    }
  }

  Future<void> _saveCurrent() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final photo = widget.photos[_currentIndex];
    var success = false;
    try {
      if (photo.bytes != null) {
        success = await MediaService.saveImageBytesToGallery(photo.bytes!);
      } else if (photo.avatarUrl != null) {
        success = await MediaService.saveImageToGallery(photo.avatarUrl!);
      }
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    showAppSnackBar(
      context,
      message: success
          ? context.l10n.photoHasBeenSavedToGallery
          : context.l10n.failedToSavePhoto,
      type: success ? SnackBarType.info : SnackBarType.error,
    );
  }
}

class _ZoomableProfilePhoto extends StatefulWidget {
  const _ZoomableProfilePhoto({
    super.key,
    required this.photo,
    this.initialAspectRatio,
    required this.onZoomChanged,
  });

  final ProfilePhoto photo;
  final double? initialAspectRatio;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableProfilePhoto> createState() => _ZoomableProfilePhotoState();
}

class _ZoomableProfilePhotoState extends State<_ZoomableProfilePhoto> {
  final _controller = TransformationController();
  late double _aspectRatio;

  @override
  void initState() {
    super.initState();
    _aspectRatio = widget.initialAspectRatio ?? 1;
    _controller.addListener(_onTransform);
    if (widget.initialAspectRatio == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resolveAspectRatio(),
      );
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  void _onTransform() {
    widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.01);
  }

  Future<void> _resolveAspectRatio() async {
    final provider = profilePhotoImageProvider(widget.photo);
    if (provider == null) return;
    final value = await resolveImageAspectRatio(context, provider);
    if (mounted && value != null && value > 0) {
      setState(() => _aspectRatio = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 4,
        panEnabled: true,
        boundaryMargin: EdgeInsets.zero,
        clipBehavior: Clip.hardEdge,
        child: Center(
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: ProfilePhotoHero(
              photo: widget.photo,
              borderRadius: 0,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
