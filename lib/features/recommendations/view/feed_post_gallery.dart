import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/feed/feed.dart';
import 'package:yap_chat/ui/ui.dart';

Future<void> openFeedGallery(
  BuildContext context, {
  required FeedCubit timeline,
  required FeedPost post,
  required int index,
  required Object heroTag,
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
  final image = preview.clone();
  final accounts = context.read<AccountSessionController?>();
  final allowed = ValueNotifier(true);
  void checkAccess() {
    if (!actions.canShow(post)) allowed.value = false;
  }

  accounts?.generationChanges.addListener(checkAccess);
  final subscription = actions.stream.listen((_) => checkAccess());
  final route = MaterialPageRoute<void>(
    builder: (_) => _FeedPostGallery(
      timeline: timeline,
      post: post,
      repository: repository as IFeedPublicationRepository,
      initialIndex: index,
      heroTag: heroTag,
      preview: image,
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
    image.dispose();
  }
}

class _FeedPostGallery extends StatefulWidget {
  const _FeedPostGallery({
    required this.timeline,
    required this.post,
    required this.repository,
    required this.initialIndex,
    required this.heroTag,
    required this.preview,
    required this.allowed,
  });

  final FeedCubit timeline;
  final FeedPost post;
  final IFeedPublicationRepository repository;
  final int initialIndex;
  final Object heroTag;
  final ui.Image preview;
  final ValueListenable<bool> allowed;

  @override
  State<_FeedPostGallery> createState() => _FeedPostGalleryState();
}

class _FeedPostGalleryState extends State<_FeedPostGallery> {
  late int _index = widget.initialIndex;
  late final _pages = PageController(initialPage: _index);
  final _transform = TransformationController();
  Animation<double>? _animation;
  ui.Image? _image;
  Uint8List? _encoded;
  int _loadGeneration = 0;
  bool _failed = false;
  bool _saving = false;
  bool _zoomed = false;
  bool _showControls = true;

  bool get _allowed =>
      widget.allowed.value && widget.timeline.actions!.canShow(widget.post);
  bool get _settled => _animation?.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    widget.allowed.addListener(_accessChanged);
    _transform.addListener(_zoomChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _animation)) return;
    _animation?.removeStatusListener(_routeChanged);
    _animation = animation?..addStatusListener(_routeChanged);
    if (_settled) _routeChanged(AnimationStatus.completed);
  }

  void _routeChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _allowed && _settled) unawaited(_load());
    });
  }

  void _accessChanged() {
    if (_allowed) return;
    _loadGeneration++;
    _image?.dispose();
    _encoded = null;
    setState(() => _image = null);
  }

  void _zoomChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _select(int index) {
    _loadGeneration++;
    _image?.dispose();
    _encoded = null;
    _transform.value = Matrix4.identity();
    setState(() {
      _index = index;
      _failed = false;
      _image = null;
    });
    if (_settled) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final photo = widget.post.photos[_index];
    final timeline = widget.timeline;
    final viewport = MediaQuery.sizeOf(context);
    final pixels = MediaQuery.devicePixelRatioOf(context);
    final maxSide = (viewport.longestSide * pixels * 1.5).ceil().clamp(1, 2560);
    bool current() =>
        mounted &&
        _allowed &&
        timeline.isCurrentAccount() &&
        _settled &&
        generation == _loadGeneration;
    try {
      final bytes = await widget.repository.downloadPhoto(
        photo,
        account: timeline.account,
        stillNeeded: current,
      );
      if (!current()) return;
      final ratio = photo.aspectRatio;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: ratio != null && ratio >= 1 ? maxSide : null,
        targetHeight: ratio != null && ratio < 1 ? maxSide : null,
        allowUpscaling: false,
      );
      try {
        if (!current()) return;
        final frame = await codec.getNextFrame();
        if (!current()) {
          frame.image.dispose();
          return;
        }
        _image?.dispose();
        setState(() {
          _image = frame.image;
          _encoded = bytes;
        });
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (current()) setState(() => _failed = true);
    }
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
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: context.colorScheme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
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
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _showControls = !_showControls),
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
                if (_showControls)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(bottom: false, child: _header(context)),
                  ),
              ],
            ),
    ),
  );

  Widget _buildPhoto(int index) {
    final initial = index == widget.initialIndex;
    final selected = index == _index;
    final image =
        (selected ? _image : null) ?? (initial ? widget.preview : null);
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
        final ratio = photo.aspectRatio ?? image.width / image.height;
        final size = applyBoxFit(
          BoxFit.contain,
          Size(ratio, 1),
          constraints.biggest,
        ).destination;
        final framed = SizedBox.fromSize(
          size: size,
          child: RawImage(image: image, fit: BoxFit.contain),
        );
        final content = initial && selected && !_zoomed
            ? Hero(
                tag: widget.heroTag,
                flightShuttleBuilder: (_, animation, _, _, _) =>
                    ValueListenableBuilder(
                      valueListenable: widget.allowed,
                      builder: (context, allowed, _) => allowed
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(
                                8 * (1 - animation.value),
                              ),
                              child: RawImage(
                                image: widget.preview,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const SizedBox.expand(),
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

  Widget _back(BuildContext context) => Tooltip(
    message: MaterialLocalizations.of(context).backButtonTooltip.toLowerCase(),
    child: GlassIconButton(
      icon: Icons.arrow_back_rounded,
      onTap: () => Navigator.of(context).maybePop(),
    ),
  );

  Widget _header(BuildContext context) {
    final post = widget.post;
    final path = post.avatarPath;
    final repository = widget.timeline.repository;
    return ColoredBox(
      color: context.scaffoldBackgroundColor.withValues(alpha: .82),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            _back(context),
            const SizedBox(width: 8),
            UserAvatar(
              size: 40,
              avatarUrl: path == null ? post.avatarUrl : null,
              avatarRevision: post.avatarRevision,
              preferAvatarLoader: path != null,
              avatarLoader: path != null && repository is FeedRepository
                  ? () => repository.loadAvatar(path, widget.timeline.account)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.authorName ?? context.l10n.feedUnknownAuthor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleMedium,
                  ),
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(post.createdAt.toLocal()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (post.photos.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_index + 1}/${post.photos.length}',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            IconButton(
              tooltip: context.l10n.feedSavePhoto,
              color: context.colorScheme.onSurface,
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.allowed.removeListener(_accessChanged);
    _animation?.removeStatusListener(_routeChanged);
    _pages.dispose();
    _transform.dispose();
    _image?.dispose();
    super.dispose();
  }
}
