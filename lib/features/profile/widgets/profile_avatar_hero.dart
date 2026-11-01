import 'package:flutter/material.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'profile_photo_image.dart';

class ProfileAvatarHero extends StatelessWidget {
  const ProfileAvatarHero({
    super.key,
    required this.child,
    this.profileId,
    this.avatarUrl,
    this.avatarStoragePath,
  });

  static const _snapshotLimit = 100;
  static final _snapshots = <String, ProfileAvatarHeroSnapshot>{};

  final Widget child;
  final String? profileId;
  final String? avatarUrl;
  final String? avatarStoragePath;

  static ProfileAvatarHeroSnapshot? snapshotFor(String profileId) =>
      _snapshots[profileId.trim()];

  @override
  Widget build(BuildContext context) {
    if (!Visibility.of(context)) return child;
    if ((avatarUrl == null || avatarUrl!.isEmpty) &&
        (avatarStoragePath == null || avatarStoragePath!.isEmpty)) {
      return child;
    }
    final photo = ProfilePhoto(
      position: 0,
      avatarUrl: avatarStoragePath == null ? avatarUrl : null,
      storagePath: avatarStoragePath,
    );
    _rememberSnapshot();
    return Hero(
      tag: profilePhotoHeroTag(photo),
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: buildProfilePhotoHeroFlight,
      child: child,
    );
  }

  void _rememberSnapshot() {
    final id = profileId?.trim();
    if (id == null || id.isEmpty) return;
    _snapshots.remove(id);
    _snapshots[id] = ProfileAvatarHeroSnapshot(
      avatarUrl: avatarUrl,
      avatarStoragePath: avatarStoragePath,
    );
    if (_snapshots.length > _snapshotLimit) {
      _snapshots.remove(_snapshots.keys.first);
    }
  }
}

class ProfileAvatarHeroSnapshot {
  const ProfileAvatarHeroSnapshot({this.avatarUrl, this.avatarStoragePath});

  final String? avatarUrl;
  final String? avatarStoragePath;
}
