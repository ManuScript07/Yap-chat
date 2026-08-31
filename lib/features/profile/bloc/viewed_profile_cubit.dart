import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/repositories/repositories.dart';

enum ViewedProfileStatus { initial, loading, success, failure }

class ViewedProfileState extends Equatable {
  const ViewedProfileState({
    this.status = ViewedProfileStatus.initial,
    this.viewedProfile,
    this.location,
    this.distance,
    this.chat,
    this.isActionPending = false,
    this.actionError,
  });

  final ViewedProfileStatus status;
  final ViewedProfile? viewedProfile;
  final FriendLocation? location;
  final UserDistance? distance;
  final Chat? chat;
  final bool isActionPending;
  final Object? actionError;

  ViewedProfileState copyWith({
    ViewedProfileStatus? status,
    ViewedProfile? viewedProfile,
    FriendLocation? location,
    UserDistance? distance,
    Chat? chat,
    bool? isActionPending,
    Object? actionError,
    bool clearActionError = false,
    bool clearLocation = false,
    bool clearDistance = false,
  }) => ViewedProfileState(
    status: status ?? this.status,
    viewedProfile: viewedProfile ?? this.viewedProfile,
    location: clearLocation ? null : location ?? this.location,
    distance: clearDistance ? null : distance ?? this.distance,
    chat: chat ?? this.chat,
    isActionPending: isActionPending ?? this.isActionPending,
    actionError: clearActionError ? null : actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [
    status,
    viewedProfile,
    location,
    distance,
    chat,
    isActionPending,
    actionError,
  ];
}

class ViewedProfileCubit extends Cubit<ViewedProfileState> {
  ViewedProfileCubit({
    required String userId,
    required IProfileRepository profileRepository,
    required IFriendsRepository friendsRepository,
    required IChatsRepository chatsRepository,
    required ILocationRepository locationRepository,
  }) : _userId = userId,
       _profileRepository = profileRepository,
       _friendsRepository = friendsRepository,
       _chatsRepository = chatsRepository,
       _locationRepository = locationRepository,
       super(const ViewedProfileState());

  final String _userId;
  final IProfileRepository _profileRepository;
  final IFriendsRepository _friendsRepository;
  final IChatsRepository _chatsRepository;
  final ILocationRepository _locationRepository;
  StreamSubscription<List<Chat>>? _chatsSubscription;
  StreamSubscription<String>? _friendsSubscription;
  bool _isRealtimeProfileRefreshPending = false;

  Future<void> load() async {
    _chatsSubscription ??= _chatsRepository.watchChats().listen(
      _syncLastSeenFromChats,
      onError: (_, _) {},
    );
    _friendsSubscription ??= _friendsRepository.watchProfileChanges().listen(
      _syncProfileFromFriendChange,
      onError: (_, _) {},
    );
    emit(state.copyWith(status: ViewedProfileStatus.loading));
    final cached = await _profileRepository.getCachedViewedProfile(_userId);
    if (cached != null && !isClosed) {
      emit(
        state.copyWith(
          status: ViewedProfileStatus.success,
          viewedProfile: cached,
        ),
      );
      await _loadSupportingData(cached);
    }
    try {
      final remote = await _profileRepository.getViewedProfile(_userId);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ViewedProfileStatus.success,
          viewedProfile: remote,
          clearActionError: true,
        ),
      );
      await _loadSupportingData(remote);
    } catch (error) {
      if (!isClosed && cached == null) {
        emit(
          state.copyWith(
            status: ViewedProfileStatus.failure,
            actionError: error,
          ),
        );
      }
    }
  }

  Future<void> _loadSupportingData(ViewedProfile profile) async {
    await Future.wait([_loadChat(profile), _loadLocation(profile)]);
  }

  Future<void> _loadChat(ViewedProfile profile) async {
    try {
      final chat = await _chatsRepository.prepareDirectChat(
        peerId: profile.profile.id,
        peerUsername: profile.profile.username,
        peerDisplayName: profile.profile.displayName,
        peerAvatarUrl: profile.profile.avatarUrl,
        peerAvatarStoragePath: profile.profile.avatarStoragePath,
      );
      if (!isClosed) emit(state.copyWith(chat: chat));
    } catch (_) {}
  }

  Future<void> _loadLocation(ViewedProfile profile) async {
    final cachedDistance = await _friendsRepository.getCachedUserDistance(
      _userId,
    );
    var isCachedDistanceFresh = await _friendsRepository
        .isCachedUserDistanceFresh(_userId);
    var distanceLocationUpdatedAt = cachedDistance?.updatedAt;
    if (cachedDistance != null && !isClosed) {
      emit(state.copyWith(distance: cachedDistance));
    }

    FriendLocation? exactLocation;
    if (profile.isFriend) {
      exactLocation = await _friendsRepository.getCachedFriendLocation(_userId);
      if (exactLocation != null && !isClosed) {
        emit(state.copyWith(location: exactLocation));
        if (distanceLocationUpdatedAt != exactLocation.updatedAt ||
            !isCachedDistanceFresh) {
          await _setLocalDistance(exactLocation);
          distanceLocationUpdatedAt = exactLocation.updatedAt;
          isCachedDistanceFresh = true;
        }
      }
      try {
        final lookup = await _friendsRepository.getFriendLocation(_userId);
        final received = lookup.location;
        if (received != null) {
          exactLocation = received;
          if (!isClosed) emit(state.copyWith(location: received));
          if (distanceLocationUpdatedAt != received.updatedAt ||
              !isCachedDistanceFresh) {
            await _setLocalDistance(received);
            distanceLocationUpdatedAt = received.updatedAt;
            isCachedDistanceFresh = true;
          }
        }
      } catch (_) {}
    }
    if (exactLocation != null) return;

    try {
      final distance = await _friendsRepository.getUserDistance(_userId);
      if (!isClosed) {
        emit(
          distance == null
              ? state.copyWith(clearDistance: true)
              : state.copyWith(distance: distance),
        );
      }
    } catch (_) {}
  }

  Future<void> _setLocalDistance(FriendLocation location) async {
    try {
      final cachedOwn = await _locationRepository.getCachedCurrentLocation();
      final own = cachedOwn == null
          ? await _locationRepository.getCurrentPosition()
          : null;
      final meters = Geolocator.distanceBetween(
        cachedOwn?.latitude ?? own!.latitude,
        cachedOwn?.longitude ?? own!.longitude,
        location.latitude,
        location.longitude,
      );
      final distance = meters < 1000
          ? UserDistance(
              value: meters.round(),
              unit: DistanceUnit.meters,
              updatedAt: location.updatedAt,
            )
          : UserDistance(
              value: (meters / 1000).round(),
              unit: DistanceUnit.kilometers,
              updatedAt: location.updatedAt,
            );
      await _friendsRepository.cacheUserDistance(_userId, distance);
      if (!isClosed) emit(state.copyWith(distance: distance));
    } catch (_) {
      try {
        final fallback = await _friendsRepository.getUserDistance(_userId);
        if (!isClosed && fallback != null) {
          emit(state.copyWith(distance: fallback));
        }
      } catch (_) {}
    }
  }

  Future<Chat> prepareChat() async {
    final existing = state.chat;
    if (existing != null) return existing;
    final profile = state.viewedProfile!.profile;
    return _chatsRepository.prepareDirectChat(
      peerId: profile.id,
      peerUsername: profile.username,
      peerDisplayName: profile.displayName,
      peerAvatarUrl: profile.avatarUrl,
      peerAvatarStoragePath: profile.avatarStoragePath,
    );
  }

  Future<void> sendRequest() => _performAction(() async {
    final profile = state.viewedProfile!;
    await _friendsRepository.sendRequest(
      FriendCandidate(
        id: profile.profile.id,
        username: profile.profile.username,
        displayName: profile.profile.displayName,
        avatarUrl: profile.profile.avatarUrl,
        avatarStoragePath: profile.profile.avatarStoragePath,
        friendCount: profile.friendCount,
        relationship: FriendRelationship.none,
      ),
    );
    await _reloadWithoutView();
  });

  Future<void> cancelRequest() => _performAction(() async {
    final requestId = state.viewedProfile?.requestId;
    if (requestId == null) return;
    await _friendsRepository.cancelRequest(requestId);
    await _reloadWithoutView();
  });

  Future<void> respondToRequest({required bool accept}) =>
      _performAction(() async {
        final requestId = state.viewedProfile?.requestId;
        if (requestId == null) return;
        await _friendsRepository.respondToRequest(requestId, accept: accept);
        await _reloadWithoutView();
      });

  Future<void> removeFriend() => _performAction(() async {
    await _friendsRepository.removeFriend(_userId);
    await _reloadWithoutView();
  });

  Future<void> toggleMute() => _performAction(() async {
    var chat = await prepareChat();
    if (chat.isDraft) {
      chat = await _chatsRepository.ensureDirectChat(_userId);
    }
    await _chatsRepository.toggleMute({chat.id});
    emit(state.copyWith(chat: chat.copyWith(isMuted: !chat.isMuted)));
  });

  Future<void> _reloadWithoutView() async {
    final refreshed = await _profileRepository.getViewedProfile(
      _userId,
      registerView: false,
    );
    if (!isClosed) {
      emit(state.copyWith(viewedProfile: refreshed));
      await _loadSupportingData(refreshed);
    }
  }

  Future<void> _performAction(Future<void> Function() action) async {
    if (state.isActionPending) return;
    emit(state.copyWith(isActionPending: true, clearActionError: true));
    try {
      await action();
    } catch (error) {
      if (!isClosed) emit(state.copyWith(actionError: error));
    } finally {
      if (!isClosed) emit(state.copyWith(isActionPending: false));
    }
  }

  void clearActionError() => emit(state.copyWith(clearActionError: true));

  void markOfflineNow() {
    final profile = state.viewedProfile;
    if (profile == null || !profile.showsLastSeen) return;
    emit(
      state.copyWith(
        viewedProfile: profile.copyWith(lastSeenAt: DateTime.now()),
      ),
    );
  }

  void _syncLastSeenFromChats(List<Chat> chats) {
    if (isClosed) return;
    Chat? chat;
    for (final candidate in chats) {
      if (candidate.peerId == _userId) {
        chat = candidate;
        break;
      }
    }
    final viewedProfile = state.viewedProfile;
    if (chat == null || viewedProfile == null) return;
    final identityChanged =
        viewedProfile.profile.username != chat.peerUsername ||
        viewedProfile.profile.displayName != chat.userName ||
        viewedProfile.profile.avatarUrl != chat.avatarUrl ||
        viewedProfile.profile.avatarStoragePath != chat.avatarStoragePath;
    final lastSeenChanged =
        viewedProfile.showsLastSeen != chat.showsLastSeen ||
        viewedProfile.lastSeenAt != chat.lastSeenAt;
    if (lastSeenChanged) {
      emit(
        state.copyWith(
          chat: chat,
          viewedProfile: viewedProfile.copyWith(
            showsLastSeen: chat.showsLastSeen,
            lastSeenAt: chat.lastSeenAt,
            clearLastSeenAt: !chat.showsLastSeen || chat.lastSeenAt == null,
          ),
        ),
      );
    }
    if (identityChanged) unawaited(_refreshProfileFromRealtime());
  }

  void _syncProfileFromFriendChange(String profileId) {
    if (profileId == _userId) unawaited(_refreshProfileFromRealtime());
  }

  Future<void> _refreshProfileFromRealtime() async {
    if (_isRealtimeProfileRefreshPending) return;
    _isRealtimeProfileRefreshPending = true;
    try {
      final refreshed = await _profileRepository.getViewedProfile(
        _userId,
        registerView: false,
      );
      if (!isClosed) {
        emit(state.copyWith(viewedProfile: refreshed));
        await _loadSupportingData(refreshed);
      }
    } catch (_) {
      // Keep the cached profile visible until the next successful update.
    } finally {
      _isRealtimeProfileRefreshPending = false;
    }
  }

  @override
  Future<void> close() async {
    await _chatsSubscription?.cancel();
    await _friendsSubscription?.cancel();
    return super.close();
  }
}
