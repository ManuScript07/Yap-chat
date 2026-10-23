import 'dart:io';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

import 'widgets.dart';

class ChatMediaHero extends StatefulWidget {
  const ChatMediaHero({
    super.key,
    required this.path,
    required this.heroTag,
    required this.fit,
    this.cacheWidth,
    this.revealOnLoad = true,
    this.onAspectRatio,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.transitionGeometry,
    this.imageKey,
  });

  final String path;
  final String heroTag;
  final BoxFit fit;
  final int? cacheWidth;
  final bool revealOnLoad;
  final ValueChanged<double>? onAspectRatio;
  final BorderRadiusGeometry borderRadius;
  final ChatMediaTransitionGeometry? transitionGeometry;

  /// Keep the gallery's mounted decoder/stream when entering its placeholder.
  /// Never copy this key to the separate flying thumbnail.
  final GlobalKey? imageKey;

  @override
  State<ChatMediaHero> createState() => _ChatMediaHeroState();
}

class _ChatMediaHeroState extends State<ChatMediaHero> {
  GlobalKey? _sourceImageKey;
  final _boundsKey = GlobalKey();
  final _hidden = ValueNotifier(false);
  ChatMediaTransitionGeometry? _geometry;

  void _unregister(ChatMediaHero owner) => _geometry?.localFlight.unregister(
    owner.heroTag,
    _boundsKey,
    gallery: owner.fit == BoxFit.contain,
  );

  void _register() {
    _geometry =
        widget.transitionGeometry ?? ChatMediaTransitionScope.maybeOf(context);
    _geometry?.localFlight.register(
      tag: widget.heroTag,
      key: _boundsKey,
      path: widget.path,
      cacheWidth: widget.cacheWidth,
      radius: widget.borderRadius.resolve(Directionality.of(context)),
      gallery: widget.fit == BoxFit.contain,
      hidden: widget.fit == BoxFit.contain ? null : _hidden,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unregister(widget);
    _register();
  }

  @override
  void didUpdateWidget(ChatMediaHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heroTag != widget.heroTag ||
        oldWidget.fit != widget.fit ||
        oldWidget.transitionGeometry != widget.transitionGeometry) {
      _unregister(oldWidget);
    }
    _register();
  }

  @override
  void dispose() {
    _unregister(widget);
    _hidden.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChatMediaHero(
      :path,
      :heroTag,
      :fit,
      :cacheWidth,
      :revealOnLoad,
      :onAspectRatio,
      :borderRadius,
      :transitionGeometry,
      :imageKey,
    ) = widget;
    final placeholderGeometry =
        transitionGeometry ?? ChatMediaTransitionScope.maybeOf(context);
    // Keep the mounted decoder when Hero reparents its child into a placeholder.
    // Without this, protected source pixels can briefly reveal the bubble below.
    final retainedImageKey =
        imageKey ??
        (placeholderGeometry == null
            ? null
            : (_sourceImageKey ??= GlobalKey()));
    final hero = Hero(
      tag: heroTag,
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: (_, animation, direction, fromContext, toContext) {
        final from = (fromContext.widget as Hero).child as ClipRRect;
        final to = (toContext.widget as Hero).child as ClipRRect;
        final fromRadius = from.borderRadius.resolve(
          Directionality.of(fromContext),
        );
        final toRadius = to.borderRadius.resolve(Directionality.of(toContext));
        // Hero's animation runs backwards on pop. Read the actual matched tile,
        // including after paging to another photo, instead of rounding all corners.
        final radius = BorderRadiusTween(
          begin: direction == HeroFlightDirection.push ? fromRadius : toRadius,
          end: direction == HeroFlightDirection.push ? toRadius : fromRadius,
        ).animate(animation);
        // Reuse the mounted thumbnail in both directions. The gallery may
        // already have requested full resolution without receiving its frame.
        final thumbnail = direction == HeroFlightDirection.push ? from : to;
        final image = thumbnail.child! as ChatMediaImage;
        return AnimatedBuilder(
          animation: radius,
          builder: (context, child) =>
              ClipRRect(borderRadius: radius.value!, child: child),
          child: ColoredBox(
            color: Colors.black,
            child: ChatMediaImage(
              path: image.path,
              fit: BoxFit.cover,
              cacheWidth: image.cacheWidth,
              revealOnLoad: false,
            ),
          ),
        );
      },
      child: ClipRRect(
        key: _boundsKey,
        borderRadius: borderRadius,
        child: ChatMediaImage(
          key: retainedImageKey,
          path: path,
          fit: fit,
          cacheWidth: cacheWidth,
          revealOnLoad: revealOnLoad,
          onAspectRatio: onAspectRatio,
        ),
      ),
    );
    final flight = _geometry?.localFlight;
    if (fit != BoxFit.cover || flight == null) return hero;
    return ValueListenableBuilder<bool>(
      valueListenable: _hidden,
      child: hero,
      builder: (_, hidden, child) =>
          Opacity(opacity: hidden ? 0 : 1, child: child),
    );
  }
}

class ChatMediaImage extends StatefulWidget {
  const ChatMediaImage({
    super.key,
    required this.path,
    required this.fit,
    this.cacheWidth,
    this.revealOnLoad = true,
    this.onAspectRatio,
  });

  final String path;
  final BoxFit fit;
  final int? cacheWidth;
  final bool revealOnLoad;
  final ValueChanged<double>? onAspectRatio;

  @override
  State<ChatMediaImage> createState() => _ChatMediaImageState();
}

class _ChatMediaImageState extends State<ChatMediaImage> {
  ImageProvider<Object>? _provider;
  ImageConfiguration? _configuration;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _observation = 0;
  bool _sizeObserved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateProvider();
  }

  @override
  void didUpdateWidget(covariant ChatMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateProvider();
    if (oldWidget.onAspectRatio != widget.onAspectRatio) {
      final ratio = chatMediaAspectRatios.lookup(widget.path);
      if (ratio != null) _notifyAspectRatio(ratio, _observation);
    }
  }

  void _updateProvider() {
    final provider = chatMediaImageProvider(
      widget.path,
      cacheWidth: widget.cacheWidth,
    );
    final configuration = createLocalImageConfiguration(context);
    if (provider == _provider && configuration == _configuration) return;
    _stopObserving();
    _provider = provider;
    _configuration = configuration;
    _observation++;
    _sizeObserved = false;
    final known = chatMediaAspectRatios.lookup(widget.path);
    if (known != null) {
      _sizeObserved = true;
      _notifyAspectRatio(known, _observation);
    }
  }

  void _captureAspectRatio() {
    if (_sizeObserved) return;
    _sizeObserved = true;
    final observation = _observation;
    // Only inspect after Image has a frame. Its live stream is already cached,
    // so this neither starts a second decode nor bypasses ScrollAwareImageProvider
    // deferral when the user flings through historical media.
    final stream = _provider!.resolve(_configuration!);
    _stream = stream;
    _listener = ImageStreamListener(
      (info, _) {
        try {
          if (observation != _observation) return;
          final ratio = info.image.width / info.image.height;
          chatMediaAspectRatios.remember(widget.path, ratio);
          _notifyAspectRatio(ratio, observation);
          _stopObserving();
        } finally {
          info.dispose();
        }
      },
      onError: (_, _) {
        if (observation == _observation) _stopObserving();
      },
    );
    stream.addListener(_listener!);
  }

  void _notifyAspectRatio(double ratio, int observation) {
    if (widget.onAspectRatio == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && observation == _observation) {
        widget.onAspectRatio?.call(ratio);
      }
    });
  }

  void _stopObserving() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _observation++;
    _stopObserving();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(_, _, _) => ColoredBox(
      color: context.scaffoldBackgroundColor,
      child: Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: context.colorScheme.surface,
          size: 48,
        ),
      ),
    );

    return Image(
      image: _provider!,
      fit: widget.fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) _captureAspectRatio();
        return widget.revealOnLoad
            ? _revealImageFrame(
                context,
                child,
                frame,
                wasSynchronouslyLoaded,
                widget.path,
              )
            : child;
      },
      errorBuilder: errorBuilder,
    );
  }
}

Widget _revealImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
  String path,
) {
  final isReady = wasSynchronouslyLoaded || frame != null;
  final shouldReveal = !_revealedChatMediaPaths.contains(path);
  if (isReady) _rememberRevealedChatMedia(path);
  return AnimatedOpacity(
    opacity: !shouldReveal || isReady ? 1 : 0,
    duration: !shouldReveal || wasSynchronouslyLoaded
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    child: child,
  );
}

const _maxRememberedChatMediaPaths = 512;
final LinkedHashSet<String> _revealedChatMediaPaths = LinkedHashSet<String>();

void _rememberRevealedChatMedia(String path) {
  _revealedChatMediaPaths.remove(path);
  _revealedChatMediaPaths.add(path);
  if (_revealedChatMediaPaths.length > _maxRememberedChatMediaPaths) {
    _revealedChatMediaPaths.remove(_revealedChatMediaPaths.first);
  }
}

ImageProvider<Object> chatMediaImageProvider(String path, {int? cacheWidth}) {
  final ImageProvider<Object> provider;
  if (path.startsWith('http://') || path.startsWith('https://')) {
    provider = NetworkImage(path);
  } else {
    provider = FileImage(File(path));
  }
  return ResizeImage.resizeIfNeeded(cacheWidth, null, provider);
}
