import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/location_tracking_coordinator.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/recommendations/bloc/bloc.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

import 'feed_tab_view.dart';

@RoutePage()
class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({super.key});

  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage>
    with WidgetsBindingObserver {
  var _storage = PageStorageBucket();
  final _pages = SwipeTabController();
  final _headerHiddenFraction = ValueNotifier<double>(0);
  late final _controllers = {
    for (final tab in FeedTab.values)
      tab: ScrollController(
        onAttach: (position) {
          final offset = _hiddenHeaderOffset;
          if (position.pixels < offset) position.correctPixels(offset);
        },
      ),
  };
  double _headerExtent = PrimaryHeaderGeometry.compactTabsContentTop;
  double get _hiddenHeaderOffset => _headerExtent * _headerHiddenFraction.value;
  AccountSessionController? _accounts;
  IFeedRepository? _repository;
  ILocationRepository? _location;
  LocationTrackingCoordinator? _tracking;
  AccountSessionSnapshot? _account;
  Map<FeedTab, FeedCubit> _timelines = {};
  FeedActionsCubit? _actions;
  StreamSubscription<FeedActionsState>? _actionChanges;
  FeedAccountScope? _localFeedScope;
  FeedTab _selected = FeedTab.forYou;
  bool _activeRoute = false;
  bool _foreground = true;
  bool _visibilityCheckScheduled = false;
  bool _checkingLocation = false;
  bool _updatingLocation = false;
  DateTime? _nearbyPublicationAt;
  Timer? _nearbyExpiry;

  @override
  void initState() {
    super.initState();
    _pages.addListener(_prepareIncomingTab);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final headerExtent =
        MediaQuery.orientationOf(context) == Orientation.landscape
        ? PrimaryHeaderGeometry.compactHeight
        : PrimaryHeaderGeometry.compactTabsContentTop;
    if (headerExtent != _headerExtent) {
      _headerExtent = headerExtent;
      // The new viewport layout will consume the new header extent.
      final controller = _controllers[_selected]!;
      final offset = _hiddenHeaderOffset;
      if (controller.hasClients && controller.offset < offset) {
        controller.position.correctPixels(offset);
      }
    }
    final tabs = TabsRouterScope.of(context, watch: true)?.controller;
    _activeRoute =
        (tabs?.current.name ?? 'RecommendationsRoute') ==
            'RecommendationsRoute' &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (!_activeRoute) {
      _timelines[_selected]?.deactivate();
    }
    if (_accounts == null) {
      _repository = context.read<IFeedRepository?>();
      _accounts = context.read<AccountSessionController?>();
      _location = context.read<ILocationRepository?>();
      _tracking = context.read<LocationTrackingCoordinator?>();
      _accounts?.generationChanges.addListener(_accountChanged);
      _replaceTimelines();
    }
    _scheduleVisibilityCheck();
  }

  void _accountChanged() {
    if (!mounted) return;
    // The app may notify its listeners while rebuilding the auth gate.
    _scheduleVisibilityCheck();
  }

  void _replaceTimelines() {
    unawaited(_actionChanges?.cancel());
    _actions = null;
    for (final timeline in _timelines.values) {
      unawaited(timeline.close());
    }
    _timelines = {};
    _account = null;
    _storage = PageStorageBucket();
    _selected = FeedTab.forYou;
    _headerHiddenFraction.value = 0;
    _checkingLocation = false;
    _updatingLocation = false;
    _nearbyPublicationAt = null;
    _cancelNearbyExpiry();
    final accounts = _accounts;
    final repository = _repository;
    if (accounts == null || accounts.userId == null || repository == null) {
      return;
    }

    final account = accounts.capture();
    _account = account;
    final friends = context.read<IFriendsRepository?>();
    final scope =
        context.read<FeedAccountScope?>() ??
        (_localFeedScope ??= FeedAccountScope(
          accounts,
          repository,
          blocks: context.read<IBlocklistRepository?>(),
          friends: friends is IFriendAccessRepository
              ? friends as IFriendAccessRepository
              : null,
        ));
    _actions = scope.actionsFor(account);
    _timelines = {
      for (final tab in FeedTab.values)
        tab: FeedCubit(
          tab: tab,
          repository: repository,
          account: account,
          actions: _actions,
          isCurrentAccount: () => accounts.isCurrent(account),
        ),
    };
    if (_actions case final actions?) {
      FeedActionsState? previous;
      void apply(FeedActionsState state) {
        if (!mounted || !accounts.isCurrent(account)) return;
        final blocksChanged = !identical(previous?.blocked, state.blocked);
        final accessChanged = previous?.accessVersion != state.accessVersion;
        final hiddenChanged =
            previous == null || previous!.hidden.length != state.hidden.length;
        previous = state;
        for (final timeline in _timelines.values) {
          if (hiddenChanged) timeline.hidePosts(state.hidden);
          if (blocksChanged) timeline.updateBlockedAuthors(state.blocked);
          if (accessChanged) timeline.removeInaccessiblePosts();
        }
      }

      _actionChanges = actions.stream.listen(apply);
      apply(actions.state);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    setState(() => _foreground = foreground);
    if (!_foreground) {
      _cancelNearbyExpiry();
      for (final timeline in _timelines.values) {
        timeline.deactivate();
      }
    }
    _scheduleVisibilityCheck();
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) return;
      final account = _account;
      if (account == null
          ? _accounts?.userId != null
          : !_accounts!.isCurrent(account)) {
        setState(_replaceTimelines);
      }
      _activateSelected();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _activateSelected() {
    final active = _activeRoute && _foreground;
    if (!active || _selected != FeedTab.nearby) _cancelNearbyExpiry();
    for (final timeline in _timelines.values) {
      if (!active || timeline.tab != _selected) timeline.deactivate();
    }
    final timeline = _timelines[_selected];
    if (!active || timeline == null) return;
    if (_selected == FeedTab.nearby && _location != null) {
      unawaited(_activateNearby(timeline));
    } else {
      unawaited(timeline.activate(atTop: _atTop(_selected)));
    }
  }

  Future<void> _activateNearby(FeedCubit timeline) async {
    if (_checkingLocation || _updatingLocation || !_isActiveNearby(timeline)) {
      return;
    }
    _checkingLocation = true;
    final location = await _readNearbyLocation();
    if (!mounted || !identical(_timelines[FeedTab.nearby], timeline)) return;
    _checkingLocation = false;
    if (!_isActiveNearby(timeline) || _updatingLocation) return;
    _applyNearbyLocation(timeline, location);
    await timeline.activate(atTop: _atTop(FeedTab.nearby));
  }

  bool _isActiveNearby(FeedCubit timeline) =>
      mounted &&
      _selected == FeedTab.nearby &&
      _activeRoute &&
      _foreground &&
      identical(_timelines[FeedTab.nearby], timeline) &&
      timeline.isCurrentAccount();

  Future<CachedTrackedLocation?> _readNearbyLocation() async {
    try {
      return await _location?.getCachedCurrentLocation(
        maxAge: nearbyLocationMaxAge,
      );
    } catch (_) {
      return null;
    }
  }

  void _applyNearbyLocation(
    FeedCubit timeline,
    CachedTrackedLocation? location,
  ) {
    _cancelNearbyExpiry();
    final publishedAt = location?.updatedAt;
    final timeLeft = publishedAt
        ?.add(nearbyLocationMaxAge)
        .difference(DateTime.now());
    if (publishedAt == null || timeLeft == null || timeLeft <= Duration.zero) {
      timeline.setLocationAllowed(false);
      return;
    }
    final previous = _nearbyPublicationAt;
    _nearbyPublicationAt = publishedAt;
    timeline.setLocationAllowed(
      true,
      newerPublication: previous != null && publishedAt.isAfter(previous),
    );
    _nearbyExpiry = Timer(timeLeft, () => unawaited(_activateNearby(timeline)));
  }

  void _cancelNearbyExpiry() {
    _nearbyExpiry?.cancel();
    _nearbyExpiry = null;
  }

  bool _atTop(FeedTab tab) {
    final controller = _controllers[tab]!;
    return !controller.hasClients || controller.offset <= 1;
  }

  void _prepareIncomingTab() {
    final progress = _pages.progress;
    if (progress == _selected.index) return;
    final offset = _hiddenHeaderOffset;
    if (offset == 0) return;
    final incoming = progress > _selected.index
        ? progress.ceil()
        : progress.floor();
    final controller =
        _controllers[FeedTab.values[incoming.clamp(
          0,
          FeedTab.values.length - 1,
        )]]!;
    if (!controller.hasClients) return;
    final position = controller.position;
    if (position.hasContentDimensions && position.pixels < offset) {
      position.jumpTo(offset);
    }
  }

  void _updateHeader(FeedTab tab, double pixels, double delta) {
    final swipe = _pages.positions.singleOrNull;
    if (tab != _selected || (swipe?.isScrollingNotifier.value ?? false)) {
      return;
    }
    final limit = pixels.clamp(0.0, _headerExtent);
    _headerHiddenFraction.value =
        (_hiddenHeaderOffset + delta).clamp(0.0, limit) / _headerExtent;
  }

  void _select(int index) {
    final selected = FeedTab.values[index];
    if (selected == _selected) return;
    _cancelNearbyExpiry();
    _timelines[_selected]?.deactivate();
    setState(() => _selected = selected);
    _scheduleVisibilityCheck();
  }

  Future<void> _updateLocation() async {
    final tracking = _tracking;
    final timeline = _timelines[FeedTab.nearby];
    if (tracking == null ||
        timeline == null ||
        _updatingLocation ||
        !_isActiveNearby(timeline)) {
      return;
    }
    setState(() => _updatingLocation = true);
    var result = TrackedLocationRefreshResult.unavailable;
    try {
      result = await tracking.refreshWithPermission();
    } catch (_) {
      // The coordinator can fail when permission or the network changes.
    }
    final location = await _readNearbyLocation();
    if (!mounted || !identical(_timelines[FeedTab.nearby], timeline)) return;
    setState(() => _updatingLocation = false);
    if (!_isActiveNearby(timeline)) return;
    _applyNearbyLocation(timeline, location);
    if (result != TrackedLocationRefreshResult.unavailable) {
      if (result == TrackedLocationRefreshResult.updated && location != null) {
        await timeline.locationUpdated();
        return;
      }
      if (timeline.state.failure != FeedFailure.locationRequired) {
        await timeline.activate(atTop: _atTop(FeedTab.nearby));
        return;
      }
    }
    showAppSnackBar(
      context,
      message: context.l10n.feedLocationUnavailable,
      type: SnackBarType.error,
      bottomMargin: FloatingNavigationGeometry.occupiedHeight(
        MediaQuery.of(context),
      ),
    );
  }

  void _showPlaceholder(String title) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: context.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(context.l10n.feedComingSoon),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final l10n = context.l10n;
    final navigationHeight = FloatingNavigationGeometry.occupiedHeight(media);
    final account = _account;
    final hasAccount = account != null && _accounts!.isCurrent(account);
    final visible = _activeRoute && _foreground;
    final landscape = media.orientation == Orientation.landscape;
    final title = ConnectionStatusTitle(
      compact: true,
      title: l10n.recommendationsTitle,
    );
    Widget tabs({required double horizontalPadding}) => PrimarySegmentedControl(
      compact: true,
      horizontalPadding: horizontalPadding,
      applySafeArea: !landscape,
      selectedIndex: _selected.index,
      pages: hasAccount ? _pages : null,
      onChanged: _pages.select,
      items: [
        PrimarySegmentItem(label: l10n.feedForYou),
        PrimarySegmentItem(label: l10n.feedNearby),
        PrimarySegmentItem(label: l10n.feedFriends),
      ],
    );
    final appBar = PrimaryAppBar(
      compact: true,
      showGradient: _repository == null,
      title: l10n.recommendationsTitle,
      titleWidget: landscape && _repository != null
          ? Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: tabs(horizontalPadding: 0),
                  ),
                ),
              ],
            )
          : title,
      actionIcon: _repository == null ? null : Icons.inbox_outlined,
      actionTooltip: l10n.feedInbox,
      onActionPressed: () => _showPlaceholder(l10n.feedInbox),
    );
    final header = DecoratedBox(
      decoration: BoxDecoration(
        gradient: GradientOverlay.topGradient(context.scaffoldBackgroundColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          appBar,
          if (!landscape) ...[
            tabs(horizontalPadding: PrimaryHeaderGeometry.horizontalPadding),
            const SizedBox(height: PrimaryHeaderGeometry.tabsBottomSpacing),
          ],
        ],
      ),
    );
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: _repository == null ? appBar : null,
      body: _repository == null
          ? EmptyChatState(message: l10n.recommendationsEmpty, showImage: false)
          : !hasAccount
          ? Column(
              children: [
                header,
                Expanded(
                  child: EmptyChatState(
                    message: l10n.feedEmpty,
                    showImage: false,
                  ),
                ),
              ],
            )
          : PageStorage(
              bucket: _storage,
              child: NavigationScrollToTopTarget(
                target: NavigationScrollTarget.recommendations,
                controller: _controllers[_selected]!,
                enabled: visible,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SwipeTabView(
                      key: ValueKey(account.generation),
                      controller: _pages,
                      onSettled: _select,
                      children: [
                        for (final tab in FeedTab.values)
                          TickerMode(
                            enabled: tab == _selected && visible,
                            child: FeedTabView(
                              timeline: _timelines[tab]!,
                              controller: _controllers[tab]!,
                              headerExtent: _headerExtent,
                              onHeaderScroll: (pixels, delta) =>
                                  _updateHeader(tab, pixels, delta),
                              bottomPadding: navigationHeight + 84,
                              visible: tab == _selected && visible,
                              onUpdateLocation: _updatingLocation
                                  ? null
                                  : _updateLocation,
                            ),
                          ),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _headerHiddenFraction,
                        child: header,
                        builder: (context, hidden, child) => Offstage(
                          offstage: hidden == 1,
                          child: ClipRect(
                            child: Transform.translate(
                              offset: Offset(0, -hidden * _headerExtent),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: _repository == null
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: navigationHeight - media.padding.bottom,
                right: media.padding.right,
              ),
              child: FloatingActionButton(
                heroTag: null,
                tooltip: l10n.feedNewPost,
                shape: const CircleBorder(),
                backgroundColor: context.colorScheme.primary,
                foregroundColor: context.colorScheme.onSurface,
                onPressed: () => _showPlaceholder(l10n.feedNewPost),
                child: const Icon(Icons.add, size: 36),
              ),
            ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accounts?.generationChanges.removeListener(_accountChanged);
    _localFeedScope?.dispose();
    _cancelNearbyExpiry();
    _headerHiddenFraction.dispose();
    _pages.dispose();
    unawaited(_actionChanges?.cancel());
    for (final timeline in _timelines.values) {
      unawaited(timeline.close());
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
