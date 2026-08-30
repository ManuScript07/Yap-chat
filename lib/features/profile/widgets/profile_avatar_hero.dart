import 'package:flutter/material.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/features/profile/widgets/profile_photo_image.dart';

class ProfileAvatarHero extends StatelessWidget {
  const ProfileAvatarHero({
    super.key,
    required this.child,
    this.avatarUrl,
    this.avatarStoragePath,
  });

  final Widget child;
  final String? avatarUrl;
  final String? avatarStoragePath;

  @override
  Widget build(BuildContext context) {
    if ((avatarUrl == null || avatarUrl!.isEmpty) &&
        (avatarStoragePath == null || avatarStoragePath!.isEmpty)) {
      return child;
    }
    final photo = ProfilePhoto(
      position: 0,
      avatarUrl: avatarStoragePath == null ? avatarUrl : null,
      storagePath: avatarStoragePath,
    );
    return Hero(
      tag: profilePhotoHeroTag(photo),
      transitionOnUserGestures: true,
      child: child,
    );
  }
}
