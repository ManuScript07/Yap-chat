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
import 'package:yap_chat/features/profile/view/viewed_profile_navigation.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<NearbyCubit>().initialize());
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      unawaited(context.read<NearbyCubit>().loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<NearbyCubit, NearbyState>(
      listenWhen: (previous, current) =>
          previous.locationFeedbackId != current.locationFeedbackId &&
          current.locationIssue != null,
      listener: (context, state) => _showLocationIssue(state.locationIssue!),
      child: BlocConsumer<NearbyCubit, NearbyState>(
        listenWhen: (previous, current) =>
            previous.status != current.status &&
            current.status == NearbyStatus.locationRequired &&
            current.locationIssue == null,
        listener: (context, state) {
          if (_locationPromptedAutomatically) return;
          _locationPromptedAutomatically = true;
          unawaited(_requestInitialLocation());
        },
        builder: (context, state) {
          final mediaQuery = MediaQuery.of(context);
          const navBarHeight = 70.0;
          const navBarOffset = 16.0;
          const controlHeight = 50.0;
          final filterBottom =
              mediaQuery.viewPadding.bottom +
              navBarHeight +
              navBarOffset +
              16.0;
          final contentBottom = filterBottom + controlHeight + 20;

          return Scaffold(
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
                  onRefreshActivityChanged: (isActive) {
                    if (mounted && _isPullRefreshing != isActive) {
                      setState(() => _isPullRefreshing = isActive);
                    }
                  },
                ),
                if (state.status == NearbyStatus.locationRequired)
                  const Positioned.fill(child: _LocationRequiredBackdrop()),
                if (state.status == NearbyStatus.locationRequired)
                  Positioned.fill(
                    child: _LocationRequiredOverlay(
                      bottomInset: contentBottom,
                      onRetry: () =>
                          context.read<NearbyCubit>().requestLocation(),
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
                    onPressed: state.isRefreshing || _isPullRefreshing
                        ? null
                        : () => _openFilters(state.filters),
                  ),
                ),
              ],
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
    required this.onRefreshActivityChanged,
  });

  final ScrollController controller;
  final NearbyState state;
  final double bottomPadding;
  final Future<void> Function() onRefresh;
  final ValueChanged<bool> onRefreshActivityChanged;

  @override
  State<_NearbyFeed> createState() => _NearbyFeedState();
}

class _NearbyFeedState extends State<_NearbyFeed> {
  final _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  var _pullExtent = 0.0;
  var _isRefreshRunning = false;
  var _isPulling = false;
  var _isArmed = false;
  var _hasArmedHaptic = false;

  static const _refreshTriggerExtent = 42.0;
  static const _refreshRevealStart = 14.0;
  static const _refreshGap = 76.0;
  static const _minimumRefreshIndicatorDuration = Duration(milliseconds: 280);

  double get _dragProgress =>
      ((_pullExtent - _refreshRevealStart) /
              (_refreshTriggerExtent - _refreshRevealStart))
          .clamp(0.0, 1.0);

  double get _refreshInset =>
      _isRefreshRunning || _isArmed ? _refreshGap : _refreshGap * _dragProgress;

  bool get _shouldShowIndicator => _isRefreshRunning || _dragProgress > 0;

  bool _trackPull(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (_isRefreshRunning) return false;

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
        var pullExtent = math.max(0.0, -notification.metrics.pixels).toDouble();
        if (notification is OverscrollNotification) {
          pullExtent = math
              .max(pullExtent, _pullExtent + notification.overscroll.abs())
              .toDouble();
        }
        _setPullExtent(pullExtent);
      }
    } else if (notification is ScrollEndNotification && _isPulling) {
      final shouldRefresh = _isArmed;
      _isPulling = false;
      if (shouldRefresh) {
        final indicator = _refreshIndicatorKey.currentState;
        if (indicator != null) {
          unawaited(indicator.show());
        } else {
          unawaited(_handleRefresh());
        }
      } else {
        _resetPull();
      }
    }
    return false;
  }

  void _setPullExtent(double pullExtent) {
    final normalized = pullExtent.clamp(0.0, _refreshTriggerExtent).toDouble();
    final isArmed = normalized >= _refreshTriggerExtent;
    if (isArmed && !_hasArmedHaptic) {
      _hasArmedHaptic = true;
      unawaited(HapticFeedback.mediumImpact());
    } else if (!isArmed) {
      _hasArmedHaptic = false;
    }
    if ((_pullExtent != normalized || _isArmed != isArmed) && mounted) {
      setState(() {
        _pullExtent = normalized;
        _isArmed = isArmed;
      });
    }
  }

  void _resetPull() {
    if (!mounted) return;
    setState(() {
      _pullExtent = 0;
      _isArmed = false;
      _hasArmedHaptic = false;
    });
  }

  Future<void> _handleRefresh() async {
    final startedAt = DateTime.now();
    widget.onRefreshActivityChanged(true);
    if (mounted) {
      setState(() {
        _isRefreshRunning = true;
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
    final people = widget.state.people
        .where((person) => !blockedUserIds.contains(person.id))
        .toList(growable: false);
    if (widget.state.status == NearbyStatus.initial ||
        widget.state.status == NearbyStatus.loading && people.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.state.status == NearbyStatus.failure && people.isEmpty) {
      return Center(child: Text(context.l10n.nearbyLoadFailed));
    }
    return RefreshIndicator.noSpinner(
      key: _refreshIndicatorKey,
      onRefresh: _handleRefresh,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _refreshInset),
        duration: _isPulling
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (context, animatedInset, _) => Stack(
          children: [
            Transform.translate(
              offset: Offset(0, animatedInset),
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
                          ? SliverToBoxAdapter(
                              child: const SizedBox(height: 250),
                            )
                          : SliverGrid.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 150,
                                    crossAxisSpacing: 6,
                                    mainAxisSpacing: 6,
                                  ),
                              itemCount: people.length,
                              itemBuilder: (context, index) =>
                                  _NearbyPersonTile(person: people[index]),
                            ),
                    ),
                    if (widget.state.isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: widget.bottomPadding),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 130 + (animatedInset - 36) / 2,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _shouldShowIndicator
                      ? (_isRefreshRunning || _isArmed ? 1 : _dragProgress)
                      : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Center(
                    child: Transform.scale(
                      scale:
                          .65 +
                          .35 *
                              (_isRefreshRunning || _isArmed
                                  ? 1
                                  : _dragProgress),
                      child: SizedBox.square(
                        dimension: 36,
                        child: CircularProgressIndicator(
                          value: _isRefreshRunning ? null : _dragProgress,
                          strokeWidth: 4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (people.isEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 130,
                      bottom: widget.bottomPadding,
                    ),
                    child: const Align(
                      alignment: Alignment(0, -0.12),
                      child: _NearbyEmptyState(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState();

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
            context.l10n.nearbyEmpty,
            textAlign: TextAlign.center,
            style: messageStyle,
          ),
        ],
      ),
    );
  }
}

class _NearbyPersonTile extends StatelessWidget {
  const _NearbyPersonTile({required this.person});

  final NearbyPerson person;

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
                      UserAvatar(
                        avatarUrl: person.avatarUrl,
                        avatarLoader: () => context
                            .read<INearbyRepository>()
                            .resolveAvatar(person),
                        preferAvatarLoader: true,
                        avatarRevision:
                            person.avatarStoragePath ?? person.avatarUrl,
                        size: constraints.maxWidth,
                        borderRadius: 0,
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
  });

  final double bottomInset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (!isLandscape) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
          child: _LocationRequiredPanel(onRetry: onRetry),
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
                  child: _LocationRequiredPanel(onRetry: onRetry),
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
  const _LocationRequiredPanel({required this.onRetry});

  final VoidCallback onRetry;

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
            context.l10n.nearbyLocationRequiredTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.nearbyLocationRequiredContent,
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
                  context.l10n.nearbyLocationUpdateShort,
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
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
    ],
  );
}

String _genderLabel(BuildContext context, ProfileGender? gender) =>
    switch (gender) {
      ProfileGender.male => context.l10n.profileGenderMale,
      ProfileGender.female => context.l10n.profileGenderFemale,
      _ => context.l10n.profileGenderUnspecified,
    };
