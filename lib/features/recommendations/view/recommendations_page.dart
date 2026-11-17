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
  final _controllers = {
    for (final tab in FeedTab.values) tab: ScrollController(),
  };
  AccountSessionController? _accounts;
  IFeedRepository? _repository;
  ILocationRepository? _location;
  LocationTrackingCoordinator? _tracking;
  StreamSubscription<Set<String>>? _blocks;
  StreamSubscription<String>? _friendChanges;
  AccountSessionSnapshot? _account;
  Map<FeedTab, FeedCubit> _timelines = {};
  FeedActionsCubit? _actions;
  StreamSubscription<Set<String>>? _actionChanges;
  FeedTab _selected = FeedTab.forYou;
  bool _activeRoute = false;
  bool _foreground = true;
  bool _visibilityCheckScheduled = false;
  bool _checkingLocation = false;
  bool _updatingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    unawaited(_blocks?.cancel());
    unawaited(_friendChanges?.cancel());
    unawaited(_actions?.close());
    unawaited(_actionChanges?.cancel());
    _actions = null;
    for (final timeline in _timelines.values) {
      unawaited(timeline.close());
    }
    _timelines = {};
    _account = null;
    _storage = PageStorageBucket();
    _selected = FeedTab.forYou;
    _checkingLocation = false;
    _updatingLocation = false;
    final accounts = _accounts;
    final repository = _repository;
    if (accounts == null || accounts.userId == null || repository == null) {
      return;
    }

    final account = accounts.capture();
    _account = account;
    if (repository is IFeedPostRepository) {
      _actions = FeedActionsCubit(
        repository as IFeedPostRepository,
        account,
        () => accounts.isCurrent(account),
      );
    }
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
    _actionChanges = _actions?.stream
        .map((state) => state.hidden)
        .distinct((a, b) => a.length == b.length && a.containsAll(b))
        .listen((hidden) {
          if (!mounted || !accounts.isCurrent(account)) return;
          for (final timeline in _timelines.values) {
            timeline.hidePosts(hidden);
          }
        });
    _blocks = context
        .read<IBlocklistRepository?>()
        ?.watchBlockedUserIds()
        .listen((blocked) {
          if (!mounted || !accounts.isCurrent(account)) return;
          _actions?.setBlocked(blocked);
          for (final timeline in _timelines.values) {
            timeline.updateBlockedAuthors(blocked);
          }
        }, onError: (Object _) {});
    final friends = context.read<IFriendsRepository?>();
    if (friends is IProfileFriendsRepository) {
      _friendChanges = (friends as IProfileFriendsRepository)
          .watchProfileChanges()
          .listen((id) {
            if (!mounted || !accounts.isCurrent(account)) return;
            _actions?.revalidateAuthor(id);
            for (final timeline in _timelines.values) {
              if (timeline.hasAuthor(id)) timeline.invalidateAccess();
            }
            _scheduleVisibilityCheck();
          }, onError: (Object _) {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    setState(() => _foreground = foreground);
    if (!_foreground) {
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
    if (_checkingLocation) return;
    _checkingLocation = true;
    bool allowed;
    try {
      allowed =
          await _location!.getLocationAccessStatus() ==
          LocationAccessStatus.granted;
    } catch (_) {
      allowed = false;
    }
    if (!mounted || !identical(_timelines[FeedTab.nearby], timeline)) return;
    _checkingLocation = false;
    timeline.setLocationAllowed(allowed);
    if (_selected == FeedTab.nearby && _activeRoute && _foreground) {
      await timeline.activate(atTop: _atTop(FeedTab.nearby));
    }
  }

  bool _atTop(FeedTab tab) {
    final controller = _controllers[tab]!;
    return !controller.hasClients || controller.offset <= 1;
  }

  void _select(int index) {
    final selected = FeedTab.values[index];
    if (selected == _selected) return;
    _timelines[_selected]?.deactivate();
    setState(() => _selected = selected);
    _scheduleVisibilityCheck();
  }

  Future<void> _updateLocation() async {
    final tracking = _tracking;
    final timeline = _timelines[FeedTab.nearby];
    if (tracking == null || timeline == null || _updatingLocation) return;
    setState(() => _updatingLocation = true);
    var result = TrackedLocationRefreshResult.unavailable;
    try {
      result = await tracking.refreshWithPermission();
    } catch (_) {
      // The coordinator can fail when permission or the network changes.
    }
    if (!mounted || !identical(_timelines[FeedTab.nearby], timeline)) return;
    setState(() => _updatingLocation = false);
    if (result != TrackedLocationRefreshResult.unavailable) {
      await timeline.locationUpdated();
    } else if (_selected == FeedTab.nearby && _activeRoute) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.feedLocationUnavailable)),
      );
    }
  }

  void _showPlaceholder(String title) {
    showModalBottomSheet<void>(
      context: context,
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
    final timeline = account != null && _accounts!.isCurrent(account)
        ? _timelines[_selected]
        : null;
    final appBar = PrimaryAppBar(
      compact: true,
      showGradient: _repository == null,
      title: l10n.recommendationsTitle,
      titleWidget: ConnectionStatusTitle(
        compact: true,
        title: l10n.recommendationsTitle,
      ),
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
          PrimarySegmentedControl(
            compact: true,
            selectedIndex: _selected.index,
            onChanged: _select,
            items: [
              PrimarySegmentItem(label: l10n.feedForYou),
              PrimarySegmentItem(label: l10n.feedNearby),
              PrimarySegmentItem(label: l10n.feedFriends),
            ],
          ),
          const SizedBox(height: PrimaryHeaderGeometry.tabsBottomSpacing),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: _repository == null ? appBar : null,
      body: _repository == null
          ? Center(child: Text(l10n.recommendationsEmpty))
          : timeline == null
          ? Column(
              children: [
                header,
                Expanded(child: Center(child: Text(l10n.feedEmpty))),
              ],
            )
          : PageStorage(
              bucket: _storage,
              child: FeedTabView(
                key: ValueKey((_selected, account!.generation)),
                timeline: timeline,
                controller: _controllers[_selected]!,
                header: header,
                bottomPadding: navigationHeight + 84,
                visible: _activeRoute && _foreground,
                onUpdateLocation: _updatingLocation ? null : _updateLocation,
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
                onPressed: () => _showPlaceholder(l10n.feedNewPost),
                child: const Icon(Icons.add),
              ),
            ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accounts?.generationChanges.removeListener(_accountChanged);
    unawaited(_blocks?.cancel());
    unawaited(_friendChanges?.cancel());
    unawaited(_actions?.close());
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
