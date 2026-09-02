import 'package:equatable/equatable.dart';

class NearbyPerson extends Equatable {
  const NearbyPerson({
    required this.id,
    required this.username,
    required this.displayName,
    required this.activeUntil,
    this.avatarUrl,
    this.avatarStoragePath,
  });

  factory NearbyPerson.fromMap(Map<String, dynamic> value) => NearbyPerson(
    id: value['id'] as String,
    username: value['username'] as String? ?? '',
    displayName: value['display_name'] as String? ?? '',
    avatarUrl: value['avatar_url'] as String?,
    avatarStoragePath: value['avatar_storage_path'] as String?,
    activeUntil: DateTime.parse(value['active_until'] as String).toUtc(),
  );

  factory NearbyPerson.fromJson(Map<String, dynamic> value) => NearbyPerson(
    id: value['id'] as String? ?? '',
    username: value['username'] as String? ?? '',
    displayName: value['display_name'] as String? ?? '',
    avatarUrl: value['avatar_url'] as String?,
    avatarStoragePath: value['avatar_storage_path'] as String?,
    activeUntil: DateTime.tryParse(value['active_until'] as String? ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final DateTime activeUntil;

  bool get isStillActive => activeUntil.isAfter(DateTime.now().toUtc());

  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'avatar_storage_path': avatarStoragePath,
    'active_until': activeUntil.toIso8601String(),
  };

  @override
  List<Object?> get props => [id, username, displayName, avatarUrl, avatarStoragePath, activeUntil];
}
