import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:yap_chat/core/core.dart';

Future<Uint8List?> openProfilePhotoCropper(
  BuildContext context,
  Uint8List sourceBytes,
) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProfilePhotoCropPage(sourceBytes: sourceBytes),
    ),
  );
}

class ProfilePhotoCropPage extends StatefulWidget {
  const ProfilePhotoCropPage({super.key, required this.sourceBytes});

  final Uint8List sourceBytes;

  @override
  State<ProfilePhotoCropPage> createState() => _ProfilePhotoCropPageState();
}

class _ProfilePhotoCropPageState extends State<ProfilePhotoCropPage> {
  final _boundaryKey = GlobalKey();
  final _transformationController = TransformationController();
  ui.Image? _decodedImage;
  double? _configuredViewport;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _decode();
  }

  Future<void> _decode() async {
    final image = await decodeImageFromList(widget.sourceBytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _decodedImage = image);
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    _transformationController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle(context),
      child: Scaffold(
        backgroundColor: context.scaffoldBackgroundColor,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final systemPadding = MediaQuery.paddingOf(context);
            final contentHeight =
                constraints.maxHeight -
                systemPadding.top -
                systemPadding.bottom;
            final viewport = (constraints.maxWidth - 32).clamp(
              220.0,
              (contentHeight - 112).clamp(220.0, 520.0),
            );
            final cropRect = Rect.fromCenter(
              center: Offset(
                constraints.maxWidth / 2,
                systemPadding.top + contentHeight / 2,
              ),
              width: viewport,
              height: viewport,
            );
            final image = _decodedImage;
            if (image != null && _configuredViewport != viewport) {
              _configuredViewport = viewport;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _centerImage(viewport, image);
              });
            }

            return Stack(
              children: [
                Positioned.fill(
                  top: systemPadding.top,
                  bottom: systemPadding.bottom,
                  child: Center(
                    child: image == null
                        ? CircularProgressIndicator(color: colorScheme.primary)
                        : _cropViewport(viewport, image),
                  ),
                ),
                if (image != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CropOverlayPainter(
                          cropRect: cropRect,
                          overlayColor: colorScheme.scrim.withValues(
                            alpha: .68,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: systemPadding.left + 16,
                  right: systemPadding.right + 16,
                  bottom: systemPadding.bottom + 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(
                          context.l10n.cancel.toLowerCase(),
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .4,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: image == null || _isSaving ? null : _save,
                        child: _isSaving
                            ? SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.colorScheme.primary,
                                ),
                              )
                            : Text(
                                context.l10n.profileCropApply.toLowerCase(),
                                style: TextStyle(
                                  color: context.colorScheme.primary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .4,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cropViewport(double viewport, ui.Image image) {
    final ratio = image.width / image.height;
    final childWidth = ratio >= 1 ? viewport * ratio : viewport;
    final childHeight = ratio >= 1 ? viewport : viewport / ratio;
    return RepaintBoundary(
      key: _boundaryKey,
      child: SizedBox.square(
        dimension: viewport,
        child: InteractiveViewer(
          transformationController: _transformationController,
          constrained: false,
          minScale: 1,
          maxScale: 4,
          boundaryMargin: EdgeInsets.zero,
          clipBehavior: Clip.none,
          child: Image.memory(
            widget.sourceBytes,
            width: childWidth,
            height: childHeight,
            fit: BoxFit.fill,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }

  void _centerImage(double viewport, ui.Image image) {
    final ratio = image.width / image.height;
    final childWidth = ratio >= 1 ? viewport * ratio : viewport;
    final childHeight = ratio >= 1 ? viewport : viewport / ratio;
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(
        (viewport - childWidth) / 2,
        (viewport - childHeight) / 2,
        0,
        1,
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

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final viewport = boundary.size.width;
      final image = await boundary.toImage(pixelRatio: 1440 / viewport);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted || byteData == null) return;
      Navigator.of(context).pop(byteData.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.cropRect,
    required this.overlayColor,
  });

  final Rect cropRect;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final crop = RRect.fromRectAndRadius(cropRect, const Radius.circular(24));
    final outside = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(crop);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outside, hole),
      Paint()..color = overlayColor,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect ||
      oldDelegate.overlayColor != overlayColor;
}
