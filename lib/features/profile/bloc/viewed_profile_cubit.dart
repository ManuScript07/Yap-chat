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

  Future<void> load() async {
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
    FriendLocation? exactLocation;
    if (profile.isFriend) {
      exactLocation = await _friendsRepository.getCachedFriendLocation(_userId);
      if (exactLocation != null && !isClosed) {
        emit(state.copyWith(location: exactLocation));
        await _setLocalDistance(exactLocation);
      }
      try {
        final lookup = await _friendsRepository.getFriendLocation(_userId);
        final received = lookup.location;
        if (received != null) {
          exactLocation = received;
          if (!isClosed) emit(state.copyWith(location: received));
          await _setLocalDistance(received);
        }
      } catch (_) {}
    }
    if (exactLocation != null) return;

    final cachedDistance = await _friendsRepository.getCachedUserDistance(
      _userId,
    );
    if (cachedDistance != null && !isClosed) {
      emit(state.copyWith(distance: cachedDistance));
    }
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
      final own = await _locationRepository.getCurrentPosition();
      final meters = Geolocator.distanceBetween(
        own.latitude,
        own.longitude,
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
}
