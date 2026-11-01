import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/widgets/profile_setup_widgets.dart';
import 'package:yap_chat/features/blocks/blocks.dart';
import 'package:yap_chat/features/nearby/bloc/bloc.dart';
import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/features/presence/presence.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/repositories/chat/abstract_location_repository.dart';
import 'package:yap_chat/repositories/nearby/nearby.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class NearbyPeoplePage extends StatefulWidget {
  const NearbyPeoplePage({super.key});

  @override
  State<NearbyPeoplePage> createState() => _NearbyPeoplePageState();
}

class _NearbyPeoplePageState extends State<NearbyPeoplePage> {
  final _scrollController = ScrollController();
  var _locationPromptedAutomatically = false;
  var _isPullRefreshing = false;
  NearbyFilters _presentedFilters = const NearbyFilters();
  int _presentedFeedRevision = 0;
  Timer? _quotaPageRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<NearbyCubit>().initialize());
    });
  }

  @override
  void dispose() {
    _quotaPageRetry?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll({bool allowQuotaRetry = true}) {
    if (!_scrollController.hasClients || (_quotaPageRetry?.isActive ?? false)) {
      return;
    }
    final nearby = context.read<NearbyCubit>();
    final state = nearby.state;
    // An empty viewport is always at its bottom edge. It must not turn that
    // layout detail into an automatic pagination request, especially while a
    // pull-to-refresh is already fetching the first page.
    if (state.isRefreshing ||
        state.isLoadingMore ||
        (state.people.isEmpty && !nearby.needsHeadRefresh) ||
        (!state.hasMore && !nearby.needsHeadRefresh) ||
        state.status != NearbyStatus.ready) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      final filters = state.filters;
      final revision = state.feedRevision;
      unawaited(
        nearby.loadMore().then((_) {
          if (!allowQuotaRetry) return;
          if (!mounted ||
              !identical(context.read<NearbyCubit>(), nearby) ||
              nearby.state.filters != filters ||
              nearby.state.feedRevision != revision) {
            return;
          }
          final delay = nearby.paginationQuotaRetryDelay;
          if (delay == null ||
              (!nearby.state.hasMore && !nearby.needsHeadRefresh)) {
            return;
          }
          _quotaPageRetry?.cancel();
          _quotaPageRetry = Timer(delay + const Duration(milliseconds: 50), () {
            _quotaPageRetry = null;
            if (!mounted ||
                !identical(context.read<NearbyCubit>(), nearby) ||
                nearby.state.filters != filters ||
                nearby.state.feedRevision != revision ||
                !TickerMode.valuesOf(context).enabled ||
                !Visibility.of(context)) {
              return;
            }
            final lifecycle = WidgetsBinding.instance.lifecycleState;
            if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
              return;
            }
            _onScroll(allowQuotaRetry: false);
          });
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<NearbyCubit, NearbyState>(
      listenWhen: (previous, current) =>
          previous.visibilityFeedbackId != current.visibilityFeedbackId ||
          previous.locationFeedbackId != current.locationFeedbackId &&
              current.locationIssue != null,
      listener: (context, state) {
        if (state.locationIssue != null) {
          _showLocationIssue(state.locationIssue!);
        }
        if (state.visibilityFeedbackId > 0) {
          showAppSnackBar(
            context,
            message: context.l10n.nearbyVisibilitySaveFailed,
            type: SnackBarType.error,
          );
        }
      },
      child: BlocConsumer<NearbyCubit, NearbyState>(
        listenWhen: (previous, current) =>
            previous.filters != current.filters ||
            previous.feedRevision != current.feedRevision ||
            (previous.status != current.status &&
                current.status == NearbyStatus.locationRequired &&
                previous.status != NearbyStatus.visibilityDisabled &&
                current.locationIssue == null),
        listener: (context, state) {
          if (_presentedFilters != state.filters ||
              _presentedFeedRevision != state.feedRevision) {
            _presentedFilters = state.filters;
            _presentedFeedRevision = state.feedRevision;
            _quotaPageRetry?.cancel();
            _quotaPageRetry = null;
            // Let the existing top-edge spring finish naturally during a pull.
            // A forced jump from a negative offset interrupts that animation.
            if (_scrollController.hasClients && _scrollController.offset > 0) {
              _scrollController.jumpTo(0);
            }
          }
          if (state.status != NearbyStatus.locationRequired) return;
          if (_locationPromptedAutomatically) return;
          _locationPromptedAutomatically = true;
          unawaited(_requestInitialLocation());
        },
        builder: (context, state) {
          final mediaQuery = MediaQuery.of(context);
          const controlHeight = 50.0;
          final filterBottom =
              FloatingNavigationGeometry.occupiedHeight(mediaQuery) +
              FloatingNavigationGeometry.controlSpacing;
          final contentBottom = filterBottom + controlHeight + 20;
          final blockedUserIds = context.select<BlocklistCubit, Set<String>>(
            (cubit) => cubit.state.blockedUserIds,
          );
          final hasVisiblePeople = state.people.any(
            (person) => !blockedUserIds.contains(person.id),
          );
          final shouldShowEmptyState =
              !hasVisiblePeople &&
              !state.isRefreshing &&
              state.status != NearbyStatus.initial &&
              state.status != NearbyStatus.loading &&
              !state.shouldObscureContent;

          return PresenceWatchScope(
            scopeName: 'nearby',
            userIds: state.people
                .where((person) => !blockedUserIds.contains(person.id))
                .map((person) => person.id),
            child: Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: context.scaffoldBackgroundColor,
              appBar: PrimaryAppBar(
                title: context.l10n.nearbyTitle,
                titleWidget: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.nearbyTitle,
                    style: AppTextStyles.titleLargeFlex,
                  ),
                ),
              ),
              body: Stack(
                children: [
                  _NearbyFeed(
                    controller: _scrollController,
                    state: state,
                    bottomPadding: contentBottom,
                    onRefresh: () => context.read<NearbyCubit>().refresh(),
                    onUserScroll: _onScroll,
                    onRefreshActivityChanged: (isActive) {
                      if (mounted && _isPullRefreshing != isActive) {
                        setState(() => _isPullRefreshing = isActive);
                      }
                    },
                  ),
                  if (state.shouldObscureContent)
                    const Positioned.fill(child: _LocationRequiredBackdrop()),
                  if (state.shouldObscureContent)
                    Positioned.fill(
                      child: _LocationRequiredOverlay(
                        bottomInset: contentBottom,
                        hidden: state.status == NearbyStatus.visibilityDisabled,
                        busy: state.isVisibilitySaving,
                        onRetry: () =>
                            state.status == NearbyStatus.visibilityDisabled
                            ? context.read<NearbyCubit>().enableVisibility()
                            : context.read<NearbyCubit>().requestLocation(),
                      ),
                    ),
                  if (shouldShowEmptyState)
                    Positioned.fill(
                      child: _NearbyEmptyStateLayer(
                        bottomPadding: contentBottom,
                        failed: state.status == NearbyStatus.failure,
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: const BottomAmbientGlow(),
                  ),
                  if (state.isRefreshing &&
                      state.status == NearbyStatus.locationRequired)
                    const Positioned.fill(child: _LocationUpdatingOverlay()),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: filterBottom,
                    child: _FiltersButton(
                      onPressed:
                          state.shouldObscureContent ||
                              state.isRefreshing ||
                              _isPullRefreshing
                          ? null
                          : () => _openFilters(state.filters),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _requestInitialLocation() async {
    final locations = context.read<ILocationRepository>();
    final access = await locations.getLocationAccessStatus();
    if (!mounted || access == LocationAccessStatus.granted) return;
    await context.read<NearbyCubit>().requestLocation();
  }

  Future<void> _openFilters(NearbyFilters filters) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showModalBottomSheet<NearbyFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.scaffoldBackgroundColor,
      barrierColor: context.colorScheme.primary.withValues(alpha: .22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _FiltersSheet(initialFilters: filters),
    );
    if (selected != null && mounted) {
      await context.read<NearbyCubit>().applyFilters(selected);
    }
  }

  Future<void> _showLocationIssue(NearbyLocationIssue issue) async {
    if (!mounted) return;
    final locations = context.read<ILocationRepository>();
    final l10n = context.l10n;
    switch (issue) {
      case NearbyLocationIssue.serviceDisabled:
        await showPermissionDeniedDialog(
          context,
          title: l10n.locationDisabled,
          content: l10n.locationEnableDescription,
          onOpenSettings: locations.openLocationSettings,
        );
      case NearbyLocationIssue.denied:
      case NearbyLocationIssue.permanentlyDenied:
        await showPermissionDeniedDialog(
          context,
          title: l10n.locationPermissionDenied,
          content: l10n.locationPermissionSettingsDescription,
          onOpenSettings: locations.openAppSettings,
        );
      case NearbyLocationIssue.unavailable:
        showAppSnackBar(
          context,
          message: l10n.nearbyLocationUnavailable,
          type: SnackBarType.error,
          bottomMargin: 156,
        );
    }
  }
}

class _NearbyFeed extends StatefulWidget {
  const _NearbyFeed({
    required this.controller,
    required this.state,
    required this.bottomPadding,
    required this.onRefresh,
    required this.onUserScroll,
    required this.onRefreshActivityChanged,
  });

  final ScrollController controller;
  final NearbyState state;
  final double bottomPadding;
  final Future<void> Function() onRefresh;
  final VoidCallback onUserScroll;
  final ValueChanged<bool> onRefreshActivityChanged;

  @override
  State<_NearbyFeed> createState() => _NearbyFeedState();
}

class _NearbyFeedState extends State<_NearbyFeed>
    with TickerProviderStateMixin {
  bool _isSnapping = false;
  var _pullExtent = 0.0;
  var _isRefreshRunning = false;
  var _isPulling = false;
  var _isArmed = false;
  var _hasArmedHaptic = false;
  bool _userScrollSequence = false;
  bool _paginationAllowedForGesture = false;
  bool _paginationScheduled = false;
  final _pageControllers = <AnimationController>[];
  final _pageEntrances = <String, Animation<double>>{};
  var _avatarRetention = _NearbyAvatarRetention();
  List<NearbyPerson>? _gridSource;
  Set<String> _gridBlocked = const {};
  _NearbyAvatarRetention? _gridRetention;
  List<NearbyPerson> _gridPeople = const [];
  Widget? _grid;

  static const _refreshTriggerExtent = 42.0;
  static const _refreshRevealStart = 14.0;
  static const _refreshGap = 76.0;
  static const _minimumRefreshIndicatorDuration = Duration(milliseconds: 280);

  @override
  void didUpdateWidget(covariant _NearbyFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.state;
    final current = widget.state;
    final sameFeed =
        previous.filters == current.filters &&
        previous.feedRevision == current.feedRevision;
    final isAppend =
        sameFeed &&
        previous.people.isNotEmpty &&
        current.people.length > previous.people.length &&
        Iterable<int>.generate(previous.people.length).every(
          (index) => previous.people[index].id == current.people[index].id,
        );
    if (isAppend && !MediaQuery.disableAnimationsOf(context)) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
      );
      _pageControllers.add(controller);
      final opacity = controller.drive(CurveTween(curve: Curves.easeOutCubic));
      for (final person in current.people.skip(previous.people.length)) {
        _pageEntrances[person.id] = opacity;
      }
      // One clock per appended page, including its offscreen cards. Scrolling
      // a card back into view cannot replay its entrance animation.
      controller.forward();
    } else if (!sameFeed ||
        current.people.length != previous.people.length ||
        Iterable<int>.generate(current.people.length).any(
          (index) => current.people[index].id != previous.people[index].id,
        )) {
      _clearPageAnimations();
      _avatarRetention.dispose();
      _avatarRetention = _NearbyAvatarRetention();
    }
  }

  void _clearPageAnimations() {
    for (final controller in _pageControllers) {
      controller.dispose();
    }
    _pageControllers.clear();
    _pageEntrances.clear();
  }

  @override
  void dispose() {
    _clearPageAnimations();
    _avatarRetention.dispose();
    super.dispose();
  }

  double get _dragProgress => _isArmed || _isSnapping
      ? 1
      : 1 -
            math.exp(
              -math.max(0.0, _pullExtent - _refreshRevealStart) /
                  (_refreshTriggerExtent - _refreshRevealStart),
            );

  double get _refreshInset => _isRefreshRunning || _isArmed || _isSnapping
      ? _refreshGap
      : _refreshGap * _dragProgress;

  bool get _shouldShowIndicator =>
      _isRefreshRunning || _isSnapping || _dragProgress > 0;

  void _onRefreshStatusChanged(RefreshIndicatorStatus? status) {
    if (!mounted) return;
    if (status == RefreshIndicatorStatus.armed) {
      if (!_hasArmedHaptic) {
        _hasArmedHaptic = true;
        unawaited(HapticFeedback.mediumImpact());
      }
      setState(() => _isArmed = true);
    } else if (status == RefreshIndicatorStatus.snap) {
      setState(() {
        _isSnapping = true;
        _isPulling = false;
        _pullExtent = _refreshTriggerExtent;
      });
    } else if (status == RefreshIndicatorStatus.canceled || status == null) {
      if (!_isRefreshRunning) _resetPull();
    }
  }

  bool _trackPull(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _userScrollSequence = notification.dragDetails != null;
      _paginationAllowedForGesture = false;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _userScrollSequence = true;
      _paginationAllowedForGesture =
          (notification.scrollDelta ?? 0) > 0 &&
          notification.metrics.pixels >= notification.metrics.minScrollExtent;
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _paginationAllowedForGesture = notification.overscroll > 0;
    }
    final towardEnd = notification is ScrollUpdateNotification
        ? (notification.scrollDelta ?? 0) > 0
        : notification is OverscrollNotification && notification.overscroll > 0;
    if (_userScrollSequence &&
        _paginationAllowedForGesture &&
        towardEnd &&
        notification.metrics.pixels >= notification.metrics.minScrollExtent &&
        !_paginationScheduled) {
      _paginationScheduled = true;
      final filters = widget.state.filters;
      final revision = widget.state.feedRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paginationScheduled = false;
        if (mounted &&
            widget.state.filters == filters &&
            widget.state.feedRevision == revision) {
          widget.onUserScroll();
        }
      });
    }
    if (notification is ScrollEndNotification) {
      _userScrollSequence = false;
      _paginationAllowedForGesture = false;
    }
    if (_isRefreshRunning || _isSnapping || widget.state.isRefreshing) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _isPulling =
          notification.dragDetails != null &&
          notification.metrics.extentBefore <= 0;
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      if (!_isPulling &&
          notification is ScrollUpdateNotification &&
          notification.dragDetails != null) {
        _isPulling = notification.metrics.extentBefore <= 0;
      }
      if (_isPulling) {
        if (notification.metrics.pixels >
            notification.metrics.minScrollExtent) {
          _isPulling = false;
          _resetPull();
          return false;
        }
        var pullExtent = math
            .max(
              0.0,
              notification.metrics.minScrollExtent -
                  notification.metrics.pixels,
            )
            .toDouble();
        if (notification is OverscrollNotification &&
            notification.overscroll < 0) {
          pullExtent = math
              .max(pullExtent, _pullExtent - notification.overscroll)
              .toDouble();
        }
        _setPullExtent(pullExtent);
      }
    } else if (notification is ScrollEndNotification && _isPulling) {
      _isPulling = false;
      // The standard indicator alone decides whether releasing starts refresh.
      if (!_isArmed) _resetPull();
    }
    return false;
  }

  void _setPullExtent(double pullExtent) {
    final normalized = math.max(0.0, pullExtent);
    if (_pullExtent != normalized && mounted) {
      setState(() {
        _pullExtent = normalized;
      });
    }
  }

  void _resetPull() {
    if (!mounted) return;
    setState(() {
      _pullExtent = 0;
      _isPulling = false;
      _isArmed = false;
      _isSnapping = false;
      _hasArmedHaptic = false;
    });
  }

  Future<void> _handleRefresh() async {
    if (!mounted || _isRefreshRunning) return;
    final startedAt = DateTime.now();
    widget.onRefreshActivityChanged(true);
    if (mounted) {
      setState(() {
        _isRefreshRunning = true;
        _isSnapping = false;
        _isPulling = false;
        _isArmed = false;
        _pullExtent = _refreshTriggerExtent;
      });
    }
    try {
      await widget.onRefresh();
    } finally {
      final remaining =
          _minimumRefreshIndicatorDuration -
          DateTime.now().difference(startedAt);
      if (!remaining.isNegative) await Future<void>.delayed(remaining);
      if (mounted) {
        setState(() {
          _isRefreshRunning = false;
          _isPulling = false;
          _pullExtent = 0;
          _isArmed = false;
          _hasArmedHaptic = false;
        });
      }
      widget.onRefreshActivityChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    final blockedUserIds = context.select<BlocklistCubit, Set<String>>(
      (cubit) => cubit.state.blockedUserIds,
    );
    if (!identical(_gridSource, widget.state.people) ||
        _gridRetention != _avatarRetention ||
        _gridBlocked.length != blockedUserIds.length ||
        !_gridBlocked.containsAll(blockedUserIds)) {
      _gridSource = widget.state.people;
      _gridBlocked = Set.of(blockedUserIds);
      _gridRetention = _avatarRetention;
      _gridPeople = widget.state.people
          .where((person) => !blockedUserIds.contains(person.id))
          .toList(growable: false);
      final rows = _gridPeople;
      final indexes = {for (final entry in rows.indexed) entry.$2.id: entry.$1};
      _grid = SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: rows.length,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? indexes[key.value] : null,
        itemBuilder: (context, index) => FadeTransition(
          key: ValueKey(rows[index].id),
          opacity: _pageEntrances[rows[index].id] ?? kAlwaysCompleteAnimation,
          child: _NearbyPersonTile(
            person: rows[index],
            avatarRetention: _avatarRetention,
          ),
        ),
      );
    }
    final people = _gridPeople;
    if (widget.state.status == NearbyStatus.initial ||
        widget.state.status == NearbyStatus.loading && people.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator.noSpinner(
      onStatusChange: _onRefreshStatusChanged,
      onRefresh: _handleRefresh,
      notificationPredicate: (_) =>
          !widget.state.isRefreshing || _isRefreshRunning,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _refreshInset),
        duration: _isPulling
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: NotificationListener<ScrollNotification>(
          onNotification: _trackPull,
          child: CustomScrollView(
            controller: widget.controller,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  top: 130,
                  left: 16 + systemPadding.left,
                  right: 16 + systemPadding.right,
                  bottom: 8,
                ),
                sliver: people.isEmpty
                    ? const SliverToBoxAdapter(child: SizedBox(height: 250))
                    : _grid!,
              ),
              // A fixed slot above the controls prevents the end extent from
              // changing under the finger, and keeps the spinner unobscured.
              SliverToBoxAdapter(
                child: SizedBox(
                  key: const ValueKey('nearby_footer'),
                  height: widget.bottomPadding + 48,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _NearbyPullIndicator(
                        opacity: widget.state.isLoadingMore ? 1 : 0,
                        progress: 1,
                        spinning: true,
                        size: 24,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        builder: (context, animatedInset, child) => Stack(
          children: [
            Transform.translate(offset: Offset(0, animatedInset), child: child),
            Positioned(
              top: 130 + (animatedInset - 36) / 2,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: _NearbyPullIndicator(
                  key: const ValueKey('nearby_pull_indicator'),
                  opacity: _shouldShowIndicator
                      ? (_isRefreshRunning || _isArmed ? 1 : _dragProgress)
                      : 0,
                  progress: _dragProgress,
                  spinning: _isRefreshRunning,
                ),
              ),
            ),
            Positioned(
              top: 142,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: _NearbyPullIndicator(
                  key: const ValueKey('nearby_query_indicator'),
                  opacity: widget.state.isRefreshing && !_isRefreshRunning
                      ? 1
                      : 0,
                  progress: 1,
                  spinning: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Retains the current ring while fading out instead of replacing a spinning
/// ring with an empty determinate one in the first dismissal frame.
class _NearbyPullIndicator extends StatefulWidget {
  const _NearbyPullIndicator({
    super.key,
    required this.opacity,
    required this.progress,
    required this.spinning,
    this.size = 36,
    this.strokeWidth = 4,
  });

  final double opacity;
  final double progress;
  final bool spinning;
  final double size;
  final double strokeWidth;

  @override
  State<_NearbyPullIndicator> createState() => _NearbyPullIndicatorState();
}

class _NearbyPullIndicatorState extends State<_NearbyPullIndicator>
    with SingleTickerProviderStateMixin {
  late final _visibility = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: widget.opacity,
  );
  late bool _spinning = widget.spinning;

  @override
  void didUpdateWidget(covariant _NearbyPullIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.opacity > 0) _spinning = widget.spinning;
    if (widget.opacity != oldWidget.opacity) {
      _visibility.animateTo(widget.opacity, curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _visibility,
    child: Center(
      heightFactor: 1,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: CircularProgressIndicator(
            key: ValueKey(
              _spinning ? 'nearby_refresh_spinner' : 'nearby_refresh_progress',
            ),
            value: _spinning ? null : widget.progress,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    ),
    builder: (context, child) => TickerMode(
      enabled: _visibility.value > 0,
      child: Opacity(
        opacity: _visibility.value,
        child: Transform.scale(
          scale: .85 + .15 * _visibility.value,
          child: child,
        ),
      ),
    ),
  );
}

class _NearbyEmptyStateLayer extends StatelessWidget {
  const _NearbyEmptyStateLayer({
    required this.bottomPadding,
    required this.failed,
  });

  final double bottomPadding;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final emptyState = _NearbyEmptyState(failed: failed);

    if (!isLandscape) {
      return IgnorePointer(
        child: Align(alignment: Alignment(0, -0.12), child: emptyState),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scrollExtent = math.max(bottomPadding - 160, 0.0);
          return SingleChildScrollView(
            reverse: true,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight + scrollExtent,
              ),
              child: Align(alignment: Alignment.center, child: emptyState),
            ),
          );
        },
      ),
    );
  }
}

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final messageStyle = context.textTheme.titleLarge?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: context.colorScheme.onSurface,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/images/mood_bad_24dp.svg',
            width: 72,
            height: 72,
            colorFilter: const ColorFilter.mode(
              AppColors.incomingBubble,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            failed ? context.l10n.nearbyLoadFailed : context.l10n.nearbyEmpty,
            textAlign: TextAlign.center,
            style: messageStyle,
          ),
        ],
      ),
    );
  }
}

class _NearbyPersonTile extends StatelessWidget {
  const _NearbyPersonTile({
    required this.person,
    required this.avatarRetention,
  });

  final NearbyPerson person;
  final _NearbyAvatarRetention avatarRetention;

  @override
  Widget build(BuildContext context) {
    final isOnline = context.select<PresenceCubit, bool>(
      (cubit) => cubit.state.isOnline(person.id),
    );
    return Semantics(
      button: true,
      label: person.displayName,
      child: InkWell(
        onTap: () => unawaited(openViewedProfile(context, userId: person.id)),
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final onlineBadgeSize = (constraints.maxWidth * .18)
                .clamp(16.0, 20.0)
                .toDouble();
            return Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _NearbyRetainedAvatar(
                        retention: avatarRetention,
                        child: ProfileAvatarHero(
                          profileId: person.id,
                          avatarUrl: person.avatarUrl,
                          avatarStoragePath: person.avatarStoragePath,
                          child: UserAvatar(
                            initialAvatarPath: person.cachedAvatarPath,
                            avatarUrl: person.avatarUrl,
                            avatarLoader: () => context
                                .read<INearbyRepository>()
                                .resolveAvatar(person),
                            preferAvatarLoader: true,
                            avatarRevision:
                                person.avatarStoragePath ?? person.avatarUrl,
                            size: constraints.maxWidth,
                            borderRadius: 8,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 7,
                        child: Text(
                          person.displayName,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -2,
                  left: -2,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: isOnline
                        ? Container(
                            key: const ValueKey('online-badge'),
                            width: onlineBadgeSize,
                            height: onlineBadgeSize,
                            decoration: BoxDecoration(
                              color: context.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                          )
                        : const SizedBox(key: ValueKey('online-badge-hidden')),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Retains only a small scrolling neighbourhood, not the entire feed. The
/// avatar State keeps its existing decoded frame and pending loader handoff.
class _NearbyAvatarRetention {
  static const maximum = 48;
  final _recent = <ValueNotifier<bool>>{};
  final _live = <ValueNotifier<bool>>{};
  bool _disposed = false;

  ValueNotifier<bool> acquire() {
    final lease = ValueNotifier(true);
    _live.add(lease);
    _recent.add(lease);
    if (_recent.length > maximum) {
      final oldest = _recent.first;
      _recent.remove(oldest);
      // Mounting a grid child happens during layout; defer keep-alive updates.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && _live.contains(oldest)) oldest.value = false;
      });
    }
    return lease;
  }

  void release(ValueNotifier<bool> lease) {
    _recent.remove(lease);
    _live.remove(lease);
    lease.dispose();
  }

  void dispose() {
    _disposed = true;
    for (final lease in _live.toList()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_live.contains(lease)) lease.value = false;
      });
    }
    _recent.clear();
  }
}

class _NearbyRetainedAvatar extends StatefulWidget {
  const _NearbyRetainedAvatar({required this.retention, required this.child});
  final _NearbyAvatarRetention retention;
  final Widget child;

  @override
  State<_NearbyRetainedAvatar> createState() => _NearbyRetainedAvatarState();
}

class _NearbyRetainedAvatarState extends State<_NearbyRetainedAvatar>
    with AutomaticKeepAliveClientMixin {
  late ValueNotifier<bool> _lease;

  @override
  void initState() {
    _lease = widget.retention.acquire()..addListener(updateKeepAlive);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _NearbyRetainedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retention != widget.retention) {
      _lease.removeListener(updateKeepAlive);
      oldWidget.retention.release(_lease);
      _lease = widget.retention.acquire()..addListener(updateKeepAlive);
      updateKeepAlive();
    }
  }

  @override
  bool get wantKeepAlive => _lease.value;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  void dispose() {
    _lease.removeListener(updateKeepAlive);
    widget.retention.release(_lease);
    super.dispose();
  }
}

class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: context.colorScheme.onSurface.withValues(alpha: .4),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.tune_rounded, size: 25),
              label: Text(context.l10n.nearbyFilters),
              style: FilledButton.styleFrom(
                backgroundColor: context.colorScheme.onSurface.withValues(
                  alpha: .15,
                ),
                foregroundColor: context.colorScheme.onSurface,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LocationRequiredBackdrop extends StatelessWidget {
  const _LocationRequiredBackdrop();

  @override
  Widget build(BuildContext context) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
    child: ColoredBox(
      color: context.scaffoldBackgroundColor.withValues(alpha: .42),
    ),
  );
}

class _LocationRequiredOverlay extends StatelessWidget {
  const _LocationRequiredOverlay({
    required this.bottomInset,
    required this.onRetry,
    this.hidden = false,
    this.busy = false,
  });

  final double bottomInset;
  final VoidCallback onRetry;
  final bool hidden;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (!isLandscape) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
          child: _LocationRequiredPanel(
            onRetry: busy ? null : onRetry,
            hidden: hidden,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = math.min(constraints.maxWidth, 420.0);
          final scrollExtent = math.max(bottomInset - 50, 0.0);
          return SingleChildScrollView(
            reverse: true,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight + scrollExtent,
              ),
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: panelWidth,
                  child: _LocationRequiredPanel(
                    onRetry: busy ? null : onRetry,
                    hidden: hidden,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LocationRequiredPanel extends StatelessWidget {
  const _LocationRequiredPanel({required this.onRetry, this.hidden = false});

  final VoidCallback? onRetry;
  final bool hidden;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hidden
                ? context.l10n.nearbyHiddenTitle
                : context.l10n.nearbyLocationRequiredTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            hidden
                ? context.l10n.nearbyHiddenContent
                : context.l10n.nearbyLocationRequiredContent,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 230,
              height: 58,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colorScheme.primary,
                  foregroundColor: context.colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  hidden
                      ? context.l10n.nearbyEnableVisibility
                      : context.l10n.nearbyLocationUpdateShort,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LocationUpdatingOverlay extends StatelessWidget {
  const _LocationUpdatingOverlay();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.scaffoldBackgroundColor.withValues(alpha: .28),
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initialFilters});

  final NearbyFilters initialFilters;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late NearbyFilters _filters = widget.initialFilters;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: context.colorScheme.onSurface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.nearbyFilters,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 14),
          _FilterRow(
            label: context.l10n.profileGenderLabel,
            value: _genderLabel(context, _filters.gender),
            onTap: _selectGender,
          ),
          _FilterRow(
            label: context.l10n.nearbyAge,
            value: '${_filters.minimumAge}–${_filters.maximumAge}',
            onTap: _selectAge,
          ),
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 230,
              height: 58,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_filters),
                style: FilledButton.styleFrom(
                  backgroundColor: context.colorScheme.primary,
                  foregroundColor: context.colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  context.l10n.nearbyApply.toLowerCase(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _selectGender() async {
    final selected = await showModalBottomSheet<ProfileGender?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.scaffoldBackgroundColor,
      barrierColor: context.colorScheme.primary.withValues(alpha: .22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetContext.colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                sheetContext.l10n.profileGenderTitle,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              ProfileGenderPicker(
                selectedGender: _filters.gender,
                resetLabel: sheetContext.l10n.authOnboardingReset,
                onSelected: (gender) => Navigator.of(sheetContext).pop(gender),
                onReset: () =>
                    Navigator.of(sheetContext).pop(ProfileGender.unspecified),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(
      () => _filters = selected == ProfileGender.unspecified
          ? _filters.copyWith(clearGender: true)
          : _filters.copyWith(gender: selected),
    );
  }

  Future<void> _selectAge() async {
    final selected = await showModalBottomSheet<({int minimum, int maximum})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.scaffoldBackgroundColor,
      barrierColor: context.colorScheme.primary.withValues(alpha: .22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _AgeSheet(
        minimumAge: _filters.minimumAge,
        maximumAge: _filters.maximumAge,
      ),
    );
    if (selected != null && mounted) {
      setState(
        () => _filters = _filters.copyWith(
          minimumAge: selected.minimum,
          maximumAge: selected.maximum,
        ),
      );
    }
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toLowerCase(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: context.colorScheme.onSurfaceVariant,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            color: context.colorScheme.onSurfaceVariant,
            size: 32,
          ),
        ],
      ),
    ),
  );
}

class _AgeSheet extends StatefulWidget {
  const _AgeSheet({required this.minimumAge, required this.maximumAge});

  final int minimumAge;
  final int maximumAge;

  @override
  State<_AgeSheet> createState() => _AgeSheetState();
}

class _AgeSheetState extends State<_AgeSheet> {
  late final TextEditingController _minimum = TextEditingController(
    text: widget.minimumAge.toString(),
  );
  late final TextEditingController _maximum = TextEditingController(
    text: widget.maximumAge.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: context.colorScheme.onSurface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.nearbyAge,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: math.min(MediaQuery.sizeOf(context).width - 32, 300.0),
            child: Row(
              children: [
                Expanded(
                  child: _AgeInput(
                    label: context.l10n.nearbyAgeFrom,
                    controller: _minimum,
                    errorText: _error == null
                        ? null
                        : context.l10n.nearbyAgeInvalidShort,
                    onChanged: _clearError,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AgeInput(
                    label: context.l10n.nearbyAgeTo,
                    controller: _maximum,
                    errorText: _error == null
                        ? null
                        : context.l10n.nearbyAgeInvalidShort,
                    onChanged: _clearError,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 230,
              height: 58,
              child: FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colorScheme.primary,
                  foregroundColor: context.colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  context.l10n.nearbyApply.toLowerCase(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  void _apply() {
    final minimum = int.tryParse(_minimum.text);
    final maximum = int.tryParse(_maximum.text);
    if (minimum == null ||
        maximum == null ||
        minimum < 18 ||
        maximum > 99 ||
        minimum > maximum) {
      setState(() => _error = context.l10n.nearbyAgeInvalid);
      return;
    }
    Navigator.of(context).pop((minimum: minimum, maximum: maximum));
  }
}

class _AgeInput extends StatelessWidget {
  const _AgeInput({
    required this.label,
    required this.controller,
    required this.errorText,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => OnboardingTextField(
    controller: controller,
    label: label,
    hint: '—',
    maxLength: 2,
    maxLines: 1,
    tooLongText: context.l10n.nearbyAgeInvalidShort,
    errorText: errorText,
    keyboardType: TextInputType.number,
    onChanged: onChanged,
    textAlign: TextAlign.center,
    autocorrect: false,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
  );
}

String _genderLabel(BuildContext context, ProfileGender? gender) =>
    switch (gender) {
      ProfileGender.male => context.l10n.profileGenderMale,
      ProfileGender.female => context.l10n.profileGenderFemale,
      _ => context.l10n.profileGenderUnspecified,
    };
