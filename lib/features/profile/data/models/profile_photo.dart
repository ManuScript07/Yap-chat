import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class ProfilePhoto extends Equatable {
  const ProfilePhoto({
    required this.position,
    this.avatarUrl,
    this.storagePath,
    this.bytes,
    this.updatedAt,
  });

  final int position;
  final String? avatarUrl;
  final String? storagePath;
  final Uint8List? bytes;
  final DateTime? updatedAt;

  bool get needsUpload =>
      bytes != null && storagePath == null && avatarUrl == null;

  String get identity =>
      storagePath ?? avatarUrl ?? 'draft-${identityHashCode(bytes)}';

  ProfilePhoto copyWith({
    int? position,
    String? avatarUrl,
    String? storagePath,
    Uint8List? bytes,
    DateTime? updatedAt,
    bool clearAvatarUrl = false,
    bool clearStoragePath = false,
    bool clearBytes = false,
  }) {
    return ProfilePhoto(
      position: position ?? this.position,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
      storagePath: clearStoragePath ? null : storagePath ?? this.storagePath,
      bytes: clearBytes ? null : bytes ?? this.bytes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    position,
    avatarUrl,
    storagePath,
    bytes,
    updatedAt,
  ];
}
