import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/features/recommendations/data/feed_media_frames.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

const feedPhotoPreviewRadius = 16.0;

// A valid file may have a one-pixel short edge. Keep that edge visible even
// when fitting the long edge would make it smaller than one screen pixel.
double feedPhotoDisplayRatio(double ratio, Size viewport, double pixelRatio) {
  if (viewport.isEmpty) return ratio;
  final minRatio = 1 / (viewport.height * pixelRatio);
  final maxRatio = viewport.width * pixelRatio;
  return minRatio <= maxRatio ? ratio.clamp(minRatio, maxRatio) : ratio;
}

/// The thumbnail codec rounds its shorter side to whole pixels. Use the
/// prepared full image's aspect ratio for both ends of the flight.
Widget feedPhotoFrame(ui.Image image, double ratio, BoxFit fit) {
  if (ratio == image.width / image.height) {
    return RawImage(image: image, fit: fit);
  }
  return FittedBox(
    fit: fit,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(
      width: ratio * image.height,
      height: image.height.toDouble(),
      child: RawImage(image: image, fit: BoxFit.fill),
    ),
  );
}

Future<void> openFeedGallery(
  BuildContext context, {
  required FeedCubit timeline,
  required FeedPost post,
  required int index,
  required Object heroTag,
  List<Object>? heroTags,
  required ui.Image preview,
}) async {
  final actions = timeline.actions;
  final repository = timeline.repository;
  if (actions == null ||
      !actions.canShow(post) ||
      repository is! IFeedPublicationRepository ||
      ModalRoute.isCurrentOf(context) == false) {
    return;
  }
  final previews = <int, ui.Image>{index: preview.clone()};
  for (final (position, photo) in post.photos.indexed) {
    if (position == index) continue;
    final thumbnail = actions.thumbnailFrames.findPreview(
      post,
      photo.thumbnailPath,
    );
    if (thumbnail != null) previews[position] = thumbnail;
  }
  final accounts = context.read<AccountSessionController?>();
  final allowed = ValueNotifier(true);
  void releasePreviews() {
    for (final image in previews.values) {
      image.dispose();
    }
    previews.clear();
  }

  void checkAccess() {
    if (!allowed.value || actions.canShow(post)) return;
    allowed.value = false;
    releasePreviews();
  }

  accounts?.generationChanges.addListener(checkAccess);
  final subscription = actions.stream.listen((_) => checkAccess());
  late final MediaGalleryRoute route;
  route = MediaGalleryRoute(
    separateBackground: true,
    pageBuilder: (_, _, _) => _FeedPostGallery(
      timeline: timeline,
      post: post,
      repository: repository as IFeedPublicationRepository,
      initialIndex: index,
      heroTag: heroTag,
      heroTags: heroTags,
      animation: route.mediaAnimation,
      previews: previews,
      allowed: allowed,
    ),
  );
  try {
    // Use the navigator owning the source Hero.
    await Navigator.of(context).push(route);
    await route.completed;
  } finally {
    accounts?.generationChanges.removeListener(checkAccess);
    await subscription.cancel();
    allowed.dispose();
    releasePreviews();
  }
}

class _FeedPostGallery extends StatefulWidget {
  const _FeedPostGallery({
    required this.timeline,
    required this.post,
    required this.repository,
    required this.initialIndex,
    required this.heroTag,
    required this.heroTags,
    required this.animation,
    required this.previews,
    required this.allowed,
  });

  final FeedCubit timeline;
  final FeedPost post;
  final IFeedPublicationRepository repository;
  final int initialIndex;
  final Object heroTag;
  final List<Object>? heroTags;
  final Animation<double> animation;
  final Map<int, ui.Image> previews;
  final ValueListenable<bool> allowed;

  @override
  State<_FeedPostGallery> createState() => _FeedPostGalleryState();
}

class _FeedPostGalleryState extends State<_FeedPostGallery>
    with SingleTickerProviderStateMixin {
  late int _index = widget.initialIndex;
  late final _pages = PageController(initialPage: _index);
  final _transform = TransformationController();
  AnimationController? _closeMotion;
  final _frames = <int, ui.Image>{};
  static const _frameBudget = 32 * 1024 * 1024;
  var _frameBytes = 0;
  Uint8List? _encoded;
  int _loadGeneration = 0;
  bool _failed = false;
  bool _saving = false;
  bool _zoomed = false;
  bool _showControls = true;
  bool _closing = false;
  bool _canPop = false;

  bool get _allowed =>
      widget.allowed.value && widget.timeline.actions!.canShow(widget.post);
  bool get _settled => widget.animation.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    widget.allowed.addListener(_accessChanged);
    _transform.addListener(_zoomChanged);
    widget.animation.addStatusListener(_routeChanged);
    if (_settled) _routeChanged(AnimationStatus.completed);
  }

  void _routeChanged(AnimationStatus status) {
    if (mounted) setState(() {});
    if (status != AnimationStatus.completed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_closing &&
          _allowed &&
          _settled &&
          !_frames.containsKey(_index)) {
        unawaited(_load());
      }
    });
  }

  void _accessChanged() {
    if (_allowed) return;
    _loadGeneration++;
    _encoded = null;
    setState(_clearFrames);
  }

  void _zoomChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _select(int index) {
    _loadGeneration++;
    _encoded = null;
    _transform.value = Matrix4.identity();
    setState(() {
      _index = index;
      _failed = false;
      final existing = _frames.remove(index);
      if (existing != null) _frames[index] = existing;
    });
    if (_settled && !_closing && !_frames.containsKey(index)) {
      unawaited(_load());
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    final navigator = Navigator.of(context);
    final fitted = Matrix4.identity();
    final recenter = _allowed && _transform.value != fitted;
    final fadeChrome = _allowed && _settled && _showControls;
    setState(() => _closing = true);
    if (recenter || fadeChrome) {
      final motion = _closeMotion ??= AnimationController(
        vsync: this,
        duration: MediaGalleryChromeVisibility.animationDuration,
      );
      final zoom = recenter
          ? Matrix4Tween(begin: _transform.value.clone(), end: fitted)
          : null;
      void tick() {
        if (zoom == null) return;
        _transform.value = zoom.transform(
          Curves.easeInOut.transform(motion.value),
        );
      }

      motion.addListener(tick);
      try {
        await motion.forward().orCancel;
      } on TickerCanceled {
        return;
      } finally {
        if (mounted) motion.removeListener(tick);
      }
    }
    if (!mounted) return;
    if (recenter) _transform.value = fitted;
    setState(() => _canPop = true);
    // Lay out the fitted endpoint before Navigator measures the reverse Hero.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && ModalRoute.isCurrentOf(context) == true) navigator.pop();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final index = _index;
    final photo = widget.post.photos[index];
    final timeline = widget.timeline;
    final viewport = MediaQuery.sizeOf(context);
    final pixels = MediaQuery.devicePixelRatioOf(context);
    final maxSide = (viewport.longestSide * pixels * 1.5).ceil().clamp(1, 2560);
    bool current() =>
        mounted &&
        !_closing &&
        _allowed &&
        timeline.isCurrentAccount() &&
        _settled &&
        generation == _loadGeneration;
    try {
      final bytes = await widget.repository.downloadPhoto(
        photo,
        post: widget.post,
        account: timeline.account,
        stillNeeded: current,
      );
      if (!current()) return;
      final image = await decodeFeedFrame(bytes, maxSide);
      if (!current()) {
        image.dispose();
        return;
      }
      setState(() {
        _dropFrame(index);
        _frames[index] = image;
        _frameBytes += image.width * image.height * 4;
        while (_frames.length > 1 &&
            (_frameBytes > _frameBudget || _frames.length > 3)) {
          _dropFrame(_frames.keys.first);
        }
        _encoded = bytes;
      });
    } catch (_) {
      if (current()) setState(() => _failed = true);
    }
  }

  void _dropFrame(int index) {
    final image = _frames.remove(index);
    if (image == null) return;
    _frameBytes -= image.width * image.height * 4;
    image.dispose();
  }

  void _clearFrames() {
    for (final image in _frames.values) {
      image.dispose();
    }
    _frames.clear();
    _frameBytes = 0;
  }

  Future<void> _save() async {
    if (_saving || !_allowed || !_settled) return;
    final photo = widget.post.photos[_index];
    final timeline = widget.timeline;
    bool current() => mounted && _allowed && timeline.isCurrentAccount();
    setState(() => _saving = true);
    var saved = false;
    try {
      final bytes =
          _encoded ??
          await widget.repository.downloadPhoto(
            photo,
            post: widget.post,
            account: timeline.account,
            stillNeeded: current,
          );
      if (!current()) return;
      saved = await MediaService.saveImageBytesToGallery(bytes);
    } catch (_) {
      // The save button remains available for another attempt.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted || !current()) return;
    showAppSnackBar(
      context,
      message:
          (saved
                  ? context.l10n.photoHasBeenSavedToGallery
                  : context.l10n.failedToSavePhoto)
              .toLowerCase(),
      type: saved ? SnackBarType.info : SnackBarType.error,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.colorScheme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: !_allowed
            ? SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _back(context),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          context.l10n.feedPostUnavailable,
                          style: context.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    ignoring: _closing,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _showControls = !_showControls),
                      child: InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 4,
                        panEnabled: _zoomed,
                        child: PageView.builder(
                          controller: _pages,
                          itemCount: widget.post.photos.length,
                          onPageChanged: _select,
                          physics: _zoomed
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          itemBuilder: (context, index) => _buildPhoto(index),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 16,
                    left: MediaQuery.paddingOf(context).left + 16,
                    right: MediaQuery.paddingOf(context).right + 16,
                    child: MediaGalleryChromeVisibility(
                      settled: _settled,
                      visible: _showControls && !_closing,
                      child: _header(context),
                    ),
                  ),
                  if (widget.post.photos.length > 1) _counter(context),
                ],
              ),
      ),
    ),
  );

  Widget _buildPhoto(int index) {
    final initial = index == widget.initialIndex;
    final selected = index == _index;
    final preview = widget.previews[index];
    final image = _frames[index] ?? preview;
    final retry = selected && _failed
        ? TextButton(
            onPressed: () {
              setState(() => _failed = false);
              unawaited(_load());
            },
            child: Text(context.l10n.feedRetry),
          )
        : null;
    if (image == null) {
      return Center(child: retry ?? const CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final photo = widget.post.photos[index];
        final ratio = feedPhotoDisplayRatio(
          photo.aspectRatio ?? image.width / image.height,
          constraints.biggest,
          MediaQuery.devicePixelRatioOf(context),
        );
        final size = applyBoxFit(
          BoxFit.contain,
          Size(ratio, 1),
          constraints.biggest,
        ).destination;
        final framed = SizedBox.fromSize(
          size: size,
          child: feedPhotoFrame(image, ratio, BoxFit.contain),
        );
        final heroTag =
            widget.heroTags?[index] ?? (initial ? widget.heroTag : null);
        final content = heroTag != null && selected
            ? Hero(
                tag: heroTag,
                curve: Curves.linear,
                reverseCurve: Curves.linear,
                createRectTween: (begin, end) =>
                    RectTween(begin: begin, end: end),
                flightShuttleBuilder: (_, animation, direction, _, _) =>
                    ValueListenableBuilder(
                      valueListenable: widget.allowed,
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (_, child) => ClipRRect(
                          key: const ValueKey('feed-gallery-flight'),
                          borderRadius: BorderRadius.circular(
                            feedPhotoPreviewRadius * (1 - animation.value),
                          ),
                          child: child,
                        ),
                        child: feedPhotoFrame(
                          direction == HeroFlightDirection.push
                              ? preview ?? image
                              : image,
                          ratio,
                          BoxFit.cover,
                        ),
                      ),
                      builder: (context, allowed, child) =>
                          allowed ? child! : const SizedBox.expand(),
                    ),
                child: framed,
              )
            : framed;
        final viewer = Center(child: content);
        return retry == null
            ? viewer
            : Stack(alignment: Alignment.center, children: [viewer, retry]);
      },
    );
  }

  String _backLabel(BuildContext context) =>
      MaterialLocalizations.of(context).backButtonTooltip.toLowerCase();

  Widget _back(BuildContext context) => Tooltip(
    message: _backLabel(context),
    child: MediaGalleryHeader.backButton(_close),
  );

  Widget _header(BuildContext context) {
    final post = widget.post;
    final path = post.avatarPath;
    final repository = widget.timeline.repository;
    return MediaGalleryHeader(
      name: post.authorName ?? context.l10n.feedUnknownAuthor,
      date: DateFormat(
        'd MMMM yyyy',
        Localizations.localeOf(context).toString(),
      ).format(post.createdAt.toLocal()),
      avatar: UserAvatar(
        size: MediaGalleryHeader.buttonSize,
        avatarUrl: path == null ? post.avatarUrl : null,
        avatarRevision: path ?? post.avatarUrl ?? post.avatarRevision,
        preferAvatarLoader: path != null,
        avatarLoader: path != null && repository is FeedRepository
            ? () => repository.loadAvatar(path, widget.timeline.account)
            : null,
      ),
      onBack: _close,
      onSave: _save,
      backLabel: _backLabel(context),
      saveLabel: context.l10n.feedSavePhoto,
    );
  }

  Widget _counter(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      top:
          media.padding.top +
          (media.orientation == Orientation.landscape ? 18 : 76),
      left: 0,
      right: 0,
      child: MediaGalleryChromeVisibility(
        settled: _settled,
        visible: _showControls && !_closing,
        child: IgnorePointer(
          child: MediaGalleryCounter(
            index: _index,
            total: widget.post.photos.length,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.allowed.removeListener(_accessChanged);
    widget.animation.removeStatusListener(_routeChanged);
    _pages.dispose();
    _closeMotion?.dispose();
    _transform.dispose();
    _clearFrames();
    super.dispose();
  }
}
