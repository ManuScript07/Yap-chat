import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yap_chat/core/core.dart';

import 'animated_unread_badge.dart';
import 'floating_navigation_geometry.dart';

class FloatingNavigationBar extends StatefulWidget {
  const FloatingNavigationBar({
    super.key,
    required this.activeIndex,
    required this.onTap,
    required this.items,
    this.itemWidth = 52,
    this.horizontalPadding = 12,
    this.itemSpacing = 6,
    this.iconTextSpacing = 3,
    this.bottomOffset = FloatingNavigationGeometry.bottomOffset,
  }) : assert(items.length > 0),
       assert(activeIndex >= 0 && activeIndex < items.length);

  final int activeIndex;
  final ValueChanged<int> onTap;
  final List<FloatingNavigationBarItem> items;
  final double itemWidth, itemSpacing, horizontalPadding, iconTextSpacing;
  final double bottomOffset;

  @override
  State<FloatingNavigationBar> createState() => _FloatingNavigationBarState();
}

class _FloatingNavigationBarState extends State<FloatingNavigationBar>
    with SingleTickerProviderStateMixin {
  static final _blur = ImageFilter.blur(sigmaX: 12, sigmaY: 12);
  static const _restingGlow = .09;
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
    value: 1,
  );
  late Animation<double> _glow = _glowFrom(_restingGlow);

  Animation<double> _glowFrom(double begin) => TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: begin,
        end: .22,
      ).chain(CurveTween(curve: Curves.easeInOutSine)),
      weight: 400,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: .22,
        end: _restingGlow,
      ).chain(CurveTween(curve: Curves.easeInOutSine)),
      weight: 1100,
    ),
  ]).animate(_pulse);

  void _activate({bool repeat = false}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 1;
    } else {
      // Repeated taps continue from the currently visible intensity instead
      // of dropping to the resting level and producing another flash.
      _glow = _glowFrom(repeat ? _glow.value : _restingGlow);
      _pulse.forward(from: 0);
    }
  }

  void _select(int index) {
    if (widget.activeIndex == index) _activate(repeat: true);
    widget.onTap(index);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _pulse.isAnimating) {
      _pulse.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant FloatingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) _activate();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final activeIndex = widget.activeIndex;
    final horizontalPadding = widget.horizontalPadding;
    final itemWidth = widget.itemWidth;
    final itemSpacing = widget.itemSpacing;
    final iconTextSpacing = widget.iconTextSpacing;
    final bottomOffset = widget.bottomOffset;
    final media = MediaQuery.of(context);
    final safeLeft = math.max(media.padding.left, media.viewPadding.left);
    final safeRight = math.max(media.padding.right, media.viewPadding.right);
    final outside = media.orientation == Orientation.landscape ? 0.0 : 16.0;
    final foreground = context.colorScheme.onSurface;
    final background = context.scaffoldBackgroundColor;
    final idealWidth =
        items.length * itemWidth +
        math.max(0, items.length - 1) * itemSpacing +
        horizontalPadding * 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        safeLeft + outside,
        0,
        safeRight + outside,
        FloatingNavigationGeometry.systemBottom(media) + bottomOffset,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: idealWidth),
          child: SizedBox(
            height: FloatingNavigationGeometry.heightFor(media),
            child: CustomPaint(
              key: const ValueKey('navigation_surface'),
              foregroundPainter: _NavigationRimPainter(foreground),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                clipBehavior: Clip.antiAlias,
                child: BackdropFilter(
                  filter: _blur,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.alphaBlend(
                            foreground.withValues(alpha: .035),
                            background.withValues(alpha: .94),
                          ),
                          background.withValues(alpha: .94),
                        ],
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Paint on the full pill, underneath ALL destinations.
                        // A tab-sized layer would cut the halo at its edges.
                        RepaintBoundary(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, _) => AnimatedSwitcher(
                                duration: media.disableAnimations
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                child: CustomPaint(
                                  key: ValueKey(activeIndex),
                                  painter: _NavigationGlowPainter(
                                    foreground.withValues(alpha: _glow.value),
                                    activeIndex,
                                    items.length,
                                    horizontalPadding,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: Row(
                            children: [
                              for (var index = 0; index < items.length; index++)
                                Expanded(
                                  child: _NavigationDestination(
                                    key: ValueKey(
                                      'navigation_destination_$index',
                                    ),
                                    selected: activeIndex == index,
                                    item: items[index],
                                    iconTextSpacing: iconTextSpacing,
                                    onTap: () => _select(index),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    super.key,
    required this.selected,
    required this.item,
    required this.iconTextSpacing,
    required this.onTap,
  });
  final bool selected;
  final FloatingNavigationBarItem item;
  final double iconTextSpacing;
  final VoidCallback onTap;

  void _handleTap() {
    HapticFeedback.lightImpact();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final foreground = context.colorScheme.onSurface;
    return Semantics(
      button: true,
      onTap: _handleTap,
      selected: selected,
      label: item.label,
      value: item.unreadCount > 0 ? '${item.unreadCount}' : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: selected ? foreground : context.colorScheme.outline,
                ),
                duration: duration,
                builder: (context, color, _) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 30,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          if (item.iconBuilder case final builder?)
                            builder(context, selected, color!)
                          else if (item.iconAsset case final asset?)
                            SvgPicture.asset(
                              selected ? item.activeIconAsset! : asset,
                              width: 26,
                              height: 26,
                              colorFilter: ColorFilter.mode(
                                color!,
                                BlendMode.srcIn,
                              ),
                            )
                          else
                            Icon(
                              selected ? item.activeIcon! : item.icon!,
                              size: 26,
                              color: color,
                            ),
                          Positioned(
                            right: -7,
                            top: -4,
                            child: MediaQuery.withClampedTextScaling(
                              maxScaleFactor: 1,
                              child: AnimatedUnreadBadge(
                                count: item.unreadCount,
                                color: context.colorScheme.primary,
                                textColor: context.scaffoldBackgroundColor,
                                size: 20,
                                textStyle: const TextStyle(
                                  fontFamily: 'RobotoFlex',
                                  fontWeight: FontWeight.w800,
                                  fontVariations: [FontVariation('wght', 800)],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: iconTextSpacing),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'RobotoFlex',
                            fontSize: 12,
                            height: 1.1,
                            letterSpacing: .4,
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                            color: color,
                          ),
                        ),
                      ),
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

class _NavigationGlowPainter extends CustomPainter {
  const _NavigationGlowPainter(
    this.color,
    this.index,
    this.count,
    this.horizontalPadding,
  );

  final Color color;
  final int index, count;
  final double horizontalPadding;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final itemWidth = (size.width - horizontalPadding * 2) / count;
    final center = Offset(
      horizontalPadding + itemWidth * (index + .5),
      size.height / 2,
    );
    final radius = size.height * .95;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_NavigationGlowPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.index != index ||
      oldDelegate.count != count ||
      oldDelegate.horizontalPadding != horizontalPadding;
}

class _NavigationRimPainter extends CustomPainter {
  const _NavigationRimPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(.5);
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: .28),
          color.withValues(alpha: .15),
          color.withValues(alpha: .08),
        ],
        stops: const [0, .45, 1],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_NavigationRimPainter oldDelegate) =>
      oldDelegate.color != color;
}

class FloatingNavigationBarItem {
  const FloatingNavigationBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.unreadCount = 0,
  }) : iconAsset = null,
       activeIconAsset = null,
       iconBuilder = null;
  const FloatingNavigationBarItem.asset({
    required this.iconAsset,
    required this.activeIconAsset,
    required this.label,
    this.unreadCount = 0,
  }) : icon = null,
       activeIcon = null,
       iconBuilder = null;
  const FloatingNavigationBarItem.custom({
    required this.iconBuilder,
    required this.label,
    this.unreadCount = 0,
  }) : icon = null,
       activeIcon = null,
       iconAsset = null,
       activeIconAsset = null;
  final IconData? icon, activeIcon;
  final String? iconAsset, activeIconAsset;
  final Widget Function(BuildContext, bool, Color)? iconBuilder;
  final String label;
  final int unreadCount;
}
