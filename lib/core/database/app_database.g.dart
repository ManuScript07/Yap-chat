// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedProfilesTable extends CachedProfiles
    with TableInfo<$CachedProfilesTable, CachedProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _birthDateMeta = const VerificationMeta(
    'birthDate',
  );
  @override
  late final GeneratedColumn<DateTime> birthDate = GeneratedColumn<DateTime>(
    'birth_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarStoragePathMeta = const VerificationMeta(
    'avatarStoragePath',
  );
  @override
  late final GeneratedColumn<String> avatarStoragePath =
      GeneratedColumn<String>(
        'avatar_storage_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _avatarBytesMeta = const VerificationMeta(
    'avatarBytes',
  );
  @override
  late final GeneratedColumn<Uint8List> avatarBytes =
      GeneratedColumn<Uint8List>(
        'avatar_bytes',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _avatarUpdatedAtMeta = const VerificationMeta(
    'avatarUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> avatarUpdatedAt =
      GeneratedColumn<DateTime>(
        'avatar_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _yandexAvatarDisabledMeta =
      const VerificationMeta('yandexAvatarDisabled');
  @override
  late final GeneratedColumn<bool> yandexAvatarDisabled = GeneratedColumn<bool>(
    'yandex_avatar_disabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("yandex_avatar_disabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bioMeta = const VerificationMeta('bio');
  @override
  late final GeneratedColumn<String> bio = GeneratedColumn<String>(
    'bio',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _onboardingCompletedMeta =
      const VerificationMeta('onboardingCompleted');
  @override
  late final GeneratedColumn<bool> onboardingCompleted = GeneratedColumn<bool>(
    'onboarding_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("onboarding_completed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _termsAcceptedAtMeta = const VerificationMeta(
    'termsAcceptedAt',
  );
  @override
  late final GeneratedColumn<DateTime> termsAcceptedAt =
      GeneratedColumn<DateTime>(
        'terms_accepted_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _privacyAcceptedAtMeta = const VerificationMeta(
    'privacyAcceptedAt',
  );
  @override
  late final GeneratedColumn<DateTime> privacyAcceptedAt =
      GeneratedColumn<DateTime>(
        'privacy_accepted_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    username,
    displayName,
    birthDate,
    avatarUrl,
    avatarStoragePath,
    avatarBytes,
    avatarUpdatedAt,
    yandexAvatarDisabled,
    gender,
    bio,
    onboardingCompleted,
    termsAcceptedAt,
    privacyAcceptedAt,
    createdAt,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('birth_date')) {
      context.handle(
        _birthDateMeta,
        birthDate.isAcceptableOrUnknown(data['birth_date']!, _birthDateMeta),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('avatar_storage_path')) {
      context.handle(
        _avatarStoragePathMeta,
        avatarStoragePath.isAcceptableOrUnknown(
          data['avatar_storage_path']!,
          _avatarStoragePathMeta,
        ),
      );
    }
    if (data.containsKey('avatar_bytes')) {
      context.handle(
        _avatarBytesMeta,
        avatarBytes.isAcceptableOrUnknown(
          data['avatar_bytes']!,
          _avatarBytesMeta,
        ),
      );
    }
    if (data.containsKey('avatar_updated_at')) {
      context.handle(
        _avatarUpdatedAtMeta,
        avatarUpdatedAt.isAcceptableOrUnknown(
          data['avatar_updated_at']!,
          _avatarUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('yandex_avatar_disabled')) {
      context.handle(
        _yandexAvatarDisabledMeta,
        yandexAvatarDisabled.isAcceptableOrUnknown(
          data['yandex_avatar_disabled']!,
          _yandexAvatarDisabledMeta,
        ),
      );
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    } else if (isInserting) {
      context.missing(_genderMeta);
    }
    if (data.containsKey('bio')) {
      context.handle(
        _bioMeta,
        bio.isAcceptableOrUnknown(data['bio']!, _bioMeta),
      );
    } else if (isInserting) {
      context.missing(_bioMeta);
    }
    if (data.containsKey('onboarding_completed')) {
      context.handle(
        _onboardingCompletedMeta,
        onboardingCompleted.isAcceptableOrUnknown(
          data['onboarding_completed']!,
          _onboardingCompletedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_onboardingCompletedMeta);
    }
    if (data.containsKey('terms_accepted_at')) {
      context.handle(
        _termsAcceptedAtMeta,
        termsAcceptedAt.isAcceptableOrUnknown(
          data['terms_accepted_at']!,
          _termsAcceptedAtMeta,
        ),
      );
    }
    if (data.containsKey('privacy_accepted_at')) {
      context.handle(
        _privacyAcceptedAtMeta,
        privacyAcceptedAt.isAcceptableOrUnknown(
          data['privacy_accepted_at']!,
          _privacyAcceptedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  CachedProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProfile(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      birthDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}birth_date'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      avatarStoragePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_storage_path'],
      ),
      avatarBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}avatar_bytes'],
      ),
      avatarUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}avatar_updated_at'],
      ),
      yandexAvatarDisabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}yandex_avatar_disabled'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      )!,
      bio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bio'],
      )!,
      onboardingCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}onboarding_completed'],
      )!,
      termsAcceptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}terms_accepted_at'],
      ),
      privacyAcceptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}privacy_accepted_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedProfilesTable createAlias(String alias) {
    return $CachedProfilesTable(attachedDatabase, alias);
  }
}

class CachedProfile extends DataClass implements Insertable<CachedProfile> {
  final String userId;
  final String username;
  final String displayName;
  final DateTime? birthDate;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final Uint8List? avatarBytes;
  final DateTime? avatarUpdatedAt;
  final bool yandexAvatarDisabled;
  final String gender;
  final String bio;
  final bool onboardingCompleted;
  final DateTime? termsAcceptedAt;
  final DateTime? privacyAcceptedAt;
  final DateTime? createdAt;
  final DateTime cachedAt;
  const CachedProfile({
    required this.userId,
    required this.username,
    required this.displayName,
    this.birthDate,
    this.avatarUrl,
    this.avatarStoragePath,
    this.avatarBytes,
    this.avatarUpdatedAt,
    required this.yandexAvatarDisabled,
    required this.gender,
    required this.bio,
    required this.onboardingCompleted,
    this.termsAcceptedAt,
    this.privacyAcceptedAt,
    this.createdAt,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['username'] = Variable<String>(username);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || birthDate != null) {
      map['birth_date'] = Variable<DateTime>(birthDate);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || avatarStoragePath != null) {
      map['avatar_storage_path'] = Variable<String>(avatarStoragePath);
    }
    if (!nullToAbsent || avatarBytes != null) {
      map['avatar_bytes'] = Variable<Uint8List>(avatarBytes);
    }
    if (!nullToAbsent || avatarUpdatedAt != null) {
      map['avatar_updated_at'] = Variable<DateTime>(avatarUpdatedAt);
    }
    map['yandex_avatar_disabled'] = Variable<bool>(yandexAvatarDisabled);
    map['gender'] = Variable<String>(gender);
    map['bio'] = Variable<String>(bio);
    map['onboarding_completed'] = Variable<bool>(onboardingCompleted);
    if (!nullToAbsent || termsAcceptedAt != null) {
      map['terms_accepted_at'] = Variable<DateTime>(termsAcceptedAt);
    }
    if (!nullToAbsent || privacyAcceptedAt != null) {
      map['privacy_accepted_at'] = Variable<DateTime>(privacyAcceptedAt);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedProfilesCompanion toCompanion(bool nullToAbsent) {
    return CachedProfilesCompanion(
      userId: Value(userId),
      username: Value(username),
      displayName: Value(displayName),
      birthDate: birthDate == null && nullToAbsent
          ? const Value.absent()
          : Value(birthDate),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      avatarStoragePath: avatarStoragePath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarStoragePath),
      avatarBytes: avatarBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarBytes),
      avatarUpdatedAt: avatarUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUpdatedAt),
      yandexAvatarDisabled: Value(yandexAvatarDisabled),
      gender: Value(gender),
      bio: Value(bio),
      onboardingCompleted: Value(onboardingCompleted),
      termsAcceptedAt: termsAcceptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(termsAcceptedAt),
      privacyAcceptedAt: privacyAcceptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(privacyAcceptedAt),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProfile(
      userId: serializer.fromJson<String>(json['userId']),
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String>(json['displayName']),
      birthDate: serializer.fromJson<DateTime?>(json['birthDate']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      avatarStoragePath: serializer.fromJson<String?>(
        json['avatarStoragePath'],
      ),
      avatarBytes: serializer.fromJson<Uint8List?>(json['avatarBytes']),
      avatarUpdatedAt: serializer.fromJson<DateTime?>(json['avatarUpdatedAt']),
      yandexAvatarDisabled: serializer.fromJson<bool>(
        json['yandexAvatarDisabled'],
      ),
      gender: serializer.fromJson<String>(json['gender']),
      bio: serializer.fromJson<String>(json['bio']),
      onboardingCompleted: serializer.fromJson<bool>(
        json['onboardingCompleted'],
      ),
      termsAcceptedAt: serializer.fromJson<DateTime?>(json['termsAcceptedAt']),
      privacyAcceptedAt: serializer.fromJson<DateTime?>(
        json['privacyAcceptedAt'],
      ),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String>(displayName),
      'birthDate': serializer.toJson<DateTime?>(birthDate),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'avatarStoragePath': serializer.toJson<String?>(avatarStoragePath),
      'avatarBytes': serializer.toJson<Uint8List?>(avatarBytes),
      'avatarUpdatedAt': serializer.toJson<DateTime?>(avatarUpdatedAt),
      'yandexAvatarDisabled': serializer.toJson<bool>(yandexAvatarDisabled),
      'gender': serializer.toJson<String>(gender),
      'bio': serializer.toJson<String>(bio),
      'onboardingCompleted': serializer.toJson<bool>(onboardingCompleted),
      'termsAcceptedAt': serializer.toJson<DateTime?>(termsAcceptedAt),
      'privacyAcceptedAt': serializer.toJson<DateTime?>(privacyAcceptedAt),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedProfile copyWith({
    String? userId,
    String? username,
    String? displayName,
    Value<DateTime?> birthDate = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> avatarStoragePath = const Value.absent(),
    Value<Uint8List?> avatarBytes = const Value.absent(),
    Value<DateTime?> avatarUpdatedAt = const Value.absent(),
    bool? yandexAvatarDisabled,
    String? gender,
    String? bio,
    bool? onboardingCompleted,
    Value<DateTime?> termsAcceptedAt = const Value.absent(),
    Value<DateTime?> privacyAcceptedAt = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    DateTime? cachedAt,
  }) => CachedProfile(
    userId: userId ?? this.userId,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    birthDate: birthDate.present ? birthDate.value : this.birthDate,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    avatarStoragePath: avatarStoragePath.present
        ? avatarStoragePath.value
        : this.avatarStoragePath,
    avatarBytes: avatarBytes.present ? avatarBytes.value : this.avatarBytes,
    avatarUpdatedAt: avatarUpdatedAt.present
        ? avatarUpdatedAt.value
        : this.avatarUpdatedAt,
    yandexAvatarDisabled: yandexAvatarDisabled ?? this.yandexAvatarDisabled,
    gender: gender ?? this.gender,
    bio: bio ?? this.bio,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    termsAcceptedAt: termsAcceptedAt.present
        ? termsAcceptedAt.value
        : this.termsAcceptedAt,
    privacyAcceptedAt: privacyAcceptedAt.present
        ? privacyAcceptedAt.value
        : this.privacyAcceptedAt,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedProfile copyWithCompanion(CachedProfilesCompanion data) {
    return CachedProfile(
      userId: data.userId.present ? data.userId.value : this.userId,
      username: data.username.present ? data.username.value : this.username,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      birthDate: data.birthDate.present ? data.birthDate.value : this.birthDate,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      avatarStoragePath: data.avatarStoragePath.present
          ? data.avatarStoragePath.value
          : this.avatarStoragePath,
      avatarBytes: data.avatarBytes.present
          ? data.avatarBytes.value
          : this.avatarBytes,
      avatarUpdatedAt: data.avatarUpdatedAt.present
          ? data.avatarUpdatedAt.value
          : this.avatarUpdatedAt,
      yandexAvatarDisabled: data.yandexAvatarDisabled.present
          ? data.yandexAvatarDisabled.value
          : this.yandexAvatarDisabled,
      gender: data.gender.present ? data.gender.value : this.gender,
      bio: data.bio.present ? data.bio.value : this.bio,
      onboardingCompleted: data.onboardingCompleted.present
          ? data.onboardingCompleted.value
          : this.onboardingCompleted,
      termsAcceptedAt: data.termsAcceptedAt.present
          ? data.termsAcceptedAt.value
          : this.termsAcceptedAt,
      privacyAcceptedAt: data.privacyAcceptedAt.present
          ? data.privacyAcceptedAt.value
          : this.privacyAcceptedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfile(')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('birthDate: $birthDate, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('avatarStoragePath: $avatarStoragePath, ')
          ..write('avatarBytes: $avatarBytes, ')
          ..write('avatarUpdatedAt: $avatarUpdatedAt, ')
          ..write('yandexAvatarDisabled: $yandexAvatarDisabled, ')
          ..write('gender: $gender, ')
          ..write('bio: $bio, ')
          ..write('onboardingCompleted: $onboardingCompleted, ')
          ..write('termsAcceptedAt: $termsAcceptedAt, ')
          ..write('privacyAcceptedAt: $privacyAcceptedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    username,
    displayName,
    birthDate,
    avatarUrl,
    avatarStoragePath,
    $driftBlobEquality.hash(avatarBytes),
    avatarUpdatedAt,
    yandexAvatarDisabled,
    gender,
    bio,
    onboardingCompleted,
    termsAcceptedAt,
    privacyAcceptedAt,
    createdAt,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProfile &&
          other.userId == this.userId &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.birthDate == this.birthDate &&
          other.avatarUrl == this.avatarUrl &&
          other.avatarStoragePath == this.avatarStoragePath &&
          $driftBlobEquality.equals(other.avatarBytes, this.avatarBytes) &&
          other.avatarUpdatedAt == this.avatarUpdatedAt &&
          other.yandexAvatarDisabled == this.yandexAvatarDisabled &&
          other.gender == this.gender &&
          other.bio == this.bio &&
          other.onboardingCompleted == this.onboardingCompleted &&
          other.termsAcceptedAt == this.termsAcceptedAt &&
          other.privacyAcceptedAt == this.privacyAcceptedAt &&
          other.createdAt == this.createdAt &&
          other.cachedAt == this.cachedAt);
}

class CachedProfilesCompanion extends UpdateCompanion<CachedProfile> {
  final Value<String> userId;
  final Value<String> username;
  final Value<String> displayName;
  final Value<DateTime?> birthDate;
  final Value<String?> avatarUrl;
  final Value<String?> avatarStoragePath;
  final Value<Uint8List?> avatarBytes;
  final Value<DateTime?> avatarUpdatedAt;
  final Value<bool> yandexAvatarDisabled;
  final Value<String> gender;
  final Value<String> bio;
  final Value<bool> onboardingCompleted;
  final Value<DateTime?> termsAcceptedAt;
  final Value<DateTime?> privacyAcceptedAt;
  final Value<DateTime?> createdAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedProfilesCompanion({
    this.userId = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.avatarStoragePath = const Value.absent(),
    this.avatarBytes = const Value.absent(),
    this.avatarUpdatedAt = const Value.absent(),
    this.yandexAvatarDisabled = const Value.absent(),
    this.gender = const Value.absent(),
    this.bio = const Value.absent(),
    this.onboardingCompleted = const Value.absent(),
    this.termsAcceptedAt = const Value.absent(),
    this.privacyAcceptedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProfilesCompanion.insert({
    required String userId,
    required String username,
    required String displayName,
    this.birthDate = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.avatarStoragePath = const Value.absent(),
    this.avatarBytes = const Value.absent(),
    this.avatarUpdatedAt = const Value.absent(),
    this.yandexAvatarDisabled = const Value.absent(),
    required String gender,
    required String bio,
    required bool onboardingCompleted,
    this.termsAcceptedAt = const Value.absent(),
    this.privacyAcceptedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       username = Value(username),
       displayName = Value(displayName),
       gender = Value(gender),
       bio = Value(bio),
       onboardingCompleted = Value(onboardingCompleted),
       cachedAt = Value(cachedAt);
  static Insertable<CachedProfile> custom({
    Expression<String>? userId,
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<DateTime>? birthDate,
    Expression<String>? avatarUrl,
    Expression<String>? avatarStoragePath,
    Expression<Uint8List>? avatarBytes,
    Expression<DateTime>? avatarUpdatedAt,
    Expression<bool>? yandexAvatarDisabled,
    Expression<String>? gender,
    Expression<String>? bio,
    Expression<bool>? onboardingCompleted,
    Expression<DateTime>? termsAcceptedAt,
    Expression<DateTime>? privacyAcceptedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (birthDate != null) 'birth_date': birthDate,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (avatarStoragePath != null) 'avatar_storage_path': avatarStoragePath,
      if (avatarBytes != null) 'avatar_bytes': avatarBytes,
      if (avatarUpdatedAt != null) 'avatar_updated_at': avatarUpdatedAt,
      if (yandexAvatarDisabled != null)
        'yandex_avatar_disabled': yandexAvatarDisabled,
      if (gender != null) 'gender': gender,
      if (bio != null) 'bio': bio,
      if (onboardingCompleted != null)
        'onboarding_completed': onboardingCompleted,
      if (termsAcceptedAt != null) 'terms_accepted_at': termsAcceptedAt,
      if (privacyAcceptedAt != null) 'privacy_accepted_at': privacyAcceptedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProfilesCompanion copyWith({
    Value<String>? userId,
    Value<String>? username,
    Value<String>? displayName,
    Value<DateTime?>? birthDate,
    Value<String?>? avatarUrl,
    Value<String?>? avatarStoragePath,
    Value<Uint8List?>? avatarBytes,
    Value<DateTime?>? avatarUpdatedAt,
    Value<bool>? yandexAvatarDisabled,
    Value<String>? gender,
    Value<String>? bio,
    Value<bool>? onboardingCompleted,
    Value<DateTime?>? termsAcceptedAt,
    Value<DateTime?>? privacyAcceptedAt,
    Value<DateTime?>? createdAt,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedProfilesCompanion(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      birthDate: birthDate ?? this.birthDate,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarStoragePath: avatarStoragePath ?? this.avatarStoragePath,
      avatarBytes: avatarBytes ?? this.avatarBytes,
      avatarUpdatedAt: avatarUpdatedAt ?? this.avatarUpdatedAt,
      yandexAvatarDisabled: yandexAvatarDisabled ?? this.yandexAvatarDisabled,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      privacyAcceptedAt: privacyAcceptedAt ?? this.privacyAcceptedAt,
      createdAt: createdAt ?? this.createdAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (birthDate.present) {
      map['birth_date'] = Variable<DateTime>(birthDate.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (avatarStoragePath.present) {
      map['avatar_storage_path'] = Variable<String>(avatarStoragePath.value);
    }
    if (avatarBytes.present) {
      map['avatar_bytes'] = Variable<Uint8List>(avatarBytes.value);
    }
    if (avatarUpdatedAt.present) {
      map['avatar_updated_at'] = Variable<DateTime>(avatarUpdatedAt.value);
    }
    if (yandexAvatarDisabled.present) {
      map['yandex_avatar_disabled'] = Variable<bool>(
        yandexAvatarDisabled.value,
      );
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (bio.present) {
      map['bio'] = Variable<String>(bio.value);
    }
    if (onboardingCompleted.present) {
      map['onboarding_completed'] = Variable<bool>(onboardingCompleted.value);
    }
    if (termsAcceptedAt.present) {
      map['terms_accepted_at'] = Variable<DateTime>(termsAcceptedAt.value);
    }
    if (privacyAcceptedAt.present) {
      map['privacy_accepted_at'] = Variable<DateTime>(privacyAcceptedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfilesCompanion(')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('birthDate: $birthDate, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('avatarStoragePath: $avatarStoragePath, ')
          ..write('avatarBytes: $avatarBytes, ')
          ..write('avatarUpdatedAt: $avatarUpdatedAt, ')
          ..write('yandexAvatarDisabled: $yandexAvatarDisabled, ')
          ..write('gender: $gender, ')
          ..write('bio: $bio, ')
          ..write('onboardingCompleted: $onboardingCompleted, ')
          ..write('termsAcceptedAt: $termsAcceptedAt, ')
          ..write('privacyAcceptedAt: $privacyAcceptedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedProfilePhotosTable extends CachedProfilePhotos
    with TableInfo<$CachedProfilePhotosTable, CachedProfilePhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProfilePhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storagePathMeta = const VerificationMeta(
    'storagePath',
  );
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
    'storage_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    position,
    avatarUrl,
    storagePath,
    bytes,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_profile_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProfilePhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('storage_path')) {
      context.handle(
        _storagePathMeta,
        storagePath.isAcceptableOrUnknown(
          data['storage_path']!,
          _storagePathMeta,
        ),
      );
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, position};
  @override
  CachedProfilePhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProfilePhoto(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      storagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_path'],
      ),
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $CachedProfilePhotosTable createAlias(String alias) {
    return $CachedProfilePhotosTable(attachedDatabase, alias);
  }
}

class CachedProfilePhoto extends DataClass
    implements Insertable<CachedProfilePhoto> {
  final String userId;
  final int position;
  final String? avatarUrl;
  final String? storagePath;
  final Uint8List? bytes;
  final DateTime? updatedAt;
  const CachedProfilePhoto({
    required this.userId,
    required this.position,
    this.avatarUrl,
    this.storagePath,
    this.bytes,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['position'] = Variable<int>(position);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || storagePath != null) {
      map['storage_path'] = Variable<String>(storagePath);
    }
    if (!nullToAbsent || bytes != null) {
      map['bytes'] = Variable<Uint8List>(bytes);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  CachedProfilePhotosCompanion toCompanion(bool nullToAbsent) {
    return CachedProfilePhotosCompanion(
      userId: Value(userId),
      position: Value(position),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      storagePath: storagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(storagePath),
      bytes: bytes == null && nullToAbsent
          ? const Value.absent()
          : Value(bytes),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory CachedProfilePhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProfilePhoto(
      userId: serializer.fromJson<String>(json['userId']),
      position: serializer.fromJson<int>(json['position']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      storagePath: serializer.fromJson<String?>(json['storagePath']),
      bytes: serializer.fromJson<Uint8List?>(json['bytes']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'position': serializer.toJson<int>(position),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'storagePath': serializer.toJson<String?>(storagePath),
      'bytes': serializer.toJson<Uint8List?>(bytes),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  CachedProfilePhoto copyWith({
    String? userId,
    int? position,
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> storagePath = const Value.absent(),
    Value<Uint8List?> bytes = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => CachedProfilePhoto(
    userId: userId ?? this.userId,
    position: position ?? this.position,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    storagePath: storagePath.present ? storagePath.value : this.storagePath,
    bytes: bytes.present ? bytes.value : this.bytes,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  CachedProfilePhoto copyWithCompanion(CachedProfilePhotosCompanion data) {
    return CachedProfilePhoto(
      userId: data.userId.present ? data.userId.value : this.userId,
      position: data.position.present ? data.position.value : this.position,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      storagePath: data.storagePath.present
          ? data.storagePath.value
          : this.storagePath,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfilePhoto(')
          ..write('userId: $userId, ')
          ..write('position: $position, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('storagePath: $storagePath, ')
          ..write('bytes: $bytes, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    position,
    avatarUrl,
    storagePath,
    $driftBlobEquality.hash(bytes),
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProfilePhoto &&
          other.userId == this.userId &&
          other.position == this.position &&
          other.avatarUrl == this.avatarUrl &&
          other.storagePath == this.storagePath &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.updatedAt == this.updatedAt);
}

class CachedProfilePhotosCompanion extends UpdateCompanion<CachedProfilePhoto> {
  final Value<String> userId;
  final Value<int> position;
  final Value<String?> avatarUrl;
  final Value<String?> storagePath;
  final Value<Uint8List?> bytes;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const CachedProfilePhotosCompanion({
    this.userId = const Value.absent(),
    this.position = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.bytes = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProfilePhotosCompanion.insert({
    required String userId,
    required int position,
    this.avatarUrl = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.bytes = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       position = Value(position);
  static Insertable<CachedProfilePhoto> custom({
    Expression<String>? userId,
    Expression<int>? position,
    Expression<String>? avatarUrl,
    Expression<String>? storagePath,
    Expression<Uint8List>? bytes,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (position != null) 'position': position,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (storagePath != null) 'storage_path': storagePath,
      if (bytes != null) 'bytes': bytes,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProfilePhotosCompanion copyWith({
    Value<String>? userId,
    Value<int>? position,
    Value<String?>? avatarUrl,
    Value<String?>? storagePath,
    Value<Uint8List?>? bytes,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedProfilePhotosCompanion(
      userId: userId ?? this.userId,
      position: position ?? this.position,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      storagePath: storagePath ?? this.storagePath,
      bytes: bytes ?? this.bytes,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfilePhotosCompanion(')
          ..write('userId: $userId, ')
          ..write('position: $position, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('storagePath: $storagePath, ')
          ..write('bytes: $bytes, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedChatsTable extends CachedChats
    with TableInfo<$CachedChatsTable, CachedChat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedChatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerUsernameMeta = const VerificationMeta(
    'peerUsername',
  );
  @override
  late final GeneratedColumn<String> peerUsername = GeneratedColumn<String>(
    'peer_username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDisplayNameMeta = const VerificationMeta(
    'peerDisplayName',
  );
  @override
  late final GeneratedColumn<String> peerDisplayName = GeneratedColumn<String>(
    'peer_display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerAvatarUrlMeta = const VerificationMeta(
    'peerAvatarUrl',
  );
  @override
  late final GeneratedColumn<String> peerAvatarUrl = GeneratedColumn<String>(
    'peer_avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerAvatarStoragePathMeta =
      const VerificationMeta('peerAvatarStoragePath');
  @override
  late final GeneratedColumn<String> peerAvatarStoragePath =
      GeneratedColumn<String>(
        'peer_avatar_storage_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastMessageIdMeta = const VerificationMeta(
    'lastMessageId',
  );
  @override
  late final GeneratedColumn<String> lastMessageId = GeneratedColumn<String>(
    'last_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageMeta = const VerificationMeta(
    'lastMessage',
  );
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
    'last_message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastMessageTypeMeta = const VerificationMeta(
    'lastMessageType',
  );
  @override
  late final GeneratedColumn<String> lastMessageType = GeneratedColumn<String>(
    'last_message_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastMessageTimeMeta = const VerificationMeta(
    'lastMessageTime',
  );
  @override
  late final GeneratedColumn<DateTime> lastMessageTime =
      GeneratedColumn<DateTime>(
        'last_message_time',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isLastMessageFromMeMeta =
      const VerificationMeta('isLastMessageFromMe');
  @override
  late final GeneratedColumn<bool> isLastMessageFromMe = GeneratedColumn<bool>(
    'is_last_message_from_me',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_last_message_from_me" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isMutedMeta = const VerificationMeta(
    'isMuted',
  );
  @override
  late final GeneratedColumn<bool> isMuted = GeneratedColumn<bool>(
    'is_muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_muted" IN (0, 1))',
    ),
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _showsLastSeenMeta = const VerificationMeta(
    'showsLastSeen',
  );
  @override
  late final GeneratedColumn<bool> showsLastSeen = GeneratedColumn<bool>(
    'shows_last_seen',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("shows_last_seen" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    id,
    peerId,
    peerUsername,
    peerDisplayName,
    peerAvatarUrl,
    peerAvatarStoragePath,
    lastMessageId,
    lastMessage,
    lastMessageType,
    lastMessageTime,
    unreadCount,
    isLastMessageFromMe,
    isMuted,
    lastSeenAt,
    showsLastSeen,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_chats';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedChat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('peer_username')) {
      context.handle(
        _peerUsernameMeta,
        peerUsername.isAcceptableOrUnknown(
          data['peer_username']!,
          _peerUsernameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerUsernameMeta);
    }
    if (data.containsKey('peer_display_name')) {
      context.handle(
        _peerDisplayNameMeta,
        peerDisplayName.isAcceptableOrUnknown(
          data['peer_display_name']!,
          _peerDisplayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerDisplayNameMeta);
    }
    if (data.containsKey('peer_avatar_url')) {
      context.handle(
        _peerAvatarUrlMeta,
        peerAvatarUrl.isAcceptableOrUnknown(
          data['peer_avatar_url']!,
          _peerAvatarUrlMeta,
        ),
      );
    }
    if (data.containsKey('peer_avatar_storage_path')) {
      context.handle(
        _peerAvatarStoragePathMeta,
        peerAvatarStoragePath.isAcceptableOrUnknown(
          data['peer_avatar_storage_path']!,
          _peerAvatarStoragePathMeta,
        ),
      );
    }
    if (data.containsKey('last_message_id')) {
      context.handle(
        _lastMessageIdMeta,
        lastMessageId.isAcceptableOrUnknown(
          data['last_message_id']!,
          _lastMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('last_message')) {
      context.handle(
        _lastMessageMeta,
        lastMessage.isAcceptableOrUnknown(
          data['last_message']!,
          _lastMessageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastMessageMeta);
    }
    if (data.containsKey('last_message_type')) {
      context.handle(
        _lastMessageTypeMeta,
        lastMessageType.isAcceptableOrUnknown(
          data['last_message_type']!,
          _lastMessageTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastMessageTypeMeta);
    }
    if (data.containsKey('last_message_time')) {
      context.handle(
        _lastMessageTimeMeta,
        lastMessageTime.isAcceptableOrUnknown(
          data['last_message_time']!,
          _lastMessageTimeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastMessageTimeMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unreadCountMeta);
    }
    if (data.containsKey('is_last_message_from_me')) {
      context.handle(
        _isLastMessageFromMeMeta,
        isLastMessageFromMe.isAcceptableOrUnknown(
          data['is_last_message_from_me']!,
          _isLastMessageFromMeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isLastMessageFromMeMeta);
    }
    if (data.containsKey('is_muted')) {
      context.handle(
        _isMutedMeta,
        isMuted.isAcceptableOrUnknown(data['is_muted']!, _isMutedMeta),
      );
    } else if (isInserting) {
      context.missing(_isMutedMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('shows_last_seen')) {
      context.handle(
        _showsLastSeenMeta,
        showsLastSeen.isAcceptableOrUnknown(
          data['shows_last_seen']!,
          _showsLastSeenMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, id};
  @override
  CachedChat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedChat(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      peerUsername: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_username'],
      )!,
      peerDisplayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_display_name'],
      )!,
      peerAvatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_avatar_url'],
      ),
      peerAvatarStoragePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_avatar_storage_path'],
      ),
      lastMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_id'],
      ),
      lastMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message'],
      )!,
      lastMessageType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_type'],
      )!,
      lastMessageTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_message_time'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      isLastMessageFromMe: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_last_message_from_me'],
      )!,
      isMuted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_muted'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      ),
      showsLastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}shows_last_seen'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedChatsTable createAlias(String alias) {
    return $CachedChatsTable(attachedDatabase, alias);
  }
}

class CachedChat extends DataClass implements Insertable<CachedChat> {
  final String ownerUserId;
  final String id;
  final String peerId;
  final String peerUsername;
  final String peerDisplayName;
  final String? peerAvatarUrl;
  final String? peerAvatarStoragePath;
  final String? lastMessageId;
  final String lastMessage;
  final String lastMessageType;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isLastMessageFromMe;
  final bool isMuted;
  final DateTime? lastSeenAt;
  final bool showsLastSeen;
  final DateTime cachedAt;
  const CachedChat({
    required this.ownerUserId,
    required this.id,
    required this.peerId,
    required this.peerUsername,
    required this.peerDisplayName,
    this.peerAvatarUrl,
    this.peerAvatarStoragePath,
    this.lastMessageId,
    required this.lastMessage,
    required this.lastMessageType,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.isLastMessageFromMe,
    required this.isMuted,
    this.lastSeenAt,
    required this.showsLastSeen,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['id'] = Variable<String>(id);
    map['peer_id'] = Variable<String>(peerId);
    map['peer_username'] = Variable<String>(peerUsername);
    map['peer_display_name'] = Variable<String>(peerDisplayName);
    if (!nullToAbsent || peerAvatarUrl != null) {
      map['peer_avatar_url'] = Variable<String>(peerAvatarUrl);
    }
    if (!nullToAbsent || peerAvatarStoragePath != null) {
      map['peer_avatar_storage_path'] = Variable<String>(peerAvatarStoragePath);
    }
    if (!nullToAbsent || lastMessageId != null) {
      map['last_message_id'] = Variable<String>(lastMessageId);
    }
    map['last_message'] = Variable<String>(lastMessage);
    map['last_message_type'] = Variable<String>(lastMessageType);
    map['last_message_time'] = Variable<DateTime>(lastMessageTime);
    map['unread_count'] = Variable<int>(unreadCount);
    map['is_last_message_from_me'] = Variable<bool>(isLastMessageFromMe);
    map['is_muted'] = Variable<bool>(isMuted);
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    map['shows_last_seen'] = Variable<bool>(showsLastSeen);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedChatsCompanion toCompanion(bool nullToAbsent) {
    return CachedChatsCompanion(
      ownerUserId: Value(ownerUserId),
      id: Value(id),
      peerId: Value(peerId),
      peerUsername: Value(peerUsername),
      peerDisplayName: Value(peerDisplayName),
      peerAvatarUrl: peerAvatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(peerAvatarUrl),
      peerAvatarStoragePath: peerAvatarStoragePath == null && nullToAbsent
          ? const Value.absent()
          : Value(peerAvatarStoragePath),
      lastMessageId: lastMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageId),
      lastMessage: Value(lastMessage),
      lastMessageType: Value(lastMessageType),
      lastMessageTime: Value(lastMessageTime),
      unreadCount: Value(unreadCount),
      isLastMessageFromMe: Value(isLastMessageFromMe),
      isMuted: Value(isMuted),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      showsLastSeen: Value(showsLastSeen),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedChat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedChat(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      id: serializer.fromJson<String>(json['id']),
      peerId: serializer.fromJson<String>(json['peerId']),
      peerUsername: serializer.fromJson<String>(json['peerUsername']),
      peerDisplayName: serializer.fromJson<String>(json['peerDisplayName']),
      peerAvatarUrl: serializer.fromJson<String?>(json['peerAvatarUrl']),
      peerAvatarStoragePath: serializer.fromJson<String?>(
        json['peerAvatarStoragePath'],
      ),
      lastMessageId: serializer.fromJson<String?>(json['lastMessageId']),
      lastMessage: serializer.fromJson<String>(json['lastMessage']),
      lastMessageType: serializer.fromJson<String>(json['lastMessageType']),
      lastMessageTime: serializer.fromJson<DateTime>(json['lastMessageTime']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      isLastMessageFromMe: serializer.fromJson<bool>(
        json['isLastMessageFromMe'],
      ),
      isMuted: serializer.fromJson<bool>(json['isMuted']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      showsLastSeen: serializer.fromJson<bool>(json['showsLastSeen']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'id': serializer.toJson<String>(id),
      'peerId': serializer.toJson<String>(peerId),
      'peerUsername': serializer.toJson<String>(peerUsername),
      'peerDisplayName': serializer.toJson<String>(peerDisplayName),
      'peerAvatarUrl': serializer.toJson<String?>(peerAvatarUrl),
      'peerAvatarStoragePath': serializer.toJson<String?>(
        peerAvatarStoragePath,
      ),
      'lastMessageId': serializer.toJson<String?>(lastMessageId),
      'lastMessage': serializer.toJson<String>(lastMessage),
      'lastMessageType': serializer.toJson<String>(lastMessageType),
      'lastMessageTime': serializer.toJson<DateTime>(lastMessageTime),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'isLastMessageFromMe': serializer.toJson<bool>(isLastMessageFromMe),
      'isMuted': serializer.toJson<bool>(isMuted),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'showsLastSeen': serializer.toJson<bool>(showsLastSeen),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedChat copyWith({
    String? ownerUserId,
    String? id,
    String? peerId,
    String? peerUsername,
    String? peerDisplayName,
    Value<String?> peerAvatarUrl = const Value.absent(),
    Value<String?> peerAvatarStoragePath = const Value.absent(),
    Value<String?> lastMessageId = const Value.absent(),
    String? lastMessage,
    String? lastMessageType,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isLastMessageFromMe,
    bool? isMuted,
    Value<DateTime?> lastSeenAt = const Value.absent(),
    bool? showsLastSeen,
    DateTime? cachedAt,
  }) => CachedChat(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    id: id ?? this.id,
    peerId: peerId ?? this.peerId,
    peerUsername: peerUsername ?? this.peerUsername,
    peerDisplayName: peerDisplayName ?? this.peerDisplayName,
    peerAvatarUrl: peerAvatarUrl.present
        ? peerAvatarUrl.value
        : this.peerAvatarUrl,
    peerAvatarStoragePath: peerAvatarStoragePath.present
        ? peerAvatarStoragePath.value
        : this.peerAvatarStoragePath,
    lastMessageId: lastMessageId.present
        ? lastMessageId.value
        : this.lastMessageId,
    lastMessage: lastMessage ?? this.lastMessage,
    lastMessageType: lastMessageType ?? this.lastMessageType,
    lastMessageTime: lastMessageTime ?? this.lastMessageTime,
    unreadCount: unreadCount ?? this.unreadCount,
    isLastMessageFromMe: isLastMessageFromMe ?? this.isLastMessageFromMe,
    isMuted: isMuted ?? this.isMuted,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    showsLastSeen: showsLastSeen ?? this.showsLastSeen,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedChat copyWithCompanion(CachedChatsCompanion data) {
    return CachedChat(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      id: data.id.present ? data.id.value : this.id,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      peerUsername: data.peerUsername.present
          ? data.peerUsername.value
          : this.peerUsername,
      peerDisplayName: data.peerDisplayName.present
          ? data.peerDisplayName.value
          : this.peerDisplayName,
      peerAvatarUrl: data.peerAvatarUrl.present
          ? data.peerAvatarUrl.value
          : this.peerAvatarUrl,
      peerAvatarStoragePath: data.peerAvatarStoragePath.present
          ? data.peerAvatarStoragePath.value
          : this.peerAvatarStoragePath,
      lastMessageId: data.lastMessageId.present
          ? data.lastMessageId.value
          : this.lastMessageId,
      lastMessage: data.lastMessage.present
          ? data.lastMessage.value
          : this.lastMessage,
      lastMessageType: data.lastMessageType.present
          ? data.lastMessageType.value
          : this.lastMessageType,
      lastMessageTime: data.lastMessageTime.present
          ? data.lastMessageTime.value
          : this.lastMessageTime,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      isLastMessageFromMe: data.isLastMessageFromMe.present
          ? data.isLastMessageFromMe.value
          : this.isLastMessageFromMe,
      isMuted: data.isMuted.present ? data.isMuted.value : this.isMuted,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      showsLastSeen: data.showsLastSeen.present
          ? data.showsLastSeen.value
          : this.showsLastSeen,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedChat(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('peerUsername: $peerUsername, ')
          ..write('peerDisplayName: $peerDisplayName, ')
          ..write('peerAvatarUrl: $peerAvatarUrl, ')
          ..write('peerAvatarStoragePath: $peerAvatarStoragePath, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageType: $lastMessageType, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isLastMessageFromMe: $isLastMessageFromMe, ')
          ..write('isMuted: $isMuted, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('showsLastSeen: $showsLastSeen, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    id,
    peerId,
    peerUsername,
    peerDisplayName,
    peerAvatarUrl,
    peerAvatarStoragePath,
    lastMessageId,
    lastMessage,
    lastMessageType,
    lastMessageTime,
    unreadCount,
    isLastMessageFromMe,
    isMuted,
    lastSeenAt,
    showsLastSeen,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedChat &&
          other.ownerUserId == this.ownerUserId &&
          other.id == this.id &&
          other.peerId == this.peerId &&
          other.peerUsername == this.peerUsername &&
          other.peerDisplayName == this.peerDisplayName &&
          other.peerAvatarUrl == this.peerAvatarUrl &&
          other.peerAvatarStoragePath == this.peerAvatarStoragePath &&
          other.lastMessageId == this.lastMessageId &&
          other.lastMessage == this.lastMessage &&
          other.lastMessageType == this.lastMessageType &&
          other.lastMessageTime == this.lastMessageTime &&
          other.unreadCount == this.unreadCount &&
          other.isLastMessageFromMe == this.isLastMessageFromMe &&
          other.isMuted == this.isMuted &&
          other.lastSeenAt == this.lastSeenAt &&
          other.showsLastSeen == this.showsLastSeen &&
          other.cachedAt == this.cachedAt);
}

class CachedChatsCompanion extends UpdateCompanion<CachedChat> {
  final Value<String> ownerUserId;
  final Value<String> id;
  final Value<String> peerId;
  final Value<String> peerUsername;
  final Value<String> peerDisplayName;
  final Value<String?> peerAvatarUrl;
  final Value<String?> peerAvatarStoragePath;
  final Value<String?> lastMessageId;
  final Value<String> lastMessage;
  final Value<String> lastMessageType;
  final Value<DateTime> lastMessageTime;
  final Value<int> unreadCount;
  final Value<bool> isLastMessageFromMe;
  final Value<bool> isMuted;
  final Value<DateTime?> lastSeenAt;
  final Value<bool> showsLastSeen;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedChatsCompanion({
    this.ownerUserId = const Value.absent(),
    this.id = const Value.absent(),
    this.peerId = const Value.absent(),
    this.peerUsername = const Value.absent(),
    this.peerDisplayName = const Value.absent(),
    this.peerAvatarUrl = const Value.absent(),
    this.peerAvatarStoragePath = const Value.absent(),
    this.lastMessageId = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageType = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isLastMessageFromMe = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.showsLastSeen = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedChatsCompanion.insert({
    required String ownerUserId,
    required String id,
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    this.peerAvatarUrl = const Value.absent(),
    this.peerAvatarStoragePath = const Value.absent(),
    this.lastMessageId = const Value.absent(),
    required String lastMessage,
    required String lastMessageType,
    required DateTime lastMessageTime,
    required int unreadCount,
    required bool isLastMessageFromMe,
    required bool isMuted,
    this.lastSeenAt = const Value.absent(),
    this.showsLastSeen = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       id = Value(id),
       peerId = Value(peerId),
       peerUsername = Value(peerUsername),
       peerDisplayName = Value(peerDisplayName),
       lastMessage = Value(lastMessage),
       lastMessageType = Value(lastMessageType),
       lastMessageTime = Value(lastMessageTime),
       unreadCount = Value(unreadCount),
       isLastMessageFromMe = Value(isLastMessageFromMe),
       isMuted = Value(isMuted),
       cachedAt = Value(cachedAt);
  static Insertable<CachedChat> custom({
    Expression<String>? ownerUserId,
    Expression<String>? id,
    Expression<String>? peerId,
    Expression<String>? peerUsername,
    Expression<String>? peerDisplayName,
    Expression<String>? peerAvatarUrl,
    Expression<String>? peerAvatarStoragePath,
    Expression<String>? lastMessageId,
    Expression<String>? lastMessage,
    Expression<String>? lastMessageType,
    Expression<DateTime>? lastMessageTime,
    Expression<int>? unreadCount,
    Expression<bool>? isLastMessageFromMe,
    Expression<bool>? isMuted,
    Expression<DateTime>? lastSeenAt,
    Expression<bool>? showsLastSeen,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (id != null) 'id': id,
      if (peerId != null) 'peer_id': peerId,
      if (peerUsername != null) 'peer_username': peerUsername,
      if (peerDisplayName != null) 'peer_display_name': peerDisplayName,
      if (peerAvatarUrl != null) 'peer_avatar_url': peerAvatarUrl,
      if (peerAvatarStoragePath != null)
        'peer_avatar_storage_path': peerAvatarStoragePath,
      if (lastMessageId != null) 'last_message_id': lastMessageId,
      if (lastMessage != null) 'last_message': lastMessage,
      if (lastMessageType != null) 'last_message_type': lastMessageType,
      if (lastMessageTime != null) 'last_message_time': lastMessageTime,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (isLastMessageFromMe != null)
        'is_last_message_from_me': isLastMessageFromMe,
      if (isMuted != null) 'is_muted': isMuted,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (showsLastSeen != null) 'shows_last_seen': showsLastSeen,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedChatsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? id,
    Value<String>? peerId,
    Value<String>? peerUsername,
    Value<String>? peerDisplayName,
    Value<String?>? peerAvatarUrl,
    Value<String?>? peerAvatarStoragePath,
    Value<String?>? lastMessageId,
    Value<String>? lastMessage,
    Value<String>? lastMessageType,
    Value<DateTime>? lastMessageTime,
    Value<int>? unreadCount,
    Value<bool>? isLastMessageFromMe,
    Value<bool>? isMuted,
    Value<DateTime?>? lastSeenAt,
    Value<bool>? showsLastSeen,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedChatsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      peerUsername: peerUsername ?? this.peerUsername,
      peerDisplayName: peerDisplayName ?? this.peerDisplayName,
      peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
      peerAvatarStoragePath:
          peerAvatarStoragePath ?? this.peerAvatarStoragePath,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isLastMessageFromMe: isLastMessageFromMe ?? this.isLastMessageFromMe,
      isMuted: isMuted ?? this.isMuted,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      showsLastSeen: showsLastSeen ?? this.showsLastSeen,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (peerUsername.present) {
      map['peer_username'] = Variable<String>(peerUsername.value);
    }
    if (peerDisplayName.present) {
      map['peer_display_name'] = Variable<String>(peerDisplayName.value);
    }
    if (peerAvatarUrl.present) {
      map['peer_avatar_url'] = Variable<String>(peerAvatarUrl.value);
    }
    if (peerAvatarStoragePath.present) {
      map['peer_avatar_storage_path'] = Variable<String>(
        peerAvatarStoragePath.value,
      );
    }
    if (lastMessageId.present) {
      map['last_message_id'] = Variable<String>(lastMessageId.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (lastMessageType.present) {
      map['last_message_type'] = Variable<String>(lastMessageType.value);
    }
    if (lastMessageTime.present) {
      map['last_message_time'] = Variable<DateTime>(lastMessageTime.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (isLastMessageFromMe.present) {
      map['is_last_message_from_me'] = Variable<bool>(
        isLastMessageFromMe.value,
      );
    }
    if (isMuted.present) {
      map['is_muted'] = Variable<bool>(isMuted.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (showsLastSeen.present) {
      map['shows_last_seen'] = Variable<bool>(showsLastSeen.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedChatsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('peerUsername: $peerUsername, ')
          ..write('peerDisplayName: $peerDisplayName, ')
          ..write('peerAvatarUrl: $peerAvatarUrl, ')
          ..write('peerAvatarStoragePath: $peerAvatarStoragePath, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageType: $lastMessageType, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isLastMessageFromMe: $isLastMessageFromMe, ')
          ..write('isMuted: $isMuted, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('showsLastSeen: $showsLastSeen, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMessagesTable extends CachedMessages
    with TableInfo<$CachedMessagesTable, CachedMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageTextMeta = const VerificationMeta(
    'messageText',
  );
  @override
  late final GeneratedColumn<String> messageText = GeneratedColumn<String>(
    'message_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaUrlsJsonMeta = const VerificationMeta(
    'mediaUrlsJson',
  );
  @override
  late final GeneratedColumn<String> mediaUrlsJson = GeneratedColumn<String>(
    'media_urls_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaStoragePathsJsonMeta =
      const VerificationMeta('mediaStoragePathsJson');
  @override
  late final GeneratedColumn<String> mediaStoragePathsJson =
      GeneratedColumn<String>(
        'media_storage_paths_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioUrlMeta = const VerificationMeta(
    'audioUrl',
  );
  @override
  late final GeneratedColumn<String> audioUrl = GeneratedColumn<String>(
    'audio_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioStoragePathMeta = const VerificationMeta(
    'audioStoragePath',
  );
  @override
  late final GeneratedColumn<String> audioStoragePath = GeneratedColumn<String>(
    'audio_storage_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioDurationMsMeta = const VerificationMeta(
    'audioDurationMs',
  );
  @override
  late final GeneratedColumn<int> audioDurationMs = GeneratedColumn<int>(
    'audio_duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioWaveformJsonMeta = const VerificationMeta(
    'audioWaveformJson',
  );
  @override
  late final GeneratedColumn<String> audioWaveformJson =
      GeneratedColumn<String>(
        'audio_waveform_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _replyMessageIdMeta = const VerificationMeta(
    'replyMessageId',
  );
  @override
  late final GeneratedColumn<String> replyMessageId = GeneratedColumn<String>(
    'reply_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replySenderIdMeta = const VerificationMeta(
    'replySenderId',
  );
  @override
  late final GeneratedColumn<String> replySenderId = GeneratedColumn<String>(
    'reply_sender_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyTypeMeta = const VerificationMeta(
    'replyType',
  );
  @override
  late final GeneratedColumn<String> replyType = GeneratedColumn<String>(
    'reply_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyTextMeta = const VerificationMeta(
    'replyText',
  );
  @override
  late final GeneratedColumn<String> replyText = GeneratedColumn<String>(
    'reply_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPendingMeta = const VerificationMeta(
    'isPending',
  );
  @override
  late final GeneratedColumn<bool> isPending = GeneratedColumn<bool>(
    'is_pending',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pending" IN (0, 1))',
    ),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    id,
    chatId,
    senderId,
    messageText,
    timestamp,
    status,
    type,
    mediaUrlsJson,
    mediaStoragePathsJson,
    latitude,
    longitude,
    audioUrl,
    audioStoragePath,
    audioDurationMs,
    audioWaveformJson,
    replyMessageId,
    replySenderId,
    replyType,
    replyText,
    readAt,
    isPending,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('message_text')) {
      context.handle(
        _messageTextMeta,
        messageText.isAcceptableOrUnknown(
          data['message_text']!,
          _messageTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageTextMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('media_urls_json')) {
      context.handle(
        _mediaUrlsJsonMeta,
        mediaUrlsJson.isAcceptableOrUnknown(
          data['media_urls_json']!,
          _mediaUrlsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mediaUrlsJsonMeta);
    }
    if (data.containsKey('media_storage_paths_json')) {
      context.handle(
        _mediaStoragePathsJsonMeta,
        mediaStoragePathsJson.isAcceptableOrUnknown(
          data['media_storage_paths_json']!,
          _mediaStoragePathsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mediaStoragePathsJsonMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('audio_url')) {
      context.handle(
        _audioUrlMeta,
        audioUrl.isAcceptableOrUnknown(data['audio_url']!, _audioUrlMeta),
      );
    }
    if (data.containsKey('audio_storage_path')) {
      context.handle(
        _audioStoragePathMeta,
        audioStoragePath.isAcceptableOrUnknown(
          data['audio_storage_path']!,
          _audioStoragePathMeta,
        ),
      );
    }
    if (data.containsKey('audio_duration_ms')) {
      context.handle(
        _audioDurationMsMeta,
        audioDurationMs.isAcceptableOrUnknown(
          data['audio_duration_ms']!,
          _audioDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('audio_waveform_json')) {
      context.handle(
        _audioWaveformJsonMeta,
        audioWaveformJson.isAcceptableOrUnknown(
          data['audio_waveform_json']!,
          _audioWaveformJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_audioWaveformJsonMeta);
    }
    if (data.containsKey('reply_message_id')) {
      context.handle(
        _replyMessageIdMeta,
        replyMessageId.isAcceptableOrUnknown(
          data['reply_message_id']!,
          _replyMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('reply_sender_id')) {
      context.handle(
        _replySenderIdMeta,
        replySenderId.isAcceptableOrUnknown(
          data['reply_sender_id']!,
          _replySenderIdMeta,
        ),
      );
    }
    if (data.containsKey('reply_type')) {
      context.handle(
        _replyTypeMeta,
        replyType.isAcceptableOrUnknown(data['reply_type']!, _replyTypeMeta),
      );
    }
    if (data.containsKey('reply_text')) {
      context.handle(
        _replyTextMeta,
        replyText.isAcceptableOrUnknown(data['reply_text']!, _replyTextMeta),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    if (data.containsKey('is_pending')) {
      context.handle(
        _isPendingMeta,
        isPending.isAcceptableOrUnknown(data['is_pending']!, _isPendingMeta),
      );
    } else if (isInserting) {
      context.missing(_isPendingMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, id};
  @override
  CachedMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMessage(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      messageText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_text'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      mediaUrlsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_urls_json'],
      )!,
      mediaStoragePathsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_storage_paths_json'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      audioUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_url'],
      ),
      audioStoragePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_storage_path'],
      ),
      audioDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}audio_duration_ms'],
      ),
      audioWaveformJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_waveform_json'],
      )!,
      replyMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_message_id'],
      ),
      replySenderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_sender_id'],
      ),
      replyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_type'],
      ),
      replyText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_text'],
      ),
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
      isPending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pending'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedMessagesTable createAlias(String alias) {
    return $CachedMessagesTable(attachedDatabase, alias);
  }
}

class CachedMessage extends DataClass implements Insertable<CachedMessage> {
  final String ownerUserId;
  final String id;
  final String chatId;
  final String senderId;
  final String messageText;
  final DateTime timestamp;
  final String status;
  final String type;
  final String mediaUrlsJson;
  final String mediaStoragePathsJson;
  final double? latitude;
  final double? longitude;
  final String? audioUrl;
  final String? audioStoragePath;
  final int? audioDurationMs;
  final String audioWaveformJson;
  final String? replyMessageId;
  final String? replySenderId;
  final String? replyType;
  final String? replyText;
  final DateTime? readAt;
  final bool isPending;
  final DateTime cachedAt;
  const CachedMessage({
    required this.ownerUserId,
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.messageText,
    required this.timestamp,
    required this.status,
    required this.type,
    required this.mediaUrlsJson,
    required this.mediaStoragePathsJson,
    this.latitude,
    this.longitude,
    this.audioUrl,
    this.audioStoragePath,
    this.audioDurationMs,
    required this.audioWaveformJson,
    this.replyMessageId,
    this.replySenderId,
    this.replyType,
    this.replyText,
    this.readAt,
    required this.isPending,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['id'] = Variable<String>(id);
    map['chat_id'] = Variable<String>(chatId);
    map['sender_id'] = Variable<String>(senderId);
    map['message_text'] = Variable<String>(messageText);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['status'] = Variable<String>(status);
    map['type'] = Variable<String>(type);
    map['media_urls_json'] = Variable<String>(mediaUrlsJson);
    map['media_storage_paths_json'] = Variable<String>(mediaStoragePathsJson);
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || audioUrl != null) {
      map['audio_url'] = Variable<String>(audioUrl);
    }
    if (!nullToAbsent || audioStoragePath != null) {
      map['audio_storage_path'] = Variable<String>(audioStoragePath);
    }
    if (!nullToAbsent || audioDurationMs != null) {
      map['audio_duration_ms'] = Variable<int>(audioDurationMs);
    }
    map['audio_waveform_json'] = Variable<String>(audioWaveformJson);
    if (!nullToAbsent || replyMessageId != null) {
      map['reply_message_id'] = Variable<String>(replyMessageId);
    }
    if (!nullToAbsent || replySenderId != null) {
      map['reply_sender_id'] = Variable<String>(replySenderId);
    }
    if (!nullToAbsent || replyType != null) {
      map['reply_type'] = Variable<String>(replyType);
    }
    if (!nullToAbsent || replyText != null) {
      map['reply_text'] = Variable<String>(replyText);
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    map['is_pending'] = Variable<bool>(isPending);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedMessagesCompanion toCompanion(bool nullToAbsent) {
    return CachedMessagesCompanion(
      ownerUserId: Value(ownerUserId),
      id: Value(id),
      chatId: Value(chatId),
      senderId: Value(senderId),
      messageText: Value(messageText),
      timestamp: Value(timestamp),
      status: Value(status),
      type: Value(type),
      mediaUrlsJson: Value(mediaUrlsJson),
      mediaStoragePathsJson: Value(mediaStoragePathsJson),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      audioUrl: audioUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(audioUrl),
      audioStoragePath: audioStoragePath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioStoragePath),
      audioDurationMs: audioDurationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(audioDurationMs),
      audioWaveformJson: Value(audioWaveformJson),
      replyMessageId: replyMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyMessageId),
      replySenderId: replySenderId == null && nullToAbsent
          ? const Value.absent()
          : Value(replySenderId),
      replyType: replyType == null && nullToAbsent
          ? const Value.absent()
          : Value(replyType),
      replyText: replyText == null && nullToAbsent
          ? const Value.absent()
          : Value(replyText),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
      isPending: Value(isPending),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMessage(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      id: serializer.fromJson<String>(json['id']),
      chatId: serializer.fromJson<String>(json['chatId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      messageText: serializer.fromJson<String>(json['messageText']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      status: serializer.fromJson<String>(json['status']),
      type: serializer.fromJson<String>(json['type']),
      mediaUrlsJson: serializer.fromJson<String>(json['mediaUrlsJson']),
      mediaStoragePathsJson: serializer.fromJson<String>(
        json['mediaStoragePathsJson'],
      ),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      audioUrl: serializer.fromJson<String?>(json['audioUrl']),
      audioStoragePath: serializer.fromJson<String?>(json['audioStoragePath']),
      audioDurationMs: serializer.fromJson<int?>(json['audioDurationMs']),
      audioWaveformJson: serializer.fromJson<String>(json['audioWaveformJson']),
      replyMessageId: serializer.fromJson<String?>(json['replyMessageId']),
      replySenderId: serializer.fromJson<String?>(json['replySenderId']),
      replyType: serializer.fromJson<String?>(json['replyType']),
      replyText: serializer.fromJson<String?>(json['replyText']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
      isPending: serializer.fromJson<bool>(json['isPending']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'id': serializer.toJson<String>(id),
      'chatId': serializer.toJson<String>(chatId),
      'senderId': serializer.toJson<String>(senderId),
      'messageText': serializer.toJson<String>(messageText),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'status': serializer.toJson<String>(status),
      'type': serializer.toJson<String>(type),
      'mediaUrlsJson': serializer.toJson<String>(mediaUrlsJson),
      'mediaStoragePathsJson': serializer.toJson<String>(mediaStoragePathsJson),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'audioUrl': serializer.toJson<String?>(audioUrl),
      'audioStoragePath': serializer.toJson<String?>(audioStoragePath),
      'audioDurationMs': serializer.toJson<int?>(audioDurationMs),
      'audioWaveformJson': serializer.toJson<String>(audioWaveformJson),
      'replyMessageId': serializer.toJson<String?>(replyMessageId),
      'replySenderId': serializer.toJson<String?>(replySenderId),
      'replyType': serializer.toJson<String?>(replyType),
      'replyText': serializer.toJson<String?>(replyText),
      'readAt': serializer.toJson<DateTime?>(readAt),
      'isPending': serializer.toJson<bool>(isPending),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedMessage copyWith({
    String? ownerUserId,
    String? id,
    String? chatId,
    String? senderId,
    String? messageText,
    DateTime? timestamp,
    String? status,
    String? type,
    String? mediaUrlsJson,
    String? mediaStoragePathsJson,
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<String?> audioUrl = const Value.absent(),
    Value<String?> audioStoragePath = const Value.absent(),
    Value<int?> audioDurationMs = const Value.absent(),
    String? audioWaveformJson,
    Value<String?> replyMessageId = const Value.absent(),
    Value<String?> replySenderId = const Value.absent(),
    Value<String?> replyType = const Value.absent(),
    Value<String?> replyText = const Value.absent(),
    Value<DateTime?> readAt = const Value.absent(),
    bool? isPending,
    DateTime? cachedAt,
  }) => CachedMessage(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    id: id ?? this.id,
    chatId: chatId ?? this.chatId,
    senderId: senderId ?? this.senderId,
    messageText: messageText ?? this.messageText,
    timestamp: timestamp ?? this.timestamp,
    status: status ?? this.status,
    type: type ?? this.type,
    mediaUrlsJson: mediaUrlsJson ?? this.mediaUrlsJson,
    mediaStoragePathsJson: mediaStoragePathsJson ?? this.mediaStoragePathsJson,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    audioUrl: audioUrl.present ? audioUrl.value : this.audioUrl,
    audioStoragePath: audioStoragePath.present
        ? audioStoragePath.value
        : this.audioStoragePath,
    audioDurationMs: audioDurationMs.present
        ? audioDurationMs.value
        : this.audioDurationMs,
    audioWaveformJson: audioWaveformJson ?? this.audioWaveformJson,
    replyMessageId: replyMessageId.present
        ? replyMessageId.value
        : this.replyMessageId,
    replySenderId: replySenderId.present
        ? replySenderId.value
        : this.replySenderId,
    replyType: replyType.present ? replyType.value : this.replyType,
    replyText: replyText.present ? replyText.value : this.replyText,
    readAt: readAt.present ? readAt.value : this.readAt,
    isPending: isPending ?? this.isPending,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedMessage copyWithCompanion(CachedMessagesCompanion data) {
    return CachedMessage(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      id: data.id.present ? data.id.value : this.id,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      messageText: data.messageText.present
          ? data.messageText.value
          : this.messageText,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      status: data.status.present ? data.status.value : this.status,
      type: data.type.present ? data.type.value : this.type,
      mediaUrlsJson: data.mediaUrlsJson.present
          ? data.mediaUrlsJson.value
          : this.mediaUrlsJson,
      mediaStoragePathsJson: data.mediaStoragePathsJson.present
          ? data.mediaStoragePathsJson.value
          : this.mediaStoragePathsJson,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      audioUrl: data.audioUrl.present ? data.audioUrl.value : this.audioUrl,
      audioStoragePath: data.audioStoragePath.present
          ? data.audioStoragePath.value
          : this.audioStoragePath,
      audioDurationMs: data.audioDurationMs.present
          ? data.audioDurationMs.value
          : this.audioDurationMs,
      audioWaveformJson: data.audioWaveformJson.present
          ? data.audioWaveformJson.value
          : this.audioWaveformJson,
      replyMessageId: data.replyMessageId.present
          ? data.replyMessageId.value
          : this.replyMessageId,
      replySenderId: data.replySenderId.present
          ? data.replySenderId.value
          : this.replySenderId,
      replyType: data.replyType.present ? data.replyType.value : this.replyType,
      replyText: data.replyText.present ? data.replyText.value : this.replyText,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      isPending: data.isPending.present ? data.isPending.value : this.isPending,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessage(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('messageText: $messageText, ')
          ..write('timestamp: $timestamp, ')
          ..write('status: $status, ')
          ..write('type: $type, ')
          ..write('mediaUrlsJson: $mediaUrlsJson, ')
          ..write('mediaStoragePathsJson: $mediaStoragePathsJson, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('audioUrl: $audioUrl, ')
          ..write('audioStoragePath: $audioStoragePath, ')
          ..write('audioDurationMs: $audioDurationMs, ')
          ..write('audioWaveformJson: $audioWaveformJson, ')
          ..write('replyMessageId: $replyMessageId, ')
          ..write('replySenderId: $replySenderId, ')
          ..write('replyType: $replyType, ')
          ..write('replyText: $replyText, ')
          ..write('readAt: $readAt, ')
          ..write('isPending: $isPending, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    ownerUserId,
    id,
    chatId,
    senderId,
    messageText,
    timestamp,
    status,
    type,
    mediaUrlsJson,
    mediaStoragePathsJson,
    latitude,
    longitude,
    audioUrl,
    audioStoragePath,
    audioDurationMs,
    audioWaveformJson,
    replyMessageId,
    replySenderId,
    replyType,
    replyText,
    readAt,
    isPending,
    cachedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMessage &&
          other.ownerUserId == this.ownerUserId &&
          other.id == this.id &&
          other.chatId == this.chatId &&
          other.senderId == this.senderId &&
          other.messageText == this.messageText &&
          other.timestamp == this.timestamp &&
          other.status == this.status &&
          other.type == this.type &&
          other.mediaUrlsJson == this.mediaUrlsJson &&
          other.mediaStoragePathsJson == this.mediaStoragePathsJson &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.audioUrl == this.audioUrl &&
          other.audioStoragePath == this.audioStoragePath &&
          other.audioDurationMs == this.audioDurationMs &&
          other.audioWaveformJson == this.audioWaveformJson &&
          other.replyMessageId == this.replyMessageId &&
          other.replySenderId == this.replySenderId &&
          other.replyType == this.replyType &&
          other.replyText == this.replyText &&
          other.readAt == this.readAt &&
          other.isPending == this.isPending &&
          other.cachedAt == this.cachedAt);
}

class CachedMessagesCompanion extends UpdateCompanion<CachedMessage> {
  final Value<String> ownerUserId;
  final Value<String> id;
  final Value<String> chatId;
  final Value<String> senderId;
  final Value<String> messageText;
  final Value<DateTime> timestamp;
  final Value<String> status;
  final Value<String> type;
  final Value<String> mediaUrlsJson;
  final Value<String> mediaStoragePathsJson;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<String?> audioUrl;
  final Value<String?> audioStoragePath;
  final Value<int?> audioDurationMs;
  final Value<String> audioWaveformJson;
  final Value<String?> replyMessageId;
  final Value<String?> replySenderId;
  final Value<String?> replyType;
  final Value<String?> replyText;
  final Value<DateTime?> readAt;
  final Value<bool> isPending;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedMessagesCompanion({
    this.ownerUserId = const Value.absent(),
    this.id = const Value.absent(),
    this.chatId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.messageText = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.status = const Value.absent(),
    this.type = const Value.absent(),
    this.mediaUrlsJson = const Value.absent(),
    this.mediaStoragePathsJson = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.audioUrl = const Value.absent(),
    this.audioStoragePath = const Value.absent(),
    this.audioDurationMs = const Value.absent(),
    this.audioWaveformJson = const Value.absent(),
    this.replyMessageId = const Value.absent(),
    this.replySenderId = const Value.absent(),
    this.replyType = const Value.absent(),
    this.replyText = const Value.absent(),
    this.readAt = const Value.absent(),
    this.isPending = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMessagesCompanion.insert({
    required String ownerUserId,
    required String id,
    required String chatId,
    required String senderId,
    required String messageText,
    required DateTime timestamp,
    required String status,
    required String type,
    required String mediaUrlsJson,
    required String mediaStoragePathsJson,
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.audioUrl = const Value.absent(),
    this.audioStoragePath = const Value.absent(),
    this.audioDurationMs = const Value.absent(),
    required String audioWaveformJson,
    this.replyMessageId = const Value.absent(),
    this.replySenderId = const Value.absent(),
    this.replyType = const Value.absent(),
    this.replyText = const Value.absent(),
    this.readAt = const Value.absent(),
    required bool isPending,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       id = Value(id),
       chatId = Value(chatId),
       senderId = Value(senderId),
       messageText = Value(messageText),
       timestamp = Value(timestamp),
       status = Value(status),
       type = Value(type),
       mediaUrlsJson = Value(mediaUrlsJson),
       mediaStoragePathsJson = Value(mediaStoragePathsJson),
       audioWaveformJson = Value(audioWaveformJson),
       isPending = Value(isPending),
       cachedAt = Value(cachedAt);
  static Insertable<CachedMessage> custom({
    Expression<String>? ownerUserId,
    Expression<String>? id,
    Expression<String>? chatId,
    Expression<String>? senderId,
    Expression<String>? messageText,
    Expression<DateTime>? timestamp,
    Expression<String>? status,
    Expression<String>? type,
    Expression<String>? mediaUrlsJson,
    Expression<String>? mediaStoragePathsJson,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? audioUrl,
    Expression<String>? audioStoragePath,
    Expression<int>? audioDurationMs,
    Expression<String>? audioWaveformJson,
    Expression<String>? replyMessageId,
    Expression<String>? replySenderId,
    Expression<String>? replyType,
    Expression<String>? replyText,
    Expression<DateTime>? readAt,
    Expression<bool>? isPending,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (id != null) 'id': id,
      if (chatId != null) 'chat_id': chatId,
      if (senderId != null) 'sender_id': senderId,
      if (messageText != null) 'message_text': messageText,
      if (timestamp != null) 'timestamp': timestamp,
      if (status != null) 'status': status,
      if (type != null) 'type': type,
      if (mediaUrlsJson != null) 'media_urls_json': mediaUrlsJson,
      if (mediaStoragePathsJson != null)
        'media_storage_paths_json': mediaStoragePathsJson,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (audioUrl != null) 'audio_url': audioUrl,
      if (audioStoragePath != null) 'audio_storage_path': audioStoragePath,
      if (audioDurationMs != null) 'audio_duration_ms': audioDurationMs,
      if (audioWaveformJson != null) 'audio_waveform_json': audioWaveformJson,
      if (replyMessageId != null) 'reply_message_id': replyMessageId,
      if (replySenderId != null) 'reply_sender_id': replySenderId,
      if (replyType != null) 'reply_type': replyType,
      if (replyText != null) 'reply_text': replyText,
      if (readAt != null) 'read_at': readAt,
      if (isPending != null) 'is_pending': isPending,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMessagesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? id,
    Value<String>? chatId,
    Value<String>? senderId,
    Value<String>? messageText,
    Value<DateTime>? timestamp,
    Value<String>? status,
    Value<String>? type,
    Value<String>? mediaUrlsJson,
    Value<String>? mediaStoragePathsJson,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<String?>? audioUrl,
    Value<String?>? audioStoragePath,
    Value<int?>? audioDurationMs,
    Value<String>? audioWaveformJson,
    Value<String?>? replyMessageId,
    Value<String?>? replySenderId,
    Value<String?>? replyType,
    Value<String?>? replyText,
    Value<DateTime?>? readAt,
    Value<bool>? isPending,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedMessagesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      messageText: messageText ?? this.messageText,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      type: type ?? this.type,
      mediaUrlsJson: mediaUrlsJson ?? this.mediaUrlsJson,
      mediaStoragePathsJson:
          mediaStoragePathsJson ?? this.mediaStoragePathsJson,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      audioUrl: audioUrl ?? this.audioUrl,
      audioStoragePath: audioStoragePath ?? this.audioStoragePath,
      audioDurationMs: audioDurationMs ?? this.audioDurationMs,
      audioWaveformJson: audioWaveformJson ?? this.audioWaveformJson,
      replyMessageId: replyMessageId ?? this.replyMessageId,
      replySenderId: replySenderId ?? this.replySenderId,
      replyType: replyType ?? this.replyType,
      replyText: replyText ?? this.replyText,
      readAt: readAt ?? this.readAt,
      isPending: isPending ?? this.isPending,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (messageText.present) {
      map['message_text'] = Variable<String>(messageText.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (mediaUrlsJson.present) {
      map['media_urls_json'] = Variable<String>(mediaUrlsJson.value);
    }
    if (mediaStoragePathsJson.present) {
      map['media_storage_paths_json'] = Variable<String>(
        mediaStoragePathsJson.value,
      );
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (audioUrl.present) {
      map['audio_url'] = Variable<String>(audioUrl.value);
    }
    if (audioStoragePath.present) {
      map['audio_storage_path'] = Variable<String>(audioStoragePath.value);
    }
    if (audioDurationMs.present) {
      map['audio_duration_ms'] = Variable<int>(audioDurationMs.value);
    }
    if (audioWaveformJson.present) {
      map['audio_waveform_json'] = Variable<String>(audioWaveformJson.value);
    }
    if (replyMessageId.present) {
      map['reply_message_id'] = Variable<String>(replyMessageId.value);
    }
    if (replySenderId.present) {
      map['reply_sender_id'] = Variable<String>(replySenderId.value);
    }
    if (replyType.present) {
      map['reply_type'] = Variable<String>(replyType.value);
    }
    if (replyText.present) {
      map['reply_text'] = Variable<String>(replyText.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (isPending.present) {
      map['is_pending'] = Variable<bool>(isPending.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessagesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('messageText: $messageText, ')
          ..write('timestamp: $timestamp, ')
          ..write('status: $status, ')
          ..write('type: $type, ')
          ..write('mediaUrlsJson: $mediaUrlsJson, ')
          ..write('mediaStoragePathsJson: $mediaStoragePathsJson, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('audioUrl: $audioUrl, ')
          ..write('audioStoragePath: $audioStoragePath, ')
          ..write('audioDurationMs: $audioDurationMs, ')
          ..write('audioWaveformJson: $audioWaveformJson, ')
          ..write('replyMessageId: $replyMessageId, ')
          ..write('replySenderId: $replySenderId, ')
          ..write('replyType: $replyType, ')
          ..write('replyText: $replyText, ')
          ..write('readAt: $readAt, ')
          ..write('isPending: $isPending, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingChatOperationsTable extends PendingChatOperations
    with TableInfo<$PendingChatOperationsTable, PendingChatOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingChatOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    id,
    chatId,
    type,
    payloadJson,
    attempts,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_chat_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingChatOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, id};
  @override
  PendingChatOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingChatOperation(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PendingChatOperationsTable createAlias(String alias) {
    return $PendingChatOperationsTable(attachedDatabase, alias);
  }
}

class PendingChatOperation extends DataClass
    implements Insertable<PendingChatOperation> {
  final String ownerUserId;
  final String id;
  final String chatId;
  final String type;
  final String payloadJson;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  const PendingChatOperation({
    required this.ownerUserId,
    required this.id,
    required this.chatId,
    required this.type,
    required this.payloadJson,
    required this.attempts,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['id'] = Variable<String>(id);
    map['chat_id'] = Variable<String>(chatId);
    map['type'] = Variable<String>(type);
    map['payload_json'] = Variable<String>(payloadJson);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PendingChatOperationsCompanion toCompanion(bool nullToAbsent) {
    return PendingChatOperationsCompanion(
      ownerUserId: Value(ownerUserId),
      id: Value(id),
      chatId: Value(chatId),
      type: Value(type),
      payloadJson: Value(payloadJson),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory PendingChatOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingChatOperation(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      id: serializer.fromJson<String>(json['id']),
      chatId: serializer.fromJson<String>(json['chatId']),
      type: serializer.fromJson<String>(json['type']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'id': serializer.toJson<String>(id),
      'chatId': serializer.toJson<String>(chatId),
      'type': serializer.toJson<String>(type),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PendingChatOperation copyWith({
    String? ownerUserId,
    String? id,
    String? chatId,
    String? type,
    String? payloadJson,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => PendingChatOperation(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    id: id ?? this.id,
    chatId: chatId ?? this.chatId,
    type: type ?? this.type,
    payloadJson: payloadJson ?? this.payloadJson,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  PendingChatOperation copyWithCompanion(PendingChatOperationsCompanion data) {
    return PendingChatOperation(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      id: data.id.present ? data.id.value : this.id,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      type: data.type.present ? data.type.value : this.type,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingChatOperation(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    id,
    chatId,
    type,
    payloadJson,
    attempts,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingChatOperation &&
          other.ownerUserId == this.ownerUserId &&
          other.id == this.id &&
          other.chatId == this.chatId &&
          other.type == this.type &&
          other.payloadJson == this.payloadJson &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class PendingChatOperationsCompanion
    extends UpdateCompanion<PendingChatOperation> {
  final Value<String> ownerUserId;
  final Value<String> id;
  final Value<String> chatId;
  final Value<String> type;
  final Value<String> payloadJson;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PendingChatOperationsCompanion({
    this.ownerUserId = const Value.absent(),
    this.id = const Value.absent(),
    this.chatId = const Value.absent(),
    this.type = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingChatOperationsCompanion.insert({
    required String ownerUserId,
    required String id,
    required String chatId,
    required String type,
    required String payloadJson,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       id = Value(id),
       chatId = Value(chatId),
       type = Value(type),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<PendingChatOperation> custom({
    Expression<String>? ownerUserId,
    Expression<String>? id,
    Expression<String>? chatId,
    Expression<String>? type,
    Expression<String>? payloadJson,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (id != null) 'id': id,
      if (chatId != null) 'chat_id': chatId,
      if (type != null) 'type': type,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingChatOperationsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? id,
    Value<String>? chatId,
    Value<String>? type,
    Value<String>? payloadJson,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PendingChatOperationsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      type: type ?? this.type,
      payloadJson: payloadJson ?? this.payloadJson,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingChatOperationsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedFriendsTable extends CachedFriends
    with TableInfo<$CachedFriendsTable, CachedFriend> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedFriendsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarStoragePathMeta = const VerificationMeta(
    'avatarStoragePath',
  );
  @override
  late final GeneratedColumn<String> avatarStoragePath =
      GeneratedColumn<String>(
        'avatar_storage_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _friendsSinceMeta = const VerificationMeta(
    'friendsSince',
  );
  @override
  late final GeneratedColumn<DateTime> friendsSince = GeneratedColumn<DateTime>(
    'friends_since',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    userId,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    friendsSince,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_friends';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFriend> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('avatar_storage_path')) {
      context.handle(
        _avatarStoragePathMeta,
        avatarStoragePath.isAcceptableOrUnknown(
          data['avatar_storage_path']!,
          _avatarStoragePathMeta,
        ),
      );
    }
    if (data.containsKey('friends_since')) {
      context.handle(
        _friendsSinceMeta,
        friendsSince.isAcceptableOrUnknown(
          data['friends_since']!,
          _friendsSinceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_friendsSinceMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, userId};
  @override
  CachedFriend map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFriend(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      avatarStoragePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_storage_path'],
      ),
      friendsSince: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}friends_since'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedFriendsTable createAlias(String alias) {
    return $CachedFriendsTable(attachedDatabase, alias);
  }
}

class CachedFriend extends DataClass implements Insertable<CachedFriend> {
  final String ownerUserId;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final DateTime friendsSince;
  final DateTime cachedAt;
  const CachedFriend({
    required this.ownerUserId,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.avatarStoragePath,
    required this.friendsSince,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['user_id'] = Variable<String>(userId);
    map['username'] = Variable<String>(username);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || avatarStoragePath != null) {
      map['avatar_storage_path'] = Variable<String>(avatarStoragePath);
    }
    map['friends_since'] = Variable<DateTime>(friendsSince);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedFriendsCompanion toCompanion(bool nullToAbsent) {
    return CachedFriendsCompanion(
      ownerUserId: Value(ownerUserId),
      userId: Value(userId),
      username: Value(username),
      displayName: Value(displayName),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      avatarStoragePath: avatarStoragePath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarStoragePath),
      friendsSince: Value(friendsSince),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedFriend.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFriend(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      userId: serializer.fromJson<String>(json['userId']),
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String>(json['displayName']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      avatarStoragePath: serializer.fromJson<String?>(
        json['avatarStoragePath'],
      ),
      friendsSince: serializer.fromJson<DateTime>(json['friendsSince']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'userId': serializer.toJson<String>(userId),
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String>(displayName),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'avatarStoragePath': serializer.toJson<String?>(avatarStoragePath),
      'friendsSince': serializer.toJson<DateTime>(friendsSince),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedFriend copyWith({
    String? ownerUserId,
    String? userId,
    String? username,
    String? displayName,
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> avatarStoragePath = const Value.absent(),
    DateTime? friendsSince,
    DateTime? cachedAt,
  }) => CachedFriend(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    userId: userId ?? this.userId,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    avatarStoragePath: avatarStoragePath.present
        ? avatarStoragePath.value
        : this.avatarStoragePath,
    friendsSince: friendsSince ?? this.friendsSince,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedFriend copyWithCompanion(CachedFriendsCompanion data) {
    return CachedFriend(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      userId: data.userId.present ? data.userId.value : this.userId,
      username: data.username.present ? data.username.value : this.username,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      avatarStoragePath: data.avatarStoragePath.present
          ? data.avatarStoragePath.value
          : this.avatarStoragePath,
      friendsSince: data.friendsSince.present
          ? data.friendsSince.value
          : this.friendsSince,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFriend(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('avatarStoragePath: $avatarStoragePath, ')
          ..write('friendsSince: $friendsSince, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    userId,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    friendsSince,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFriend &&
          other.ownerUserId == this.ownerUserId &&
          other.userId == this.userId &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.avatarUrl == this.avatarUrl &&
          other.avatarStoragePath == this.avatarStoragePath &&
          other.friendsSince == this.friendsSince &&
          other.cachedAt == this.cachedAt);
}

class CachedFriendsCompanion extends UpdateCompanion<CachedFriend> {
  final Value<String> ownerUserId;
  final Value<String> userId;
  final Value<String> username;
  final Value<String> displayName;
  final Value<String?> avatarUrl;
  final Value<String?> avatarStoragePath;
  final Value<DateTime> friendsSince;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedFriendsCompanion({
    this.ownerUserId = const Value.absent(),
    this.userId = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.avatarStoragePath = const Value.absent(),
    this.friendsSince = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedFriendsCompanion.insert({
    required String ownerUserId,
    required String userId,
    required String username,
    required String displayName,
    this.avatarUrl = const Value.absent(),
    this.avatarStoragePath = const Value.absent(),
    required DateTime friendsSince,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       userId = Value(userId),
       username = Value(username),
       displayName = Value(displayName),
       friendsSince = Value(friendsSince),
       cachedAt = Value(cachedAt);
  static Insertable<CachedFriend> custom({
    Expression<String>? ownerUserId,
    Expression<String>? userId,
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<String>? avatarUrl,
    Expression<String>? avatarStoragePath,
    Expression<DateTime>? friendsSince,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (avatarStoragePath != null) 'avatar_storage_path': avatarStoragePath,
      if (friendsSince != null) 'friends_since': friendsSince,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedFriendsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? userId,
    Value<String>? username,
    Value<String>? displayName,
    Value<String?>? avatarUrl,
    Value<String?>? avatarStoragePath,
    Value<DateTime>? friendsSince,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedFriendsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarStoragePath: avatarStoragePath ?? this.avatarStoragePath,
      friendsSince: friendsSince ?? this.friendsSince,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (avatarStoragePath.present) {
      map['avatar_storage_path'] = Variable<String>(avatarStoragePath.value);
    }
    if (friendsSince.present) {
      map['friends_since'] = Variable<DateTime>(friendsSince.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedFriendsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('avatarStoragePath: $avatarStoragePath, ')
          ..write('friendsSince: $friendsSince, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedFriendRequestsTable extends CachedFriendRequests
    with TableInfo<$CachedFriendRequestsTable, CachedFriendRequest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedFriendRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerUsernameMeta = const VerificationMeta(
    'peerUsername',
  );
  @override
  late final GeneratedColumn<String> peerUsername = GeneratedColumn<String>(
    'peer_username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDisplayNameMeta = const VerificationMeta(
    'peerDisplayName',
  );
  @override
  late final GeneratedColumn<String> peerDisplayName = GeneratedColumn<String>(
    'peer_display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerAvatarUrlMeta = const VerificationMeta(
    'peerAvatarUrl',
  );
  @override
  late final GeneratedColumn<String> peerAvatarUrl = GeneratedColumn<String>(
    'peer_avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerAvatarStoragePathMeta =
      const VerificationMeta('peerAvatarStoragePath');
  @override
  late final GeneratedColumn<String> peerAvatarStoragePath =
      GeneratedColumn<String>(
        'peer_avatar_storage_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _peerFriendCountMeta = const VerificationMeta(
    'peerFriendCount',
  );
  @override
  late final GeneratedColumn<int> peerFriendCount = GeneratedColumn<int>(
    'peer_friend_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestedAtMeta = const VerificationMeta(
    'requestedAt',
  );
  @override
  late final GeneratedColumn<DateTime> requestedAt = GeneratedColumn<DateTime>(
    'requested_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    requestId,
    peerId,
    peerUsername,
    peerDisplayName,
    peerAvatarUrl,
    peerAvatarStoragePath,
    peerFriendCount,
    direction,
    requestedAt,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_friend_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFriendRequest> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('peer_username')) {
      context.handle(
        _peerUsernameMeta,
        peerUsername.isAcceptableOrUnknown(
          data['peer_username']!,
          _peerUsernameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerUsernameMeta);
    }
    if (data.containsKey('peer_display_name')) {
      context.handle(
        _peerDisplayNameMeta,
        peerDisplayName.isAcceptableOrUnknown(
          data['peer_display_name']!,
          _peerDisplayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerDisplayNameMeta);
    }
    if (data.containsKey('peer_avatar_url')) {
      context.handle(
        _peerAvatarUrlMeta,
        peerAvatarUrl.isAcceptableOrUnknown(
          data['peer_avatar_url']!,
          _peerAvatarUrlMeta,
        ),
      );
    }
    if (data.containsKey('peer_avatar_storage_path')) {
      context.handle(
        _peerAvatarStoragePathMeta,
        peerAvatarStoragePath.isAcceptableOrUnknown(
          data['peer_avatar_storage_path']!,
          _peerAvatarStoragePathMeta,
        ),
      );
    }
    if (data.containsKey('peer_friend_count')) {
      context.handle(
        _peerFriendCountMeta,
        peerFriendCount.isAcceptableOrUnknown(
          data['peer_friend_count']!,
          _peerFriendCountMeta,
        ),
      );
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('requested_at')) {
      context.handle(
        _requestedAtMeta,
        requestedAt.isAcceptableOrUnknown(
          data['requested_at']!,
          _requestedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestedAtMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, requestId};
  @override
  CachedFriendRequest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFriendRequest(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      peerUsername: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_username'],
      )!,
      peerDisplayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_display_name'],
      )!,
      peerAvatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_avatar_url'],
      ),
      peerAvatarStoragePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_avatar_storage_path'],
      ),
      peerFriendCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}peer_friend_count'],
      ),
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      requestedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}requested_at'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedFriendRequestsTable createAlias(String alias) {
    return $CachedFriendRequestsTable(attachedDatabase, alias);
  }
}

class CachedFriendRequest extends DataClass
    implements Insertable<CachedFriendRequest> {
  final String ownerUserId;
  final String requestId;
  final String peerId;
  final String peerUsername;
  final String peerDisplayName;
  final String? peerAvatarUrl;
  final String? peerAvatarStoragePath;
  final int? peerFriendCount;
  final String direction;
  final DateTime requestedAt;
  final DateTime cachedAt;
  const CachedFriendRequest({
    required this.ownerUserId,
    required this.requestId,
    required this.peerId,
    required this.peerUsername,
    required this.peerDisplayName,
    this.peerAvatarUrl,
    this.peerAvatarStoragePath,
    this.peerFriendCount,
    required this.direction,
    required this.requestedAt,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['request_id'] = Variable<String>(requestId);
    map['peer_id'] = Variable<String>(peerId);
    map['peer_username'] = Variable<String>(peerUsername);
    map['peer_display_name'] = Variable<String>(peerDisplayName);
    if (!nullToAbsent || peerAvatarUrl != null) {
      map['peer_avatar_url'] = Variable<String>(peerAvatarUrl);
    }
    if (!nullToAbsent || peerAvatarStoragePath != null) {
      map['peer_avatar_storage_path'] = Variable<String>(peerAvatarStoragePath);
    }
    if (!nullToAbsent || peerFriendCount != null) {
      map['peer_friend_count'] = Variable<int>(peerFriendCount);
    }
    map['direction'] = Variable<String>(direction);
    map['requested_at'] = Variable<DateTime>(requestedAt);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedFriendRequestsCompanion toCompanion(bool nullToAbsent) {
    return CachedFriendRequestsCompanion(
      ownerUserId: Value(ownerUserId),
      requestId: Value(requestId),
      peerId: Value(peerId),
      peerUsername: Value(peerUsername),
      peerDisplayName: Value(peerDisplayName),
      peerAvatarUrl: peerAvatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(peerAvatarUrl),
      peerAvatarStoragePath: peerAvatarStoragePath == null && nullToAbsent
          ? const Value.absent()
          : Value(peerAvatarStoragePath),
      peerFriendCount: peerFriendCount == null && nullToAbsent
          ? const Value.absent()
          : Value(peerFriendCount),
      direction: Value(direction),
      requestedAt: Value(requestedAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedFriendRequest.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFriendRequest(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      requestId: serializer.fromJson<String>(json['requestId']),
      peerId: serializer.fromJson<String>(json['peerId']),
      peerUsername: serializer.fromJson<String>(json['peerUsername']),
      peerDisplayName: serializer.fromJson<String>(json['peerDisplayName']),
      peerAvatarUrl: serializer.fromJson<String?>(json['peerAvatarUrl']),
      peerAvatarStoragePath: serializer.fromJson<String?>(
        json['peerAvatarStoragePath'],
      ),
      peerFriendCount: serializer.fromJson<int?>(json['peerFriendCount']),
      direction: serializer.fromJson<String>(json['direction']),
      requestedAt: serializer.fromJson<DateTime>(json['requestedAt']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'requestId': serializer.toJson<String>(requestId),
      'peerId': serializer.toJson<String>(peerId),
      'peerUsername': serializer.toJson<String>(peerUsername),
      'peerDisplayName': serializer.toJson<String>(peerDisplayName),
      'peerAvatarUrl': serializer.toJson<String?>(peerAvatarUrl),
      'peerAvatarStoragePath': serializer.toJson<String?>(
        peerAvatarStoragePath,
      ),
      'peerFriendCount': serializer.toJson<int?>(peerFriendCount),
      'direction': serializer.toJson<String>(direction),
      'requestedAt': serializer.toJson<DateTime>(requestedAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedFriendRequest copyWith({
    String? ownerUserId,
    String? requestId,
    String? peerId,
    String? peerUsername,
    String? peerDisplayName,
    Value<String?> peerAvatarUrl = const Value.absent(),
    Value<String?> peerAvatarStoragePath = const Value.absent(),
    Value<int?> peerFriendCount = const Value.absent(),
    String? direction,
    DateTime? requestedAt,
    DateTime? cachedAt,
  }) => CachedFriendRequest(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    requestId: requestId ?? this.requestId,
    peerId: peerId ?? this.peerId,
    peerUsername: peerUsername ?? this.peerUsername,
    peerDisplayName: peerDisplayName ?? this.peerDisplayName,
    peerAvatarUrl: peerAvatarUrl.present
        ? peerAvatarUrl.value
        : this.peerAvatarUrl,
    peerAvatarStoragePath: peerAvatarStoragePath.present
        ? peerAvatarStoragePath.value
        : this.peerAvatarStoragePath,
    peerFriendCount: peerFriendCount.present
        ? peerFriendCount.value
        : this.peerFriendCount,
    direction: direction ?? this.direction,
    requestedAt: requestedAt ?? this.requestedAt,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedFriendRequest copyWithCompanion(CachedFriendRequestsCompanion data) {
    return CachedFriendRequest(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      peerUsername: data.peerUsername.present
          ? data.peerUsername.value
          : this.peerUsername,
      peerDisplayName: data.peerDisplayName.present
          ? data.peerDisplayName.value
          : this.peerDisplayName,
      peerAvatarUrl: data.peerAvatarUrl.present
          ? data.peerAvatarUrl.value
          : this.peerAvatarUrl,
      peerAvatarStoragePath: data.peerAvatarStoragePath.present
          ? data.peerAvatarStoragePath.value
          : this.peerAvatarStoragePath,
      peerFriendCount: data.peerFriendCount.present
          ? data.peerFriendCount.value
          : this.peerFriendCount,
      direction: data.direction.present ? data.direction.value : this.direction,
      requestedAt: data.requestedAt.present
          ? data.requestedAt.value
          : this.requestedAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFriendRequest(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('requestId: $requestId, ')
          ..write('peerId: $peerId, ')
          ..write('peerUsername: $peerUsername, ')
          ..write('peerDisplayName: $peerDisplayName, ')
          ..write('peerAvatarUrl: $peerAvatarUrl, ')
          ..write('peerAvatarStoragePath: $peerAvatarStoragePath, ')
          ..write('peerFriendCount: $peerFriendCount, ')
          ..write('direction: $direction, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    requestId,
    peerId,
    peerUsername,
    peerDisplayName,
    peerAvatarUrl,
    peerAvatarStoragePath,
    peerFriendCount,
    direction,
    requestedAt,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFriendRequest &&
          other.ownerUserId == this.ownerUserId &&
          other.requestId == this.requestId &&
          other.peerId == this.peerId &&
          other.peerUsername == this.peerUsername &&
          other.peerDisplayName == this.peerDisplayName &&
          other.peerAvatarUrl == this.peerAvatarUrl &&
          other.peerAvatarStoragePath == this.peerAvatarStoragePath &&
          other.peerFriendCount == this.peerFriendCount &&
          other.direction == this.direction &&
          other.requestedAt == this.requestedAt &&
          other.cachedAt == this.cachedAt);
}

class CachedFriendRequestsCompanion
    extends UpdateCompanion<CachedFriendRequest> {
  final Value<String> ownerUserId;
  final Value<String> requestId;
  final Value<String> peerId;
  final Value<String> peerUsername;
  final Value<String> peerDisplayName;
  final Value<String?> peerAvatarUrl;
  final Value<String?> peerAvatarStoragePath;
  final Value<int?> peerFriendCount;
  final Value<String> direction;
  final Value<DateTime> requestedAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedFriendRequestsCompanion({
    this.ownerUserId = const Value.absent(),
    this.requestId = const Value.absent(),
    this.peerId = const Value.absent(),
    this.peerUsername = const Value.absent(),
    this.peerDisplayName = const Value.absent(),
    this.peerAvatarUrl = const Value.absent(),
    this.peerAvatarStoragePath = const Value.absent(),
    this.peerFriendCount = const Value.absent(),
    this.direction = const Value.absent(),
    this.requestedAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedFriendRequestsCompanion.insert({
    required String ownerUserId,
    required String requestId,
    required String peerId,
    required String peerUsername,
    required String peerDisplayName,
    this.peerAvatarUrl = const Value.absent(),
    this.peerAvatarStoragePath = const Value.absent(),
    this.peerFriendCount = const Value.absent(),
    required String direction,
    required DateTime requestedAt,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       requestId = Value(requestId),
       peerId = Value(peerId),
       peerUsername = Value(peerUsername),
       peerDisplayName = Value(peerDisplayName),
       direction = Value(direction),
       requestedAt = Value(requestedAt),
       cachedAt = Value(cachedAt);
  static Insertable<CachedFriendRequest> custom({
    Expression<String>? ownerUserId,
    Expression<String>? requestId,
    Expression<String>? peerId,
    Expression<String>? peerUsername,
    Expression<String>? peerDisplayName,
    Expression<String>? peerAvatarUrl,
    Expression<String>? peerAvatarStoragePath,
    Expression<int>? peerFriendCount,
    Expression<String>? direction,
    Expression<DateTime>? requestedAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (requestId != null) 'request_id': requestId,
      if (peerId != null) 'peer_id': peerId,
      if (peerUsername != null) 'peer_username': peerUsername,
      if (peerDisplayName != null) 'peer_display_name': peerDisplayName,
      if (peerAvatarUrl != null) 'peer_avatar_url': peerAvatarUrl,
      if (peerAvatarStoragePath != null)
        'peer_avatar_storage_path': peerAvatarStoragePath,
      if (peerFriendCount != null) 'peer_friend_count': peerFriendCount,
      if (direction != null) 'direction': direction,
      if (requestedAt != null) 'requested_at': requestedAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedFriendRequestsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? requestId,
    Value<String>? peerId,
    Value<String>? peerUsername,
    Value<String>? peerDisplayName,
    Value<String?>? peerAvatarUrl,
    Value<String?>? peerAvatarStoragePath,
    Value<int?>? peerFriendCount,
    Value<String>? direction,
    Value<DateTime>? requestedAt,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedFriendRequestsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      requestId: requestId ?? this.requestId,
      peerId: peerId ?? this.peerId,
      peerUsername: peerUsername ?? this.peerUsername,
      peerDisplayName: peerDisplayName ?? this.peerDisplayName,
      peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
      peerAvatarStoragePath:
          peerAvatarStoragePath ?? this.peerAvatarStoragePath,
      peerFriendCount: peerFriendCount ?? this.peerFriendCount,
      direction: direction ?? this.direction,
      requestedAt: requestedAt ?? this.requestedAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (peerUsername.present) {
      map['peer_username'] = Variable<String>(peerUsername.value);
    }
    if (peerDisplayName.present) {
      map['peer_display_name'] = Variable<String>(peerDisplayName.value);
    }
    if (peerAvatarUrl.present) {
      map['peer_avatar_url'] = Variable<String>(peerAvatarUrl.value);
    }
    if (peerAvatarStoragePath.present) {
      map['peer_avatar_storage_path'] = Variable<String>(
        peerAvatarStoragePath.value,
      );
    }
    if (peerFriendCount.present) {
      map['peer_friend_count'] = Variable<int>(peerFriendCount.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (requestedAt.present) {
      map['requested_at'] = Variable<DateTime>(requestedAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedFriendRequestsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('requestId: $requestId, ')
          ..write('peerId: $peerId, ')
          ..write('peerUsername: $peerUsername, ')
          ..write('peerDisplayName: $peerDisplayName, ')
          ..write('peerAvatarUrl: $peerAvatarUrl, ')
          ..write('peerAvatarStoragePath: $peerAvatarStoragePath, ')
          ..write('peerFriendCount: $peerFriendCount, ')
          ..write('direction: $direction, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedFriendLocationsTable extends CachedFriendLocations
    with TableInfo<$CachedFriendLocationsTable, CachedFriendLocation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedFriendLocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _friendUserIdMeta = const VerificationMeta(
    'friendUserId',
  );
  @override
  late final GeneratedColumn<String> friendUserId = GeneratedColumn<String>(
    'friend_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationUpdatedAtMsMeta =
      const VerificationMeta('locationUpdatedAtMs');
  @override
  late final GeneratedColumn<int> locationUpdatedAtMs = GeneratedColumn<int>(
    'location_updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    friendUserId,
    latitude,
    longitude,
    locationUpdatedAtMs,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_friend_locations';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFriendLocation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('friend_user_id')) {
      context.handle(
        _friendUserIdMeta,
        friendUserId.isAcceptableOrUnknown(
          data['friend_user_id']!,
          _friendUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_friendUserIdMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('location_updated_at_ms')) {
      context.handle(
        _locationUpdatedAtMsMeta,
        locationUpdatedAtMs.isAcceptableOrUnknown(
          data['location_updated_at_ms']!,
          _locationUpdatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationUpdatedAtMsMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, friendUserId};
  @override
  CachedFriendLocation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFriendLocation(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      friendUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}friend_user_id'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      locationUpdatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}location_updated_at_ms'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedFriendLocationsTable createAlias(String alias) {
    return $CachedFriendLocationsTable(attachedDatabase, alias);
  }
}

class CachedFriendLocation extends DataClass
    implements Insertable<CachedFriendLocation> {
  final String ownerUserId;
  final String friendUserId;
  final double latitude;
  final double longitude;
  final int locationUpdatedAtMs;
  final DateTime cachedAt;
  const CachedFriendLocation({
    required this.ownerUserId,
    required this.friendUserId,
    required this.latitude,
    required this.longitude,
    required this.locationUpdatedAtMs,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['friend_user_id'] = Variable<String>(friendUserId);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['location_updated_at_ms'] = Variable<int>(locationUpdatedAtMs);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedFriendLocationsCompanion toCompanion(bool nullToAbsent) {
    return CachedFriendLocationsCompanion(
      ownerUserId: Value(ownerUserId),
      friendUserId: Value(friendUserId),
      latitude: Value(latitude),
      longitude: Value(longitude),
      locationUpdatedAtMs: Value(locationUpdatedAtMs),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedFriendLocation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFriendLocation(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      friendUserId: serializer.fromJson<String>(json['friendUserId']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      locationUpdatedAtMs: serializer.fromJson<int>(
        json['locationUpdatedAtMs'],
      ),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'friendUserId': serializer.toJson<String>(friendUserId),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'locationUpdatedAtMs': serializer.toJson<int>(locationUpdatedAtMs),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedFriendLocation copyWith({
    String? ownerUserId,
    String? friendUserId,
    double? latitude,
    double? longitude,
    int? locationUpdatedAtMs,
    DateTime? cachedAt,
  }) => CachedFriendLocation(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    friendUserId: friendUserId ?? this.friendUserId,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    locationUpdatedAtMs: locationUpdatedAtMs ?? this.locationUpdatedAtMs,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedFriendLocation copyWithCompanion(CachedFriendLocationsCompanion data) {
    return CachedFriendLocation(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      friendUserId: data.friendUserId.present
          ? data.friendUserId.value
          : this.friendUserId,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      locationUpdatedAtMs: data.locationUpdatedAtMs.present
          ? data.locationUpdatedAtMs.value
          : this.locationUpdatedAtMs,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFriendLocation(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('friendUserId: $friendUserId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationUpdatedAtMs: $locationUpdatedAtMs, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    friendUserId,
    latitude,
    longitude,
    locationUpdatedAtMs,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFriendLocation &&
          other.ownerUserId == this.ownerUserId &&
          other.friendUserId == this.friendUserId &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationUpdatedAtMs == this.locationUpdatedAtMs &&
          other.cachedAt == this.cachedAt);
}

class CachedFriendLocationsCompanion
    extends UpdateCompanion<CachedFriendLocation> {
  final Value<String> ownerUserId;
  final Value<String> friendUserId;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<int> locationUpdatedAtMs;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedFriendLocationsCompanion({
    this.ownerUserId = const Value.absent(),
    this.friendUserId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationUpdatedAtMs = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedFriendLocationsCompanion.insert({
    required String ownerUserId,
    required String friendUserId,
    required double latitude,
    required double longitude,
    required int locationUpdatedAtMs,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       friendUserId = Value(friendUserId),
       latitude = Value(latitude),
       longitude = Value(longitude),
       locationUpdatedAtMs = Value(locationUpdatedAtMs),
       cachedAt = Value(cachedAt);
  static Insertable<CachedFriendLocation> custom({
    Expression<String>? ownerUserId,
    Expression<String>? friendUserId,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? locationUpdatedAtMs,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (friendUserId != null) 'friend_user_id': friendUserId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationUpdatedAtMs != null)
        'location_updated_at_ms': locationUpdatedAtMs,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedFriendLocationsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? friendUserId,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<int>? locationUpdatedAtMs,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedFriendLocationsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      friendUserId: friendUserId ?? this.friendUserId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationUpdatedAtMs: locationUpdatedAtMs ?? this.locationUpdatedAtMs,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (friendUserId.present) {
      map['friend_user_id'] = Variable<String>(friendUserId.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (locationUpdatedAtMs.present) {
      map['location_updated_at_ms'] = Variable<int>(locationUpdatedAtMs.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedFriendLocationsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('friendUserId: $friendUserId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationUpdatedAtMs: $locationUpdatedAtMs, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedContactMatchesTable extends CachedContactMatches
    with TableInfo<$CachedContactMatchesTable, CachedContactMatch> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedContactMatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneKeyMeta = const VerificationMeta(
    'phoneKey',
  );
  @override
  late final GeneratedColumn<String> phoneKey = GeneratedColumn<String>(
    'phone_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isRegisteredMeta = const VerificationMeta(
    'isRegistered',
  );
  @override
  late final GeneratedColumn<bool> isRegistered = GeneratedColumn<bool>(
    'is_registered',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_registered" IN (0, 1))',
    ),
  );
  static const VerificationMeta _candidateIdMeta = const VerificationMeta(
    'candidateId',
  );
  @override
  late final GeneratedColumn<String> candidateId = GeneratedColumn<String>(
    'candidate_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarStoragePathMeta = const VerificationMeta(
    'avatarStoragePath',
  );
  @override
  late final GeneratedColumn<String> avatarStoragePath =
      GeneratedColumn<String>(
        'avatar_storage_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _friendCountMeta = const VerificationMeta(
    'friendCount',
  );
  @override
  late final GeneratedColumn<int> friendCount = GeneratedColumn<int>(
    'friend_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkedAt = GeneratedColumn<DateTime>(
    'checked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    phoneKey,
    isRegistered,
    candidateId,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    friendCount,
    checkedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_contact_matches';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedContactMatch> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('phone_key')) {
      context.handle(
        _phoneKeyMeta,
        phoneKey.isAcceptableOrUnknown(data['phone_key']!, _phoneKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_phoneKeyMeta);
    }
    if (data.containsKey('is_registered')) {
      context.handle(
        _isRegisteredMeta,
        isRegistered.isAcceptableOrUnknown(
          data['is_registered']!,
          _isRegisteredMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isRegisteredMeta);
    }
    if (data.containsKey('candidate_id')) {
      context.handle(
        _candidateIdMeta,
        candidateId.isAcceptableOrUnknown(
          data['candidate_id']!,
          _candidateIdMeta,
        ),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('avatar_storage_path')) {
      context.handle(
        _avatarStoragePathMeta,
        avatarStoragePath.isAcceptableOrUnknown(
          data['avatar_storage_path']!,
          _avatarStoragePathMeta,
        ),
      );
    }
    if (data.containsKey('friend_count')) {
      context.handle(
        _friendCountMeta,
        friendCount.isAcceptableOrUnknown(
          data['friend_count']!,
          _friendCountMeta,
        ),
      );
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_checkedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, phoneKey};
  @override
  CachedContactMatch map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedContactMatch(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      phoneKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_key'],
      )!,
      isRegistered: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_registered'],
      )!,
      candidateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}candidate_id'],
      ),
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      avatarStoragePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_storage_path'],
      ),
      friendCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}friend_count'],
      ),
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checked_at'],
      )!,
    );
  }

  @override
  $CachedContactMatchesTable createAlias(String alias) {
    return $CachedContactMatchesTable(attachedDatabase, alias);
  }
}

class CachedContactMatch extends DataClass
    implements Insertable<CachedContactMatch> {
  final String ownerUserId;
  final String phoneKey;
  final bool isRegistered;
  final String? candidateId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final int? friendCount;
  final DateTime checkedAt;
  const CachedContactMatch({
    required this.ownerUserId,
    required this.phoneKey,
    required this.isRegistered,
    this.candidateId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.avatarStoragePath,
    this.friendCount,
    required this.checkedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['phone_key'] = Variable<String>(phoneKey);
    map['is_registered'] = Variable<bool>(isRegistered);
    if (!nullToAbsent || candidateId != null) {
      map['candidate_id'] = Variable<String>(candidateId);
    }
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || avatarStoragePath != null) {
      map['avatar_storage_path'] = Variable<String>(avatarStoragePath);
    }
    if (!nullToAbsent || friendCount != null) {
      map['friend_count'] = Variable<int>(friendCount);
    }
    map['checked_at'] = Variable<DateTime>(checkedAt);
    return map;
  }

  CachedContactMatchesCompanion toCompanion(bool nullToAbsent) {
    return CachedContactMatchesCompanion(
      ownerUserId: Value(ownerUserId),
      phoneKey: Value(phoneKey),
      isRegistered: Value(isRegistered),
      candidateId: candidateId == null && nullToAbsent
          ? const Value.absent()
          : Value(candidateId),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      avatarStoragePath: avatarStoragePath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarStoragePath),
      friendCount: friendCount == null && nullToAbsent
          ? const Value.absent()
          : Value(friendCount),
      checkedAt: Value(checkedAt),
    );
  }

  factory CachedContactMatch.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedContactMatch(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      phoneKey: serializer.fromJson<String>(json['phoneKey']),
      isRegistered: serializer.fromJson<bool>(json['isRegistered']),
      candidateId: serializer.fromJson<String?>(json['candidateId']),
      username: serializer.fromJson<String?>(json['username']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      avatarStoragePath: serializer.fromJson<String?>(
        json['avatarStoragePath'],
      ),
      friendCount: serializer.fromJson<int?>(json['friendCount']),
      checkedAt: serializer.fromJson<DateTime>(json['checkedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'phoneKey': serializer.toJson<String>(phoneKey),
      'isRegistered': serializer.toJson<bool>(isRegistered),
      'candidateId': serializer.toJson<String?>(candidateId),
      'username': serializer.toJson<String?>(username),
      'displayName': serializer.toJson<String?>(displayName),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'avatarStoragePath': serializer.toJson<String?>(avatarStoragePath),
      'friendCount': serializer.toJson<int?>(friendCount),
      'checkedAt': serializer.toJson<DateTime>(checkedAt),
    };
  }

  CachedContactMatch copyWith({
    String? ownerUserId,
    String? phoneKey,
    bool? isRegistered,
    Value<String?> candidateId = const Value.absent(),
    Value<String?> username = const Value.absent(),
    Value<String?> displayName = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> avatarStoragePath = const Value.absent(),
    Value<int?> friendCount = const Value.absent(),
    DateTime? checkedAt,
  }) => CachedContactMatch(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    phoneKey: phoneKey ?? this.phoneKey,
    isRegistered: isRegistered ?? this.isRegistered,
    candidateId: candidateId.present ? candidateId.value : this.candidateId,
    username: username.present ? username.value : this.username,
    displayName: displayName.present ? displayName.value : this.displayName,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    avatarStoragePath: avatarStoragePath.present
        ? avatarStoragePath.value
        : this.avatarStoragePath,
    friendCount: friendCount.present ? friendCount.value : this.friendCount,
    checkedAt: checkedAt ?? this.checkedAt,
  );
  CachedContactMatch copyWithCompanion(CachedContactMatchesCompanion data) {
    return CachedContactMatch(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      phoneKey: data.phoneKey.present ? data.phoneKey.value : this.phoneKey,
      isRegistered: data.isRegistered.present
          ? data.isRegistered.value
          : this.isRegistered,
      candidateId: data.candidateId.present
          ? data.candidateId.value
          : this.candidateId,
      username: data.username.present ? data.username.value : this.username,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      avatarStoragePath: data.avatarStoragePath.present
          ? data.avatarStoragePath.value
          : this.avatarStoragePath,
      friendCount: data.friendCount.present
          ? data.friendCount.value
          : this.friendCount,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedContactMatch(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('phoneKey: $phoneKey, ')
          ..write('isRegistered: $isRegistered, ')
          ..write('candidateId: $candidateId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('avatarStoragePath: $avatarStoragePath, ')
          ..write('friendCount: $friendCount, ')
          ..write('checkedAt: $checkedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    phoneKey,
    isRegistered,
    candidateId,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    friendCount,
    checkedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedContactMatch &&
          other.ownerUserId == this.ownerUserId &&
          other.phoneKey == this.phoneKey &&
          other.isRegistered == this.isRegistered &&
          other.candidateId == this.candidateId &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.avatarUrl == this.avatarUrl &&
          other.avatarStoragePath == this.avatarStoragePath &&
          other.friendCount == this.friendCount &&
          other.checkedAt == this.checkedAt);
}

class CachedContactMatchesCompanion
    extends UpdateCompanion<CachedContactMatch> {
  final Value<String> ownerUserId;
  final Value<String> phoneKey;
  final Value<bool> isRegistered;
  final Value<String?> candidateId;
  final Value<String?> username;
  final Value<String?> displayName;
  final Value<String?> avatarUrl;
  final Value<String?> avatarStoragePath;
  final Value<int?> friendCount;
  final Value<DateTime> checkedAt;
  final Value<int> rowid;
  const CachedContactMatchesCompanion({
    this.ownerUserId = const Value.absent(),
    this.phoneKey = const Value.absent(),
    this.isRegistered = const Value.absent(),
    this.candidateId = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.avatarStoragePath = const Value.absent(),
    this.friendCount = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedContactMatchesCompanion.insert({
    required String ownerUserId,
    required String phoneKey,
    required bool isRegistered,
    this.candidateId = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.avatarStoragePath = const Value.absent(),
    this.friendCount = const Value.absent(),
    required DateTime checkedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       phoneKey = Value(phoneKey),
       isRegistered = Value(isRegistered),
       checkedAt = Value(checkedAt);
  static Insertable<CachedContactMatch> custom({
    Expression<String>? ownerUserId,
    Expression<String>? phoneKey,
    Expression<bool>? isRegistered,
    Expression<String>? candidateId,
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<String>? avatarUrl,
    Expression<String>? avatarStoragePath,
    Expression<int>? friendCount,
    Expression<DateTime>? checkedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (phoneKey != null) 'phone_key': phoneKey,
      if (isRegistered != null) 'is_registered': isRegistered,
      if (candidateId != null) 'candidate_id': candidateId,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (avatarStoragePath != null) 'avatar_storage_path': avatarStoragePath,
      if (friendCount != null) 'friend_count': friendCount,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedContactMatchesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? phoneKey,
    Value<bool>? isRegistered,
    Value<String?>? candidateId,
    Value<String?>? username,
    Value<String?>? displayName,
    Value<String?>? avatarUrl,
    Value<String?>? avatarStoragePath,
    Value<int?>? friendCount,
    Value<DateTime>? checkedAt,
    Value<int>? rowid,
  }) {
    return CachedContactMatchesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      phoneKey: phoneKey ?? this.phoneKey,
      isRegistered: isRegistered ?? this.isRegistered,
      candidateId: candidateId ?? this.candidateId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarStoragePath: avatarStoragePath ?? this.avatarStoragePath,
      friendCount: friendCount ?? this.friendCount,
      checkedAt: checkedAt ?? this.checkedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (phoneKey.present) {
      map['phone_key'] = Variable<String>(phoneKey.value);
    }
    if (isRegistered.present) {
      map['is_registered'] = Variable<bool>(isRegistered.value);
    }
    if (candidateId.present) {
      map['candidate_id'] = Variable<String>(candidateId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (avatarStoragePath.present) {
      map['avatar_storage_path'] = Variable<String>(avatarStoragePath.value);
    }
    if (friendCount.present) {
      map['friend_count'] = Variable<int>(friendCount.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<DateTime>(checkedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedContactMatchesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('phoneKey: $phoneKey, ')
          ..write('isRegistered: $isRegistered, ')
          ..write('candidateId: $candidateId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('avatarStoragePath: $avatarStoragePath, ')
          ..write('friendCount: $friendCount, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedSearchPrivacySettingsTable extends CachedSearchPrivacySettings
    with
        TableInfo<
          $CachedSearchPrivacySettingsTable,
          CachedSearchPrivacySetting
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedSearchPrivacySettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _searchByUsernameMeta = const VerificationMeta(
    'searchByUsername',
  );
  @override
  late final GeneratedColumn<bool> searchByUsername = GeneratedColumn<bool>(
    'search_by_username',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("search_by_username" IN (0, 1))',
    ),
  );
  static const VerificationMeta _searchByPhoneMeta = const VerificationMeta(
    'searchByPhone',
  );
  @override
  late final GeneratedColumn<bool> searchByPhone = GeneratedColumn<bool>(
    'search_by_phone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("search_by_phone" IN (0, 1))',
    ),
  );
  static const VerificationMeta _searchByNameMeta = const VerificationMeta(
    'searchByName',
  );
  @override
  late final GeneratedColumn<bool> searchByName = GeneratedColumn<bool>(
    'search_by_name',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("search_by_name" IN (0, 1))',
    ),
  );
  static const VerificationMeta _lastSeenVisibilityMeta =
      const VerificationMeta('lastSeenVisibility');
  @override
  late final GeneratedColumn<String> lastSeenVisibility =
      GeneratedColumn<String>(
        'last_seen_visibility',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('all'),
      );
  static const VerificationMeta _sharePreciseLocationMeta =
      const VerificationMeta('sharePreciseLocation');
  @override
  late final GeneratedColumn<bool> sharePreciseLocation = GeneratedColumn<bool>(
    'share_precise_location',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("share_precise_location" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _shareDistanceMeta = const VerificationMeta(
    'shareDistance',
  );
  @override
  late final GeneratedColumn<bool> shareDistance = GeneratedColumn<bool>(
    'share_distance',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("share_distance" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    searchByUsername,
    searchByPhone,
    searchByName,
    lastSeenVisibility,
    sharePreciseLocation,
    shareDistance,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_search_privacy_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedSearchPrivacySetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('search_by_username')) {
      context.handle(
        _searchByUsernameMeta,
        searchByUsername.isAcceptableOrUnknown(
          data['search_by_username']!,
          _searchByUsernameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_searchByUsernameMeta);
    }
    if (data.containsKey('search_by_phone')) {
      context.handle(
        _searchByPhoneMeta,
        searchByPhone.isAcceptableOrUnknown(
          data['search_by_phone']!,
          _searchByPhoneMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_searchByPhoneMeta);
    }
    if (data.containsKey('search_by_name')) {
      context.handle(
        _searchByNameMeta,
        searchByName.isAcceptableOrUnknown(
          data['search_by_name']!,
          _searchByNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_searchByNameMeta);
    }
    if (data.containsKey('last_seen_visibility')) {
      context.handle(
        _lastSeenVisibilityMeta,
        lastSeenVisibility.isAcceptableOrUnknown(
          data['last_seen_visibility']!,
          _lastSeenVisibilityMeta,
        ),
      );
    }
    if (data.containsKey('share_precise_location')) {
      context.handle(
        _sharePreciseLocationMeta,
        sharePreciseLocation.isAcceptableOrUnknown(
          data['share_precise_location']!,
          _sharePreciseLocationMeta,
        ),
      );
    }
    if (data.containsKey('share_distance')) {
      context.handle(
        _shareDistanceMeta,
        shareDistance.isAcceptableOrUnknown(
          data['share_distance']!,
          _shareDistanceMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId};
  @override
  CachedSearchPrivacySetting map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedSearchPrivacySetting(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      searchByUsername: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}search_by_username'],
      )!,
      searchByPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}search_by_phone'],
      )!,
      searchByName: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}search_by_name'],
      )!,
      lastSeenVisibility: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_seen_visibility'],
      )!,
      sharePreciseLocation: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}share_precise_location'],
      )!,
      shareDistance: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}share_distance'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedSearchPrivacySettingsTable createAlias(String alias) {
    return $CachedSearchPrivacySettingsTable(attachedDatabase, alias);
  }
}

class CachedSearchPrivacySetting extends DataClass
    implements Insertable<CachedSearchPrivacySetting> {
  final String ownerUserId;
  final bool searchByUsername;
  final bool searchByPhone;
  final bool searchByName;
  final String lastSeenVisibility;
  final bool sharePreciseLocation;
  final bool shareDistance;
  final DateTime cachedAt;
  const CachedSearchPrivacySetting({
    required this.ownerUserId,
    required this.searchByUsername,
    required this.searchByPhone,
    required this.searchByName,
    required this.lastSeenVisibility,
    required this.sharePreciseLocation,
    required this.shareDistance,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['search_by_username'] = Variable<bool>(searchByUsername);
    map['search_by_phone'] = Variable<bool>(searchByPhone);
    map['search_by_name'] = Variable<bool>(searchByName);
    map['last_seen_visibility'] = Variable<String>(lastSeenVisibility);
    map['share_precise_location'] = Variable<bool>(sharePreciseLocation);
    map['share_distance'] = Variable<bool>(shareDistance);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedSearchPrivacySettingsCompanion toCompanion(bool nullToAbsent) {
    return CachedSearchPrivacySettingsCompanion(
      ownerUserId: Value(ownerUserId),
      searchByUsername: Value(searchByUsername),
      searchByPhone: Value(searchByPhone),
      searchByName: Value(searchByName),
      lastSeenVisibility: Value(lastSeenVisibility),
      sharePreciseLocation: Value(sharePreciseLocation),
      shareDistance: Value(shareDistance),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedSearchPrivacySetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedSearchPrivacySetting(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      searchByUsername: serializer.fromJson<bool>(json['searchByUsername']),
      searchByPhone: serializer.fromJson<bool>(json['searchByPhone']),
      searchByName: serializer.fromJson<bool>(json['searchByName']),
      lastSeenVisibility: serializer.fromJson<String>(
        json['lastSeenVisibility'],
      ),
      sharePreciseLocation: serializer.fromJson<bool>(
        json['sharePreciseLocation'],
      ),
      shareDistance: serializer.fromJson<bool>(json['shareDistance']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'searchByUsername': serializer.toJson<bool>(searchByUsername),
      'searchByPhone': serializer.toJson<bool>(searchByPhone),
      'searchByName': serializer.toJson<bool>(searchByName),
      'lastSeenVisibility': serializer.toJson<String>(lastSeenVisibility),
      'sharePreciseLocation': serializer.toJson<bool>(sharePreciseLocation),
      'shareDistance': serializer.toJson<bool>(shareDistance),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedSearchPrivacySetting copyWith({
    String? ownerUserId,
    bool? searchByUsername,
    bool? searchByPhone,
    bool? searchByName,
    String? lastSeenVisibility,
    bool? sharePreciseLocation,
    bool? shareDistance,
    DateTime? cachedAt,
  }) => CachedSearchPrivacySetting(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    searchByUsername: searchByUsername ?? this.searchByUsername,
    searchByPhone: searchByPhone ?? this.searchByPhone,
    searchByName: searchByName ?? this.searchByName,
    lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
    sharePreciseLocation: sharePreciseLocation ?? this.sharePreciseLocation,
    shareDistance: shareDistance ?? this.shareDistance,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedSearchPrivacySetting copyWithCompanion(
    CachedSearchPrivacySettingsCompanion data,
  ) {
    return CachedSearchPrivacySetting(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      searchByUsername: data.searchByUsername.present
          ? data.searchByUsername.value
          : this.searchByUsername,
      searchByPhone: data.searchByPhone.present
          ? data.searchByPhone.value
          : this.searchByPhone,
      searchByName: data.searchByName.present
          ? data.searchByName.value
          : this.searchByName,
      lastSeenVisibility: data.lastSeenVisibility.present
          ? data.lastSeenVisibility.value
          : this.lastSeenVisibility,
      sharePreciseLocation: data.sharePreciseLocation.present
          ? data.sharePreciseLocation.value
          : this.sharePreciseLocation,
      shareDistance: data.shareDistance.present
          ? data.shareDistance.value
          : this.shareDistance,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedSearchPrivacySetting(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('searchByUsername: $searchByUsername, ')
          ..write('searchByPhone: $searchByPhone, ')
          ..write('searchByName: $searchByName, ')
          ..write('lastSeenVisibility: $lastSeenVisibility, ')
          ..write('sharePreciseLocation: $sharePreciseLocation, ')
          ..write('shareDistance: $shareDistance, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    searchByUsername,
    searchByPhone,
    searchByName,
    lastSeenVisibility,
    sharePreciseLocation,
    shareDistance,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedSearchPrivacySetting &&
          other.ownerUserId == this.ownerUserId &&
          other.searchByUsername == this.searchByUsername &&
          other.searchByPhone == this.searchByPhone &&
          other.searchByName == this.searchByName &&
          other.lastSeenVisibility == this.lastSeenVisibility &&
          other.sharePreciseLocation == this.sharePreciseLocation &&
          other.shareDistance == this.shareDistance &&
          other.cachedAt == this.cachedAt);
}

class CachedSearchPrivacySettingsCompanion
    extends UpdateCompanion<CachedSearchPrivacySetting> {
  final Value<String> ownerUserId;
  final Value<bool> searchByUsername;
  final Value<bool> searchByPhone;
  final Value<bool> searchByName;
  final Value<String> lastSeenVisibility;
  final Value<bool> sharePreciseLocation;
  final Value<bool> shareDistance;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedSearchPrivacySettingsCompanion({
    this.ownerUserId = const Value.absent(),
    this.searchByUsername = const Value.absent(),
    this.searchByPhone = const Value.absent(),
    this.searchByName = const Value.absent(),
    this.lastSeenVisibility = const Value.absent(),
    this.sharePreciseLocation = const Value.absent(),
    this.shareDistance = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedSearchPrivacySettingsCompanion.insert({
    required String ownerUserId,
    required bool searchByUsername,
    required bool searchByPhone,
    required bool searchByName,
    this.lastSeenVisibility = const Value.absent(),
    this.sharePreciseLocation = const Value.absent(),
    this.shareDistance = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       searchByUsername = Value(searchByUsername),
       searchByPhone = Value(searchByPhone),
       searchByName = Value(searchByName),
       cachedAt = Value(cachedAt);
  static Insertable<CachedSearchPrivacySetting> custom({
    Expression<String>? ownerUserId,
    Expression<bool>? searchByUsername,
    Expression<bool>? searchByPhone,
    Expression<bool>? searchByName,
    Expression<String>? lastSeenVisibility,
    Expression<bool>? sharePreciseLocation,
    Expression<bool>? shareDistance,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (searchByUsername != null) 'search_by_username': searchByUsername,
      if (searchByPhone != null) 'search_by_phone': searchByPhone,
      if (searchByName != null) 'search_by_name': searchByName,
      if (lastSeenVisibility != null)
        'last_seen_visibility': lastSeenVisibility,
      if (sharePreciseLocation != null)
        'share_precise_location': sharePreciseLocation,
      if (shareDistance != null) 'share_distance': shareDistance,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedSearchPrivacySettingsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<bool>? searchByUsername,
    Value<bool>? searchByPhone,
    Value<bool>? searchByName,
    Value<String>? lastSeenVisibility,
    Value<bool>? sharePreciseLocation,
    Value<bool>? shareDistance,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedSearchPrivacySettingsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      searchByUsername: searchByUsername ?? this.searchByUsername,
      searchByPhone: searchByPhone ?? this.searchByPhone,
      searchByName: searchByName ?? this.searchByName,
      lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
      sharePreciseLocation: sharePreciseLocation ?? this.sharePreciseLocation,
      shareDistance: shareDistance ?? this.shareDistance,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (searchByUsername.present) {
      map['search_by_username'] = Variable<bool>(searchByUsername.value);
    }
    if (searchByPhone.present) {
      map['search_by_phone'] = Variable<bool>(searchByPhone.value);
    }
    if (searchByName.present) {
      map['search_by_name'] = Variable<bool>(searchByName.value);
    }
    if (lastSeenVisibility.present) {
      map['last_seen_visibility'] = Variable<String>(lastSeenVisibility.value);
    }
    if (sharePreciseLocation.present) {
      map['share_precise_location'] = Variable<bool>(
        sharePreciseLocation.value,
      );
    }
    if (shareDistance.present) {
      map['share_distance'] = Variable<bool>(shareDistance.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedSearchPrivacySettingsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('searchByUsername: $searchByUsername, ')
          ..write('searchByPhone: $searchByPhone, ')
          ..write('searchByName: $searchByName, ')
          ..write('lastSeenVisibility: $lastSeenVisibility, ')
          ..write('sharePreciseLocation: $sharePreciseLocation, ')
          ..write('shareDistance: $shareDistance, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPreciseLocationExclusionsTable
    extends CachedPreciseLocationExclusions
    with
        TableInfo<
          $CachedPreciseLocationExclusionsTable,
          CachedPreciseLocationExclusion
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPreciseLocationExclusionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _viewerUserIdMeta = const VerificationMeta(
    'viewerUserId',
  );
  @override
  late final GeneratedColumn<String> viewerUserId = GeneratedColumn<String>(
    'viewer_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ownerUserId, viewerUserId, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_precise_location_exclusions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPreciseLocationExclusion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('viewer_user_id')) {
      context.handle(
        _viewerUserIdMeta,
        viewerUserId.isAcceptableOrUnknown(
          data['viewer_user_id']!,
          _viewerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_viewerUserIdMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, viewerUserId};
  @override
  CachedPreciseLocationExclusion map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPreciseLocationExclusion(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      viewerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}viewer_user_id'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedPreciseLocationExclusionsTable createAlias(String alias) {
    return $CachedPreciseLocationExclusionsTable(attachedDatabase, alias);
  }
}

class CachedPreciseLocationExclusion extends DataClass
    implements Insertable<CachedPreciseLocationExclusion> {
  final String ownerUserId;
  final String viewerUserId;
  final DateTime cachedAt;
  const CachedPreciseLocationExclusion({
    required this.ownerUserId,
    required this.viewerUserId,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['viewer_user_id'] = Variable<String>(viewerUserId);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedPreciseLocationExclusionsCompanion toCompanion(bool nullToAbsent) {
    return CachedPreciseLocationExclusionsCompanion(
      ownerUserId: Value(ownerUserId),
      viewerUserId: Value(viewerUserId),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedPreciseLocationExclusion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPreciseLocationExclusion(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      viewerUserId: serializer.fromJson<String>(json['viewerUserId']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'viewerUserId': serializer.toJson<String>(viewerUserId),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedPreciseLocationExclusion copyWith({
    String? ownerUserId,
    String? viewerUserId,
    DateTime? cachedAt,
  }) => CachedPreciseLocationExclusion(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    viewerUserId: viewerUserId ?? this.viewerUserId,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedPreciseLocationExclusion copyWithCompanion(
    CachedPreciseLocationExclusionsCompanion data,
  ) {
    return CachedPreciseLocationExclusion(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      viewerUserId: data.viewerUserId.present
          ? data.viewerUserId.value
          : this.viewerUserId,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPreciseLocationExclusion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('viewerUserId: $viewerUserId, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ownerUserId, viewerUserId, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPreciseLocationExclusion &&
          other.ownerUserId == this.ownerUserId &&
          other.viewerUserId == this.viewerUserId &&
          other.cachedAt == this.cachedAt);
}

class CachedPreciseLocationExclusionsCompanion
    extends UpdateCompanion<CachedPreciseLocationExclusion> {
  final Value<String> ownerUserId;
  final Value<String> viewerUserId;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedPreciseLocationExclusionsCompanion({
    this.ownerUserId = const Value.absent(),
    this.viewerUserId = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPreciseLocationExclusionsCompanion.insert({
    required String ownerUserId,
    required String viewerUserId,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       viewerUserId = Value(viewerUserId),
       cachedAt = Value(cachedAt);
  static Insertable<CachedPreciseLocationExclusion> custom({
    Expression<String>? ownerUserId,
    Expression<String>? viewerUserId,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (viewerUserId != null) 'viewer_user_id': viewerUserId,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPreciseLocationExclusionsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? viewerUserId,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedPreciseLocationExclusionsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      viewerUserId: viewerUserId ?? this.viewerUserId,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (viewerUserId.present) {
      map['viewer_user_id'] = Variable<String>(viewerUserId.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPreciseLocationExclusionsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('viewerUserId: $viewerUserId, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedViewedProfileMetadataTable extends CachedViewedProfileMetadata
    with
        TableInfo<
          $CachedViewedProfileMetadataTable,
          CachedViewedProfileMetadataData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedViewedProfileMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetUserIdMeta = const VerificationMeta(
    'targetUserId',
  );
  @override
  late final GeneratedColumn<String> targetUserId = GeneratedColumn<String>(
    'target_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relationshipMeta = const VerificationMeta(
    'relationship',
  );
  @override
  late final GeneratedColumn<String> relationship = GeneratedColumn<String>(
    'relationship',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _friendCountMeta = const VerificationMeta(
    'friendCount',
  );
  @override
  late final GeneratedColumn<int> friendCount = GeneratedColumn<int>(
    'friend_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _friendsPreviewJsonMeta =
      const VerificationMeta('friendsPreviewJson');
  @override
  late final GeneratedColumn<String> friendsPreviewJson =
      GeneratedColumn<String>(
        'friends_preview_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _viewCountMeta = const VerificationMeta(
    'viewCount',
  );
  @override
  late final GeneratedColumn<int> viewCount = GeneratedColumn<int>(
    'view_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _showsLastSeenMeta = const VerificationMeta(
    'showsLastSeen',
  );
  @override
  late final GeneratedColumn<bool> showsLastSeen = GeneratedColumn<bool>(
    'shows_last_seen',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("shows_last_seen" IN (0, 1))',
    ),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    targetUserId,
    relationship,
    requestId,
    friendCount,
    friendsPreviewJson,
    viewCount,
    lastSeenAt,
    showsLastSeen,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_viewed_profile_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedViewedProfileMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('target_user_id')) {
      context.handle(
        _targetUserIdMeta,
        targetUserId.isAcceptableOrUnknown(
          data['target_user_id']!,
          _targetUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetUserIdMeta);
    }
    if (data.containsKey('relationship')) {
      context.handle(
        _relationshipMeta,
        relationship.isAcceptableOrUnknown(
          data['relationship']!,
          _relationshipMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relationshipMeta);
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('friend_count')) {
      context.handle(
        _friendCountMeta,
        friendCount.isAcceptableOrUnknown(
          data['friend_count']!,
          _friendCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_friendCountMeta);
    }
    if (data.containsKey('friends_preview_json')) {
      context.handle(
        _friendsPreviewJsonMeta,
        friendsPreviewJson.isAcceptableOrUnknown(
          data['friends_preview_json']!,
          _friendsPreviewJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_friendsPreviewJsonMeta);
    }
    if (data.containsKey('view_count')) {
      context.handle(
        _viewCountMeta,
        viewCount.isAcceptableOrUnknown(data['view_count']!, _viewCountMeta),
      );
    } else if (isInserting) {
      context.missing(_viewCountMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('shows_last_seen')) {
      context.handle(
        _showsLastSeenMeta,
        showsLastSeen.isAcceptableOrUnknown(
          data['shows_last_seen']!,
          _showsLastSeenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_showsLastSeenMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, targetUserId};
  @override
  CachedViewedProfileMetadataData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedViewedProfileMetadataData(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      targetUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_user_id'],
      )!,
      relationship: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relationship'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      ),
      friendCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}friend_count'],
      )!,
      friendsPreviewJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}friends_preview_json'],
      )!,
      viewCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}view_count'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      ),
      showsLastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}shows_last_seen'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedViewedProfileMetadataTable createAlias(String alias) {
    return $CachedViewedProfileMetadataTable(attachedDatabase, alias);
  }
}

class CachedViewedProfileMetadataData extends DataClass
    implements Insertable<CachedViewedProfileMetadataData> {
  final String ownerUserId;
  final String targetUserId;
  final String relationship;
  final String? requestId;
  final int friendCount;
  final String friendsPreviewJson;
  final int viewCount;
  final DateTime? lastSeenAt;
  final bool showsLastSeen;
  final DateTime cachedAt;
  const CachedViewedProfileMetadataData({
    required this.ownerUserId,
    required this.targetUserId,
    required this.relationship,
    this.requestId,
    required this.friendCount,
    required this.friendsPreviewJson,
    required this.viewCount,
    this.lastSeenAt,
    required this.showsLastSeen,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['target_user_id'] = Variable<String>(targetUserId);
    map['relationship'] = Variable<String>(relationship);
    if (!nullToAbsent || requestId != null) {
      map['request_id'] = Variable<String>(requestId);
    }
    map['friend_count'] = Variable<int>(friendCount);
    map['friends_preview_json'] = Variable<String>(friendsPreviewJson);
    map['view_count'] = Variable<int>(viewCount);
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    map['shows_last_seen'] = Variable<bool>(showsLastSeen);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedViewedProfileMetadataCompanion toCompanion(bool nullToAbsent) {
    return CachedViewedProfileMetadataCompanion(
      ownerUserId: Value(ownerUserId),
      targetUserId: Value(targetUserId),
      relationship: Value(relationship),
      requestId: requestId == null && nullToAbsent
          ? const Value.absent()
          : Value(requestId),
      friendCount: Value(friendCount),
      friendsPreviewJson: Value(friendsPreviewJson),
      viewCount: Value(viewCount),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      showsLastSeen: Value(showsLastSeen),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedViewedProfileMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedViewedProfileMetadataData(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      targetUserId: serializer.fromJson<String>(json['targetUserId']),
      relationship: serializer.fromJson<String>(json['relationship']),
      requestId: serializer.fromJson<String?>(json['requestId']),
      friendCount: serializer.fromJson<int>(json['friendCount']),
      friendsPreviewJson: serializer.fromJson<String>(
        json['friendsPreviewJson'],
      ),
      viewCount: serializer.fromJson<int>(json['viewCount']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      showsLastSeen: serializer.fromJson<bool>(json['showsLastSeen']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'targetUserId': serializer.toJson<String>(targetUserId),
      'relationship': serializer.toJson<String>(relationship),
      'requestId': serializer.toJson<String?>(requestId),
      'friendCount': serializer.toJson<int>(friendCount),
      'friendsPreviewJson': serializer.toJson<String>(friendsPreviewJson),
      'viewCount': serializer.toJson<int>(viewCount),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'showsLastSeen': serializer.toJson<bool>(showsLastSeen),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedViewedProfileMetadataData copyWith({
    String? ownerUserId,
    String? targetUserId,
    String? relationship,
    Value<String?> requestId = const Value.absent(),
    int? friendCount,
    String? friendsPreviewJson,
    int? viewCount,
    Value<DateTime?> lastSeenAt = const Value.absent(),
    bool? showsLastSeen,
    DateTime? cachedAt,
  }) => CachedViewedProfileMetadataData(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    targetUserId: targetUserId ?? this.targetUserId,
    relationship: relationship ?? this.relationship,
    requestId: requestId.present ? requestId.value : this.requestId,
    friendCount: friendCount ?? this.friendCount,
    friendsPreviewJson: friendsPreviewJson ?? this.friendsPreviewJson,
    viewCount: viewCount ?? this.viewCount,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    showsLastSeen: showsLastSeen ?? this.showsLastSeen,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedViewedProfileMetadataData copyWithCompanion(
    CachedViewedProfileMetadataCompanion data,
  ) {
    return CachedViewedProfileMetadataData(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      targetUserId: data.targetUserId.present
          ? data.targetUserId.value
          : this.targetUserId,
      relationship: data.relationship.present
          ? data.relationship.value
          : this.relationship,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      friendCount: data.friendCount.present
          ? data.friendCount.value
          : this.friendCount,
      friendsPreviewJson: data.friendsPreviewJson.present
          ? data.friendsPreviewJson.value
          : this.friendsPreviewJson,
      viewCount: data.viewCount.present ? data.viewCount.value : this.viewCount,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      showsLastSeen: data.showsLastSeen.present
          ? data.showsLastSeen.value
          : this.showsLastSeen,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedViewedProfileMetadataData(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('relationship: $relationship, ')
          ..write('requestId: $requestId, ')
          ..write('friendCount: $friendCount, ')
          ..write('friendsPreviewJson: $friendsPreviewJson, ')
          ..write('viewCount: $viewCount, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('showsLastSeen: $showsLastSeen, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    targetUserId,
    relationship,
    requestId,
    friendCount,
    friendsPreviewJson,
    viewCount,
    lastSeenAt,
    showsLastSeen,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedViewedProfileMetadataData &&
          other.ownerUserId == this.ownerUserId &&
          other.targetUserId == this.targetUserId &&
          other.relationship == this.relationship &&
          other.requestId == this.requestId &&
          other.friendCount == this.friendCount &&
          other.friendsPreviewJson == this.friendsPreviewJson &&
          other.viewCount == this.viewCount &&
          other.lastSeenAt == this.lastSeenAt &&
          other.showsLastSeen == this.showsLastSeen &&
          other.cachedAt == this.cachedAt);
}

class CachedViewedProfileMetadataCompanion
    extends UpdateCompanion<CachedViewedProfileMetadataData> {
  final Value<String> ownerUserId;
  final Value<String> targetUserId;
  final Value<String> relationship;
  final Value<String?> requestId;
  final Value<int> friendCount;
  final Value<String> friendsPreviewJson;
  final Value<int> viewCount;
  final Value<DateTime?> lastSeenAt;
  final Value<bool> showsLastSeen;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedViewedProfileMetadataCompanion({
    this.ownerUserId = const Value.absent(),
    this.targetUserId = const Value.absent(),
    this.relationship = const Value.absent(),
    this.requestId = const Value.absent(),
    this.friendCount = const Value.absent(),
    this.friendsPreviewJson = const Value.absent(),
    this.viewCount = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.showsLastSeen = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedViewedProfileMetadataCompanion.insert({
    required String ownerUserId,
    required String targetUserId,
    required String relationship,
    this.requestId = const Value.absent(),
    required int friendCount,
    required String friendsPreviewJson,
    required int viewCount,
    this.lastSeenAt = const Value.absent(),
    required bool showsLastSeen,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       targetUserId = Value(targetUserId),
       relationship = Value(relationship),
       friendCount = Value(friendCount),
       friendsPreviewJson = Value(friendsPreviewJson),
       viewCount = Value(viewCount),
       showsLastSeen = Value(showsLastSeen),
       cachedAt = Value(cachedAt);
  static Insertable<CachedViewedProfileMetadataData> custom({
    Expression<String>? ownerUserId,
    Expression<String>? targetUserId,
    Expression<String>? relationship,
    Expression<String>? requestId,
    Expression<int>? friendCount,
    Expression<String>? friendsPreviewJson,
    Expression<int>? viewCount,
    Expression<DateTime>? lastSeenAt,
    Expression<bool>? showsLastSeen,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (targetUserId != null) 'target_user_id': targetUserId,
      if (relationship != null) 'relationship': relationship,
      if (requestId != null) 'request_id': requestId,
      if (friendCount != null) 'friend_count': friendCount,
      if (friendsPreviewJson != null)
        'friends_preview_json': friendsPreviewJson,
      if (viewCount != null) 'view_count': viewCount,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (showsLastSeen != null) 'shows_last_seen': showsLastSeen,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedViewedProfileMetadataCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? targetUserId,
    Value<String>? relationship,
    Value<String?>? requestId,
    Value<int>? friendCount,
    Value<String>? friendsPreviewJson,
    Value<int>? viewCount,
    Value<DateTime?>? lastSeenAt,
    Value<bool>? showsLastSeen,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedViewedProfileMetadataCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      targetUserId: targetUserId ?? this.targetUserId,
      relationship: relationship ?? this.relationship,
      requestId: requestId ?? this.requestId,
      friendCount: friendCount ?? this.friendCount,
      friendsPreviewJson: friendsPreviewJson ?? this.friendsPreviewJson,
      viewCount: viewCount ?? this.viewCount,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      showsLastSeen: showsLastSeen ?? this.showsLastSeen,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (targetUserId.present) {
      map['target_user_id'] = Variable<String>(targetUserId.value);
    }
    if (relationship.present) {
      map['relationship'] = Variable<String>(relationship.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (friendCount.present) {
      map['friend_count'] = Variable<int>(friendCount.value);
    }
    if (friendsPreviewJson.present) {
      map['friends_preview_json'] = Variable<String>(friendsPreviewJson.value);
    }
    if (viewCount.present) {
      map['view_count'] = Variable<int>(viewCount.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (showsLastSeen.present) {
      map['shows_last_seen'] = Variable<bool>(showsLastSeen.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedViewedProfileMetadataCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('relationship: $relationship, ')
          ..write('requestId: $requestId, ')
          ..write('friendCount: $friendCount, ')
          ..write('friendsPreviewJson: $friendsPreviewJson, ')
          ..write('viewCount: $viewCount, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('showsLastSeen: $showsLastSeen, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedViewedProfileFriendsTable extends CachedViewedProfileFriends
    with
        TableInfo<$CachedViewedProfileFriendsTable, CachedViewedProfileFriend> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedViewedProfileFriendsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetUserIdMeta = const VerificationMeta(
    'targetUserId',
  );
  @override
  late final GeneratedColumn<String> targetUserId = GeneratedColumn<String>(
    'target_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _friendUserIdMeta = const VerificationMeta(
    'friendUserId',
  );
  @override
  late final GeneratedColumn<String> friendUserId = GeneratedColumn<String>(
    'friend_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarStoragePathMeta = const VerificationMeta(
    'avatarStoragePath',
  );
  @override
  late final GeneratedColumn<String> avatarStoragePath =
      GeneratedColumn<String>(
        'avatar_storage_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    targetUserId,
    friendUserId,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_viewed_profile_friends';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedViewedProfileFriend> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('target_user_id')) {
      context.handle(
        _targetUserIdMeta,
        targetUserId.isAcceptableOrUnknown(
          data['target_user_id']!,
          _targetUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetUserIdMeta);
    }
    if (data.containsKey('friend_user_id')) {
      context.handle(
        _friendUserIdMeta,
        friendUserId.isAcceptableOrUnknown(
          data['friend_user_id']!,
          _friendUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_friendUserIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('avatar_storage_path')) {
      context.handle(
        _avatarStoragePathMeta,
        avatarStoragePath.isAcceptableOrUnknown(
          data['avatar_storage_path']!,
          _avatarStoragePathMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    ownerUserId,
    targetUserId,
    friendUserId,
  };
  @override
  CachedViewedProfileFriend map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedViewedProfileFriend(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      targetUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_user_id'],
      )!,
      friendUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}friend_user_id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      avatarStoragePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_storage_path'],
      ),
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedViewedProfileFriendsTable createAlias(String alias) {
    return $CachedViewedProfileFriendsTable(attachedDatabase, alias);
  }
}

class CachedViewedProfileFriend extends DataClass
    implements Insertable<CachedViewedProfileFriend> {
  final String ownerUserId;
  final String targetUserId;
  final String friendUserId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarStoragePath;
  final DateTime cachedAt;
  const CachedViewedProfileFriend({
    required this.ownerUserId,
    required this.targetUserId,
    required this.friendUserId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.avatarStoragePath,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['target_user_id'] = Variable<String>(targetUserId);
    map['friend_user_id'] = Variable<String>(friendUserId);
    map['username'] = Variable<String>(username);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || avatarStoragePath != null) {
      map['avatar_storage_path'] = Variable<String>(avatarStoragePath);
    }
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedViewedProfileFriendsCompanion toCompanion(bool nullToAbsent) {
    return CachedViewedProfileFriendsCompanion(
      ownerUserId: Value(ownerUserId),
      targetUserId: Value(targetUserId),
      friendUserId: Value(friendUserId),
      username: Value(username),
      displayName: Value(displayName),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      avatarStoragePath: avatarStoragePath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarStoragePath),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedViewedProfileFriend.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedViewedProfileFriend(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      targetUserId: serializer.fromJson<String>(json['targetUserId']),
      friendUserId: serializer.fromJson<String>(json['friendUserId']),
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String>(json['displayName']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      avatarStoragePath: serializer.fromJson<String?>(
        json['avatarStoragePath'],
      ),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'targetUserId': serializer.toJson<String>(targetUserId),
      'friendUserId': serializer.toJson<String>(friendUserId),
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String>(displayName),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'avatarStoragePath': serializer.toJson<String?>(avatarStoragePath),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedViewedProfileFriend copyWith({
    String? ownerUserId,
    String? targetUserId,
    String? friendUserId,
    String? username,
    String? displayName,
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> avatarStoragePath = const Value.absent(),
    DateTime? cachedAt,
  }) => CachedViewedProfileFriend(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    targetUserId: targetUserId ?? this.targetUserId,
    friendUserId: friendUserId ?? this.friendUserId,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    avatarStoragePath: avatarStoragePath.present
        ? avatarStoragePath.value
        : this.avatarStoragePath,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedViewedProfileFriend copyWithCompanion(
    CachedViewedProfileFriendsCompanion data,
  ) {
    return CachedViewedProfileFriend(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      targetUserId: data.targetUserId.present
          ? data.targetUserId.value
          : this.targetUserId,
      friendUserId: data.friendUserId.present
          ? data.friendUserId.value
          : this.friendUserId,
      username: data.username.present ? data.username.value : this.username,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      avatarStoragePath: data.avatarStoragePath.present
          ? data.avatarStoragePath.value
          : this.avatarStoragePath,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedViewedProfileFriend(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('friendUserId: $friendUserId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('avatarStoragePath: $avatarStoragePath, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    targetUserId,
    friendUserId,
    username,
    displayName,
    avatarUrl,
    avatarStoragePath,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedViewedProfileFriend &&
          other.ownerUserId == this.ownerUserId &&
          other.targetUserId == this.targetUserId &&
          other.friendUserId == this.friendUserId &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.avatarUrl == this.avatarUrl &&
          other.avatarStoragePath == this.avatarStoragePath &&
          other.cachedAt == this.cachedAt);
}

class CachedViewedProfileFriendsCompanion
    extends UpdateCompanion<CachedViewedProfileFriend> {
  final Value<String> ownerUserId;
  final Value<String> targetUserId;
  final Value<String> friendUserId;
  final Value<String> username;
  final Value<String> displayName;
  final Value<String?> avatarUrl;
  final Value<String?> avatarStoragePath;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedViewedProfileFriendsCompanion({
    this.ownerUserId = const Value.absent(),
    this.targetUserId = const Value.absent(),
    this.friendUserId = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.avatarStoragePath = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedViewedProfileFriendsCompanion.insert({
    required String ownerUserId,
    required String targetUserId,
    required String friendUserId,
    required String username,
    required String displayName,
    this.avatarUrl = const Value.absent(),
    this.avatarStoragePath = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       targetUserId = Value(targetUserId),
       friendUserId = Value(friendUserId),
       username = Value(username),
       displayName = Value(displayName),
       cachedAt = Value(cachedAt);
  static Insertable<CachedViewedProfileFriend> custom({
    Expression<String>? ownerUserId,
    Expression<String>? targetUserId,
    Expression<String>? friendUserId,
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<String>? avatarUrl,
    Expression<String>? avatarStoragePath,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (targetUserId != null) 'target_user_id': targetUserId,
      if (friendUserId != null) 'friend_user_id': friendUserId,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (avatarStoragePath != null) 'avatar_storage_path': avatarStoragePath,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedViewedProfileFriendsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? targetUserId,
    Value<String>? friendUserId,
    Value<String>? username,
    Value<String>? displayName,
    Value<String?>? avatarUrl,
    Value<String?>? avatarStoragePath,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedViewedProfileFriendsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      targetUserId: targetUserId ?? this.targetUserId,
      friendUserId: friendUserId ?? this.friendUserId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarStoragePath: avatarStoragePath ?? this.avatarStoragePath,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (targetUserId.present) {
      map['target_user_id'] = Variable<String>(targetUserId.value);
    }
    if (friendUserId.present) {
      map['friend_user_id'] = Variable<String>(friendUserId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (avatarStoragePath.present) {
      map['avatar_storage_path'] = Variable<String>(avatarStoragePath.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedViewedProfileFriendsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('friendUserId: $friendUserId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('avatarStoragePath: $avatarStoragePath, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedViewedProfileFriendListsTable
    extends CachedViewedProfileFriendLists
    with
        TableInfo<
          $CachedViewedProfileFriendListsTable,
          CachedViewedProfileFriendList
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedViewedProfileFriendListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetUserIdMeta = const VerificationMeta(
    'targetUserId',
  );
  @override
  late final GeneratedColumn<String> targetUserId = GeneratedColumn<String>(
    'target_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ownerUserId, targetUserId, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_viewed_profile_friend_lists';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedViewedProfileFriendList> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('target_user_id')) {
      context.handle(
        _targetUserIdMeta,
        targetUserId.isAcceptableOrUnknown(
          data['target_user_id']!,
          _targetUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetUserIdMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, targetUserId};
  @override
  CachedViewedProfileFriendList map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedViewedProfileFriendList(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      targetUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_user_id'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedViewedProfileFriendListsTable createAlias(String alias) {
    return $CachedViewedProfileFriendListsTable(attachedDatabase, alias);
  }
}

class CachedViewedProfileFriendList extends DataClass
    implements Insertable<CachedViewedProfileFriendList> {
  final String ownerUserId;
  final String targetUserId;
  final DateTime cachedAt;
  const CachedViewedProfileFriendList({
    required this.ownerUserId,
    required this.targetUserId,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['target_user_id'] = Variable<String>(targetUserId);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedViewedProfileFriendListsCompanion toCompanion(bool nullToAbsent) {
    return CachedViewedProfileFriendListsCompanion(
      ownerUserId: Value(ownerUserId),
      targetUserId: Value(targetUserId),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedViewedProfileFriendList.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedViewedProfileFriendList(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      targetUserId: serializer.fromJson<String>(json['targetUserId']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'targetUserId': serializer.toJson<String>(targetUserId),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedViewedProfileFriendList copyWith({
    String? ownerUserId,
    String? targetUserId,
    DateTime? cachedAt,
  }) => CachedViewedProfileFriendList(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    targetUserId: targetUserId ?? this.targetUserId,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedViewedProfileFriendList copyWithCompanion(
    CachedViewedProfileFriendListsCompanion data,
  ) {
    return CachedViewedProfileFriendList(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      targetUserId: data.targetUserId.present
          ? data.targetUserId.value
          : this.targetUserId,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedViewedProfileFriendList(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ownerUserId, targetUserId, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedViewedProfileFriendList &&
          other.ownerUserId == this.ownerUserId &&
          other.targetUserId == this.targetUserId &&
          other.cachedAt == this.cachedAt);
}

class CachedViewedProfileFriendListsCompanion
    extends UpdateCompanion<CachedViewedProfileFriendList> {
  final Value<String> ownerUserId;
  final Value<String> targetUserId;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedViewedProfileFriendListsCompanion({
    this.ownerUserId = const Value.absent(),
    this.targetUserId = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedViewedProfileFriendListsCompanion.insert({
    required String ownerUserId,
    required String targetUserId,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       targetUserId = Value(targetUserId),
       cachedAt = Value(cachedAt);
  static Insertable<CachedViewedProfileFriendList> custom({
    Expression<String>? ownerUserId,
    Expression<String>? targetUserId,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (targetUserId != null) 'target_user_id': targetUserId,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedViewedProfileFriendListsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? targetUserId,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedViewedProfileFriendListsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      targetUserId: targetUserId ?? this.targetUserId,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (targetUserId.present) {
      map['target_user_id'] = Variable<String>(targetUserId.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedViewedProfileFriendListsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedUserDistancesTable extends CachedUserDistances
    with TableInfo<$CachedUserDistancesTable, CachedUserDistance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedUserDistancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetUserIdMeta = const VerificationMeta(
    'targetUserId',
  );
  @override
  late final GeneratedColumn<String> targetUserId = GeneratedColumn<String>(
    'target_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceValueMeta = const VerificationMeta(
    'distanceValue',
  );
  @override
  late final GeneratedColumn<int> distanceValue = GeneratedColumn<int>(
    'distance_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceUnitMeta = const VerificationMeta(
    'distanceUnit',
  );
  @override
  late final GeneratedColumn<String> distanceUnit = GeneratedColumn<String>(
    'distance_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationUpdatedAtMeta = const VerificationMeta(
    'locationUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> locationUpdatedAt =
      GeneratedColumn<DateTime>(
        'location_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    targetUserId,
    distanceValue,
    distanceUnit,
    locationUpdatedAt,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_user_distances';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedUserDistance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('target_user_id')) {
      context.handle(
        _targetUserIdMeta,
        targetUserId.isAcceptableOrUnknown(
          data['target_user_id']!,
          _targetUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetUserIdMeta);
    }
    if (data.containsKey('distance_value')) {
      context.handle(
        _distanceValueMeta,
        distanceValue.isAcceptableOrUnknown(
          data['distance_value']!,
          _distanceValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_distanceValueMeta);
    }
    if (data.containsKey('distance_unit')) {
      context.handle(
        _distanceUnitMeta,
        distanceUnit.isAcceptableOrUnknown(
          data['distance_unit']!,
          _distanceUnitMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_distanceUnitMeta);
    }
    if (data.containsKey('location_updated_at')) {
      context.handle(
        _locationUpdatedAtMeta,
        locationUpdatedAt.isAcceptableOrUnknown(
          data['location_updated_at']!,
          _locationUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationUpdatedAtMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, targetUserId};
  @override
  CachedUserDistance map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedUserDistance(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      targetUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_user_id'],
      )!,
      distanceValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distance_value'],
      )!,
      distanceUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}distance_unit'],
      )!,
      locationUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}location_updated_at'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedUserDistancesTable createAlias(String alias) {
    return $CachedUserDistancesTable(attachedDatabase, alias);
  }
}

class CachedUserDistance extends DataClass
    implements Insertable<CachedUserDistance> {
  final String ownerUserId;
  final String targetUserId;
  final int distanceValue;
  final String distanceUnit;
  final DateTime locationUpdatedAt;
  final DateTime cachedAt;
  const CachedUserDistance({
    required this.ownerUserId,
    required this.targetUserId,
    required this.distanceValue,
    required this.distanceUnit,
    required this.locationUpdatedAt,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['target_user_id'] = Variable<String>(targetUserId);
    map['distance_value'] = Variable<int>(distanceValue);
    map['distance_unit'] = Variable<String>(distanceUnit);
    map['location_updated_at'] = Variable<DateTime>(locationUpdatedAt);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedUserDistancesCompanion toCompanion(bool nullToAbsent) {
    return CachedUserDistancesCompanion(
      ownerUserId: Value(ownerUserId),
      targetUserId: Value(targetUserId),
      distanceValue: Value(distanceValue),
      distanceUnit: Value(distanceUnit),
      locationUpdatedAt: Value(locationUpdatedAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedUserDistance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedUserDistance(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      targetUserId: serializer.fromJson<String>(json['targetUserId']),
      distanceValue: serializer.fromJson<int>(json['distanceValue']),
      distanceUnit: serializer.fromJson<String>(json['distanceUnit']),
      locationUpdatedAt: serializer.fromJson<DateTime>(
        json['locationUpdatedAt'],
      ),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'targetUserId': serializer.toJson<String>(targetUserId),
      'distanceValue': serializer.toJson<int>(distanceValue),
      'distanceUnit': serializer.toJson<String>(distanceUnit),
      'locationUpdatedAt': serializer.toJson<DateTime>(locationUpdatedAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedUserDistance copyWith({
    String? ownerUserId,
    String? targetUserId,
    int? distanceValue,
    String? distanceUnit,
    DateTime? locationUpdatedAt,
    DateTime? cachedAt,
  }) => CachedUserDistance(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    targetUserId: targetUserId ?? this.targetUserId,
    distanceValue: distanceValue ?? this.distanceValue,
    distanceUnit: distanceUnit ?? this.distanceUnit,
    locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedUserDistance copyWithCompanion(CachedUserDistancesCompanion data) {
    return CachedUserDistance(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      targetUserId: data.targetUserId.present
          ? data.targetUserId.value
          : this.targetUserId,
      distanceValue: data.distanceValue.present
          ? data.distanceValue.value
          : this.distanceValue,
      distanceUnit: data.distanceUnit.present
          ? data.distanceUnit.value
          : this.distanceUnit,
      locationUpdatedAt: data.locationUpdatedAt.present
          ? data.locationUpdatedAt.value
          : this.locationUpdatedAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedUserDistance(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('distanceValue: $distanceValue, ')
          ..write('distanceUnit: $distanceUnit, ')
          ..write('locationUpdatedAt: $locationUpdatedAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerUserId,
    targetUserId,
    distanceValue,
    distanceUnit,
    locationUpdatedAt,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedUserDistance &&
          other.ownerUserId == this.ownerUserId &&
          other.targetUserId == this.targetUserId &&
          other.distanceValue == this.distanceValue &&
          other.distanceUnit == this.distanceUnit &&
          other.locationUpdatedAt == this.locationUpdatedAt &&
          other.cachedAt == this.cachedAt);
}

class CachedUserDistancesCompanion extends UpdateCompanion<CachedUserDistance> {
  final Value<String> ownerUserId;
  final Value<String> targetUserId;
  final Value<int> distanceValue;
  final Value<String> distanceUnit;
  final Value<DateTime> locationUpdatedAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedUserDistancesCompanion({
    this.ownerUserId = const Value.absent(),
    this.targetUserId = const Value.absent(),
    this.distanceValue = const Value.absent(),
    this.distanceUnit = const Value.absent(),
    this.locationUpdatedAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedUserDistancesCompanion.insert({
    required String ownerUserId,
    required String targetUserId,
    required int distanceValue,
    required String distanceUnit,
    required DateTime locationUpdatedAt,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       targetUserId = Value(targetUserId),
       distanceValue = Value(distanceValue),
       distanceUnit = Value(distanceUnit),
       locationUpdatedAt = Value(locationUpdatedAt),
       cachedAt = Value(cachedAt);
  static Insertable<CachedUserDistance> custom({
    Expression<String>? ownerUserId,
    Expression<String>? targetUserId,
    Expression<int>? distanceValue,
    Expression<String>? distanceUnit,
    Expression<DateTime>? locationUpdatedAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (targetUserId != null) 'target_user_id': targetUserId,
      if (distanceValue != null) 'distance_value': distanceValue,
      if (distanceUnit != null) 'distance_unit': distanceUnit,
      if (locationUpdatedAt != null) 'location_updated_at': locationUpdatedAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedUserDistancesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? targetUserId,
    Value<int>? distanceValue,
    Value<String>? distanceUnit,
    Value<DateTime>? locationUpdatedAt,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedUserDistancesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      targetUserId: targetUserId ?? this.targetUserId,
      distanceValue: distanceValue ?? this.distanceValue,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (targetUserId.present) {
      map['target_user_id'] = Variable<String>(targetUserId.value);
    }
    if (distanceValue.present) {
      map['distance_value'] = Variable<int>(distanceValue.value);
    }
    if (distanceUnit.present) {
      map['distance_unit'] = Variable<String>(distanceUnit.value);
    }
    if (locationUpdatedAt.present) {
      map['location_updated_at'] = Variable<DateTime>(locationUpdatedAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedUserDistancesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('distanceValue: $distanceValue, ')
          ..write('distanceUnit: $distanceUnit, ')
          ..write('locationUpdatedAt: $locationUpdatedAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedProfileViewCountsTable extends CachedProfileViewCounts
    with TableInfo<$CachedProfileViewCountsTable, CachedProfileViewCount> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProfileViewCountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetUserIdMeta = const VerificationMeta(
    'targetUserId',
  );
  @override
  late final GeneratedColumn<String> targetUserId = GeneratedColumn<String>(
    'target_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _viewCountMeta = const VerificationMeta(
    'viewCount',
  );
  @override
  late final GeneratedColumn<int> viewCount = GeneratedColumn<int>(
    'view_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerUserId,
    targetUserId,
    viewCount,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_profile_view_counts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProfileViewCount> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('target_user_id')) {
      context.handle(
        _targetUserIdMeta,
        targetUserId.isAcceptableOrUnknown(
          data['target_user_id']!,
          _targetUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetUserIdMeta);
    }
    if (data.containsKey('view_count')) {
      context.handle(
        _viewCountMeta,
        viewCount.isAcceptableOrUnknown(data['view_count']!, _viewCountMeta),
      );
    } else if (isInserting) {
      context.missing(_viewCountMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId, targetUserId};
  @override
  CachedProfileViewCount map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProfileViewCount(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      targetUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_user_id'],
      )!,
      viewCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}view_count'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedProfileViewCountsTable createAlias(String alias) {
    return $CachedProfileViewCountsTable(attachedDatabase, alias);
  }
}

class CachedProfileViewCount extends DataClass
    implements Insertable<CachedProfileViewCount> {
  final String ownerUserId;
  final String targetUserId;
  final int viewCount;
  final DateTime cachedAt;
  const CachedProfileViewCount({
    required this.ownerUserId,
    required this.targetUserId,
    required this.viewCount,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['target_user_id'] = Variable<String>(targetUserId);
    map['view_count'] = Variable<int>(viewCount);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedProfileViewCountsCompanion toCompanion(bool nullToAbsent) {
    return CachedProfileViewCountsCompanion(
      ownerUserId: Value(ownerUserId),
      targetUserId: Value(targetUserId),
      viewCount: Value(viewCount),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedProfileViewCount.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProfileViewCount(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      targetUserId: serializer.fromJson<String>(json['targetUserId']),
      viewCount: serializer.fromJson<int>(json['viewCount']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'targetUserId': serializer.toJson<String>(targetUserId),
      'viewCount': serializer.toJson<int>(viewCount),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedProfileViewCount copyWith({
    String? ownerUserId,
    String? targetUserId,
    int? viewCount,
    DateTime? cachedAt,
  }) => CachedProfileViewCount(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    targetUserId: targetUserId ?? this.targetUserId,
    viewCount: viewCount ?? this.viewCount,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedProfileViewCount copyWithCompanion(
    CachedProfileViewCountsCompanion data,
  ) {
    return CachedProfileViewCount(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      targetUserId: data.targetUserId.present
          ? data.targetUserId.value
          : this.targetUserId,
      viewCount: data.viewCount.present ? data.viewCount.value : this.viewCount,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfileViewCount(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('viewCount: $viewCount, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(ownerUserId, targetUserId, viewCount, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProfileViewCount &&
          other.ownerUserId == this.ownerUserId &&
          other.targetUserId == this.targetUserId &&
          other.viewCount == this.viewCount &&
          other.cachedAt == this.cachedAt);
}

class CachedProfileViewCountsCompanion
    extends UpdateCompanion<CachedProfileViewCount> {
  final Value<String> ownerUserId;
  final Value<String> targetUserId;
  final Value<int> viewCount;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedProfileViewCountsCompanion({
    this.ownerUserId = const Value.absent(),
    this.targetUserId = const Value.absent(),
    this.viewCount = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProfileViewCountsCompanion.insert({
    required String ownerUserId,
    required String targetUserId,
    required int viewCount,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       targetUserId = Value(targetUserId),
       viewCount = Value(viewCount),
       cachedAt = Value(cachedAt);
  static Insertable<CachedProfileViewCount> custom({
    Expression<String>? ownerUserId,
    Expression<String>? targetUserId,
    Expression<int>? viewCount,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (targetUserId != null) 'target_user_id': targetUserId,
      if (viewCount != null) 'view_count': viewCount,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProfileViewCountsCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? targetUserId,
    Value<int>? viewCount,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedProfileViewCountsCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      targetUserId: targetUserId ?? this.targetUserId,
      viewCount: viewCount ?? this.viewCount,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (targetUserId.present) {
      map['target_user_id'] = Variable<String>(targetUserId.value);
    }
    if (viewCount.present) {
      map['view_count'] = Variable<int>(viewCount.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfileViewCountsCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('viewCount: $viewCount, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedAppLanguagesTable extends CachedAppLanguages
    with TableInfo<$CachedAppLanguagesTable, CachedAppLanguage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedAppLanguagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageCodeMeta = const VerificationMeta(
    'languageCode',
  );
  @override
  late final GeneratedColumn<String> languageCode = GeneratedColumn<String>(
    'language_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [ownerUserId, languageCode, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_app_languages';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedAppLanguage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('language_code')) {
      context.handle(
        _languageCodeMeta,
        languageCode.isAcceptableOrUnknown(
          data['language_code']!,
          _languageCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_languageCodeMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerUserId};
  @override
  CachedAppLanguage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedAppLanguage(
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      languageCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language_code'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedAppLanguagesTable createAlias(String alias) {
    return $CachedAppLanguagesTable(attachedDatabase, alias);
  }
}

class CachedAppLanguage extends DataClass
    implements Insertable<CachedAppLanguage> {
  final String ownerUserId;
  final String languageCode;
  final DateTime cachedAt;
  const CachedAppLanguage({
    required this.ownerUserId,
    required this.languageCode,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['language_code'] = Variable<String>(languageCode);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedAppLanguagesCompanion toCompanion(bool nullToAbsent) {
    return CachedAppLanguagesCompanion(
      ownerUserId: Value(ownerUserId),
      languageCode: Value(languageCode),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedAppLanguage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedAppLanguage(
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      languageCode: serializer.fromJson<String>(json['languageCode']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'languageCode': serializer.toJson<String>(languageCode),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedAppLanguage copyWith({
    String? ownerUserId,
    String? languageCode,
    DateTime? cachedAt,
  }) => CachedAppLanguage(
    ownerUserId: ownerUserId ?? this.ownerUserId,
    languageCode: languageCode ?? this.languageCode,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedAppLanguage copyWithCompanion(CachedAppLanguagesCompanion data) {
    return CachedAppLanguage(
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      languageCode: data.languageCode.present
          ? data.languageCode.value
          : this.languageCode,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedAppLanguage(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('languageCode: $languageCode, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ownerUserId, languageCode, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedAppLanguage &&
          other.ownerUserId == this.ownerUserId &&
          other.languageCode == this.languageCode &&
          other.cachedAt == this.cachedAt);
}

class CachedAppLanguagesCompanion extends UpdateCompanion<CachedAppLanguage> {
  final Value<String> ownerUserId;
  final Value<String> languageCode;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedAppLanguagesCompanion({
    this.ownerUserId = const Value.absent(),
    this.languageCode = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedAppLanguagesCompanion.insert({
    required String ownerUserId,
    required String languageCode,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : ownerUserId = Value(ownerUserId),
       languageCode = Value(languageCode),
       cachedAt = Value(cachedAt);
  static Insertable<CachedAppLanguage> custom({
    Expression<String>? ownerUserId,
    Expression<String>? languageCode,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (languageCode != null) 'language_code': languageCode,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedAppLanguagesCompanion copyWith({
    Value<String>? ownerUserId,
    Value<String>? languageCode,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedAppLanguagesCompanion(
      ownerUserId: ownerUserId ?? this.ownerUserId,
      languageCode: languageCode ?? this.languageCode,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (languageCode.present) {
      map['language_code'] = Variable<String>(languageCode.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedAppLanguagesCompanion(')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('languageCode: $languageCode, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedProfilesTable cachedProfiles = $CachedProfilesTable(this);
  late final $CachedProfilePhotosTable cachedProfilePhotos =
      $CachedProfilePhotosTable(this);
  late final $CachedChatsTable cachedChats = $CachedChatsTable(this);
  late final $CachedMessagesTable cachedMessages = $CachedMessagesTable(this);
  late final $PendingChatOperationsTable pendingChatOperations =
      $PendingChatOperationsTable(this);
  late final $CachedFriendsTable cachedFriends = $CachedFriendsTable(this);
  late final $CachedFriendRequestsTable cachedFriendRequests =
      $CachedFriendRequestsTable(this);
  late final $CachedFriendLocationsTable cachedFriendLocations =
      $CachedFriendLocationsTable(this);
  late final $CachedContactMatchesTable cachedContactMatches =
      $CachedContactMatchesTable(this);
  late final $CachedSearchPrivacySettingsTable cachedSearchPrivacySettings =
      $CachedSearchPrivacySettingsTable(this);
  late final $CachedPreciseLocationExclusionsTable
  cachedPreciseLocationExclusions = $CachedPreciseLocationExclusionsTable(this);
  late final $CachedViewedProfileMetadataTable cachedViewedProfileMetadata =
      $CachedViewedProfileMetadataTable(this);
  late final $CachedViewedProfileFriendsTable cachedViewedProfileFriends =
      $CachedViewedProfileFriendsTable(this);
  late final $CachedViewedProfileFriendListsTable
  cachedViewedProfileFriendLists = $CachedViewedProfileFriendListsTable(this);
  late final $CachedUserDistancesTable cachedUserDistances =
      $CachedUserDistancesTable(this);
  late final $CachedProfileViewCountsTable cachedProfileViewCounts =
      $CachedProfileViewCountsTable(this);
  late final $CachedAppLanguagesTable cachedAppLanguages =
      $CachedAppLanguagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedProfiles,
    cachedProfilePhotos,
    cachedChats,
    cachedMessages,
    pendingChatOperations,
    cachedFriends,
    cachedFriendRequests,
    cachedFriendLocations,
    cachedContactMatches,
    cachedSearchPrivacySettings,
    cachedPreciseLocationExclusions,
    cachedViewedProfileMetadata,
    cachedViewedProfileFriends,
    cachedViewedProfileFriendLists,
    cachedUserDistances,
    cachedProfileViewCounts,
    cachedAppLanguages,
  ];
}

typedef $$CachedProfilesTableCreateCompanionBuilder =
    CachedProfilesCompanion Function({
      required String userId,
      required String username,
      required String displayName,
      Value<DateTime?> birthDate,
      Value<String?> avatarUrl,
      Value<String?> avatarStoragePath,
      Value<Uint8List?> avatarBytes,
      Value<DateTime?> avatarUpdatedAt,
      Value<bool> yandexAvatarDisabled,
      required String gender,
      required String bio,
      required bool onboardingCompleted,
      Value<DateTime?> termsAcceptedAt,
      Value<DateTime?> privacyAcceptedAt,
      Value<DateTime?> createdAt,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedProfilesTableUpdateCompanionBuilder =
    CachedProfilesCompanion Function({
      Value<String> userId,
      Value<String> username,
      Value<String> displayName,
      Value<DateTime?> birthDate,
      Value<String?> avatarUrl,
      Value<String?> avatarStoragePath,
      Value<Uint8List?> avatarBytes,
      Value<DateTime?> avatarUpdatedAt,
      Value<bool> yandexAvatarDisabled,
      Value<String> gender,
      Value<String> bio,
      Value<bool> onboardingCompleted,
      Value<DateTime?> termsAcceptedAt,
      Value<DateTime?> privacyAcceptedAt,
      Value<DateTime?> createdAt,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get avatarBytes => $composableBuilder(
    column: $table.avatarBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get avatarUpdatedAt => $composableBuilder(
    column: $table.avatarUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get yandexAvatarDisabled => $composableBuilder(
    column: $table.yandexAvatarDisabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bio => $composableBuilder(
    column: $table.bio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get onboardingCompleted => $composableBuilder(
    column: $table.onboardingCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get termsAcceptedAt => $composableBuilder(
    column: $table.termsAcceptedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get privacyAcceptedAt => $composableBuilder(
    column: $table.privacyAcceptedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get avatarBytes => $composableBuilder(
    column: $table.avatarBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get avatarUpdatedAt => $composableBuilder(
    column: $table.avatarUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get yandexAvatarDisabled => $composableBuilder(
    column: $table.yandexAvatarDisabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bio => $composableBuilder(
    column: $table.bio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get onboardingCompleted => $composableBuilder(
    column: $table.onboardingCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get termsAcceptedAt => $composableBuilder(
    column: $table.termsAcceptedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get privacyAcceptedAt => $composableBuilder(
    column: $table.privacyAcceptedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get birthDate =>
      $composableBuilder(column: $table.birthDate, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get avatarBytes => $composableBuilder(
    column: $table.avatarBytes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get avatarUpdatedAt => $composableBuilder(
    column: $table.avatarUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get yandexAvatarDisabled => $composableBuilder(
    column: $table.yandexAvatarDisabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<String> get bio =>
      $composableBuilder(column: $table.bio, builder: (column) => column);

  GeneratedColumn<bool> get onboardingCompleted => $composableBuilder(
    column: $table.onboardingCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get termsAcceptedAt => $composableBuilder(
    column: $table.termsAcceptedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get privacyAcceptedAt => $composableBuilder(
    column: $table.privacyAcceptedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedProfilesTable,
          CachedProfile,
          $$CachedProfilesTableFilterComposer,
          $$CachedProfilesTableOrderingComposer,
          $$CachedProfilesTableAnnotationComposer,
          $$CachedProfilesTableCreateCompanionBuilder,
          $$CachedProfilesTableUpdateCompanionBuilder,
          (
            CachedProfile,
            BaseReferences<_$AppDatabase, $CachedProfilesTable, CachedProfile>,
          ),
          CachedProfile,
          PrefetchHooks Function()
        > {
  $$CachedProfilesTableTableManager(
    _$AppDatabase db,
    $CachedProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> avatarStoragePath = const Value.absent(),
                Value<Uint8List?> avatarBytes = const Value.absent(),
                Value<DateTime?> avatarUpdatedAt = const Value.absent(),
                Value<bool> yandexAvatarDisabled = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String> bio = const Value.absent(),
                Value<bool> onboardingCompleted = const Value.absent(),
                Value<DateTime?> termsAcceptedAt = const Value.absent(),
                Value<DateTime?> privacyAcceptedAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion(
                userId: userId,
                username: username,
                displayName: displayName,
                birthDate: birthDate,
                avatarUrl: avatarUrl,
                avatarStoragePath: avatarStoragePath,
                avatarBytes: avatarBytes,
                avatarUpdatedAt: avatarUpdatedAt,
                yandexAvatarDisabled: yandexAvatarDisabled,
                gender: gender,
                bio: bio,
                onboardingCompleted: onboardingCompleted,
                termsAcceptedAt: termsAcceptedAt,
                privacyAcceptedAt: privacyAcceptedAt,
                createdAt: createdAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String username,
                required String displayName,
                Value<DateTime?> birthDate = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> avatarStoragePath = const Value.absent(),
                Value<Uint8List?> avatarBytes = const Value.absent(),
                Value<DateTime?> avatarUpdatedAt = const Value.absent(),
                Value<bool> yandexAvatarDisabled = const Value.absent(),
                required String gender,
                required String bio,
                required bool onboardingCompleted,
                Value<DateTime?> termsAcceptedAt = const Value.absent(),
                Value<DateTime?> privacyAcceptedAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion.insert(
                userId: userId,
                username: username,
                displayName: displayName,
                birthDate: birthDate,
                avatarUrl: avatarUrl,
                avatarStoragePath: avatarStoragePath,
                avatarBytes: avatarBytes,
                avatarUpdatedAt: avatarUpdatedAt,
                yandexAvatarDisabled: yandexAvatarDisabled,
                gender: gender,
                bio: bio,
                onboardingCompleted: onboardingCompleted,
                termsAcceptedAt: termsAcceptedAt,
                privacyAcceptedAt: privacyAcceptedAt,
                createdAt: createdAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedProfilesTable,
      CachedProfile,
      $$CachedProfilesTableFilterComposer,
      $$CachedProfilesTableOrderingComposer,
      $$CachedProfilesTableAnnotationComposer,
      $$CachedProfilesTableCreateCompanionBuilder,
      $$CachedProfilesTableUpdateCompanionBuilder,
      (
        CachedProfile,
        BaseReferences<_$AppDatabase, $CachedProfilesTable, CachedProfile>,
      ),
      CachedProfile,
      PrefetchHooks Function()
    >;
typedef $$CachedProfilePhotosTableCreateCompanionBuilder =
    CachedProfilePhotosCompanion Function({
      required String userId,
      required int position,
      Value<String?> avatarUrl,
      Value<String?> storagePath,
      Value<Uint8List?> bytes,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$CachedProfilePhotosTableUpdateCompanionBuilder =
    CachedProfilePhotosCompanion Function({
      Value<String> userId,
      Value<int> position,
      Value<String?> avatarUrl,
      Value<String?> storagePath,
      Value<Uint8List?> bytes,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$CachedProfilePhotosTableFilterComposer
    extends Composer<_$AppDatabase, $CachedProfilePhotosTable> {
  $$CachedProfilePhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProfilePhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedProfilePhotosTable> {
  $$CachedProfilePhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProfilePhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedProfilePhotosTable> {
  $$CachedProfilePhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedProfilePhotosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedProfilePhotosTable,
          CachedProfilePhoto,
          $$CachedProfilePhotosTableFilterComposer,
          $$CachedProfilePhotosTableOrderingComposer,
          $$CachedProfilePhotosTableAnnotationComposer,
          $$CachedProfilePhotosTableCreateCompanionBuilder,
          $$CachedProfilePhotosTableUpdateCompanionBuilder,
          (
            CachedProfilePhoto,
            BaseReferences<
              _$AppDatabase,
              $CachedProfilePhotosTable,
              CachedProfilePhoto
            >,
          ),
          CachedProfilePhoto,
          PrefetchHooks Function()
        > {
  $$CachedProfilePhotosTableTableManager(
    _$AppDatabase db,
    $CachedProfilePhotosTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProfilePhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProfilePhotosTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedProfilePhotosTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> storagePath = const Value.absent(),
                Value<Uint8List?> bytes = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilePhotosCompanion(
                userId: userId,
                position: position,
                avatarUrl: avatarUrl,
                storagePath: storagePath,
                bytes: bytes,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required int position,
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> storagePath = const Value.absent(),
                Value<Uint8List?> bytes = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilePhotosCompanion.insert(
                userId: userId,
                position: position,
                avatarUrl: avatarUrl,
                storagePath: storagePath,
                bytes: bytes,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProfilePhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedProfilePhotosTable,
      CachedProfilePhoto,
      $$CachedProfilePhotosTableFilterComposer,
      $$CachedProfilePhotosTableOrderingComposer,
      $$CachedProfilePhotosTableAnnotationComposer,
      $$CachedProfilePhotosTableCreateCompanionBuilder,
      $$CachedProfilePhotosTableUpdateCompanionBuilder,
      (
        CachedProfilePhoto,
        BaseReferences<
          _$AppDatabase,
          $CachedProfilePhotosTable,
          CachedProfilePhoto
        >,
      ),
      CachedProfilePhoto,
      PrefetchHooks Function()
    >;
typedef $$CachedChatsTableCreateCompanionBuilder =
    CachedChatsCompanion Function({
      required String ownerUserId,
      required String id,
      required String peerId,
      required String peerUsername,
      required String peerDisplayName,
      Value<String?> peerAvatarUrl,
      Value<String?> peerAvatarStoragePath,
      Value<String?> lastMessageId,
      required String lastMessage,
      required String lastMessageType,
      required DateTime lastMessageTime,
      required int unreadCount,
      required bool isLastMessageFromMe,
      required bool isMuted,
      Value<DateTime?> lastSeenAt,
      Value<bool> showsLastSeen,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedChatsTableUpdateCompanionBuilder =
    CachedChatsCompanion Function({
      Value<String> ownerUserId,
      Value<String> id,
      Value<String> peerId,
      Value<String> peerUsername,
      Value<String> peerDisplayName,
      Value<String?> peerAvatarUrl,
      Value<String?> peerAvatarStoragePath,
      Value<String?> lastMessageId,
      Value<String> lastMessage,
      Value<String> lastMessageType,
      Value<DateTime> lastMessageTime,
      Value<int> unreadCount,
      Value<bool> isLastMessageFromMe,
      Value<bool> isMuted,
      Value<DateTime?> lastSeenAt,
      Value<bool> showsLastSeen,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedChatsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedChatsTable> {
  $$CachedChatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerUsername => $composableBuilder(
    column: $table.peerUsername,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerAvatarUrl => $composableBuilder(
    column: $table.peerAvatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerAvatarStoragePath => $composableBuilder(
    column: $table.peerAvatarStoragePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageType => $composableBuilder(
    column: $table.lastMessageType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLastMessageFromMe => $composableBuilder(
    column: $table.isLastMessageFromMe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showsLastSeen => $composableBuilder(
    column: $table.showsLastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedChatsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedChatsTable> {
  $$CachedChatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerUsername => $composableBuilder(
    column: $table.peerUsername,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerAvatarUrl => $composableBuilder(
    column: $table.peerAvatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerAvatarStoragePath => $composableBuilder(
    column: $table.peerAvatarStoragePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageType => $composableBuilder(
    column: $table.lastMessageType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLastMessageFromMe => $composableBuilder(
    column: $table.isLastMessageFromMe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showsLastSeen => $composableBuilder(
    column: $table.showsLastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedChatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedChatsTable> {
  $$CachedChatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get peerUsername => $composableBuilder(
    column: $table.peerUsername,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerAvatarUrl => $composableBuilder(
    column: $table.peerAvatarUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerAvatarStoragePath => $composableBuilder(
    column: $table.peerAvatarStoragePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessage => $composableBuilder(
    column: $table.lastMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageType => $composableBuilder(
    column: $table.lastMessageType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isLastMessageFromMe => $composableBuilder(
    column: $table.isLastMessageFromMe,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isMuted =>
      $composableBuilder(column: $table.isMuted, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get showsLastSeen => $composableBuilder(
    column: $table.showsLastSeen,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedChatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedChatsTable,
          CachedChat,
          $$CachedChatsTableFilterComposer,
          $$CachedChatsTableOrderingComposer,
          $$CachedChatsTableAnnotationComposer,
          $$CachedChatsTableCreateCompanionBuilder,
          $$CachedChatsTableUpdateCompanionBuilder,
          (
            CachedChat,
            BaseReferences<_$AppDatabase, $CachedChatsTable, CachedChat>,
          ),
          CachedChat,
          PrefetchHooks Function()
        > {
  $$CachedChatsTableTableManager(_$AppDatabase db, $CachedChatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedChatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedChatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedChatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String> peerUsername = const Value.absent(),
                Value<String> peerDisplayName = const Value.absent(),
                Value<String?> peerAvatarUrl = const Value.absent(),
                Value<String?> peerAvatarStoragePath = const Value.absent(),
                Value<String?> lastMessageId = const Value.absent(),
                Value<String> lastMessage = const Value.absent(),
                Value<String> lastMessageType = const Value.absent(),
                Value<DateTime> lastMessageTime = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<bool> isLastMessageFromMe = const Value.absent(),
                Value<bool> isMuted = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<bool> showsLastSeen = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedChatsCompanion(
                ownerUserId: ownerUserId,
                id: id,
                peerId: peerId,
                peerUsername: peerUsername,
                peerDisplayName: peerDisplayName,
                peerAvatarUrl: peerAvatarUrl,
                peerAvatarStoragePath: peerAvatarStoragePath,
                lastMessageId: lastMessageId,
                lastMessage: lastMessage,
                lastMessageType: lastMessageType,
                lastMessageTime: lastMessageTime,
                unreadCount: unreadCount,
                isLastMessageFromMe: isLastMessageFromMe,
                isMuted: isMuted,
                lastSeenAt: lastSeenAt,
                showsLastSeen: showsLastSeen,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String id,
                required String peerId,
                required String peerUsername,
                required String peerDisplayName,
                Value<String?> peerAvatarUrl = const Value.absent(),
                Value<String?> peerAvatarStoragePath = const Value.absent(),
                Value<String?> lastMessageId = const Value.absent(),
                required String lastMessage,
                required String lastMessageType,
                required DateTime lastMessageTime,
                required int unreadCount,
                required bool isLastMessageFromMe,
                required bool isMuted,
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<bool> showsLastSeen = const Value.absent(),
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedChatsCompanion.insert(
                ownerUserId: ownerUserId,
                id: id,
                peerId: peerId,
                peerUsername: peerUsername,
                peerDisplayName: peerDisplayName,
                peerAvatarUrl: peerAvatarUrl,
                peerAvatarStoragePath: peerAvatarStoragePath,
                lastMessageId: lastMessageId,
                lastMessage: lastMessage,
                lastMessageType: lastMessageType,
                lastMessageTime: lastMessageTime,
                unreadCount: unreadCount,
                isLastMessageFromMe: isLastMessageFromMe,
                isMuted: isMuted,
                lastSeenAt: lastSeenAt,
                showsLastSeen: showsLastSeen,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedChatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedChatsTable,
      CachedChat,
      $$CachedChatsTableFilterComposer,
      $$CachedChatsTableOrderingComposer,
      $$CachedChatsTableAnnotationComposer,
      $$CachedChatsTableCreateCompanionBuilder,
      $$CachedChatsTableUpdateCompanionBuilder,
      (
        CachedChat,
        BaseReferences<_$AppDatabase, $CachedChatsTable, CachedChat>,
      ),
      CachedChat,
      PrefetchHooks Function()
    >;
typedef $$CachedMessagesTableCreateCompanionBuilder =
    CachedMessagesCompanion Function({
      required String ownerUserId,
      required String id,
      required String chatId,
      required String senderId,
      required String messageText,
      required DateTime timestamp,
      required String status,
      required String type,
      required String mediaUrlsJson,
      required String mediaStoragePathsJson,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<String?> audioUrl,
      Value<String?> audioStoragePath,
      Value<int?> audioDurationMs,
      required String audioWaveformJson,
      Value<String?> replyMessageId,
      Value<String?> replySenderId,
      Value<String?> replyType,
      Value<String?> replyText,
      Value<DateTime?> readAt,
      required bool isPending,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedMessagesTableUpdateCompanionBuilder =
    CachedMessagesCompanion Function({
      Value<String> ownerUserId,
      Value<String> id,
      Value<String> chatId,
      Value<String> senderId,
      Value<String> messageText,
      Value<DateTime> timestamp,
      Value<String> status,
      Value<String> type,
      Value<String> mediaUrlsJson,
      Value<String> mediaStoragePathsJson,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<String?> audioUrl,
      Value<String?> audioStoragePath,
      Value<int?> audioDurationMs,
      Value<String> audioWaveformJson,
      Value<String?> replyMessageId,
      Value<String?> replySenderId,
      Value<String?> replyType,
      Value<String?> replyText,
      Value<DateTime?> readAt,
      Value<bool> isPending,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageText => $composableBuilder(
    column: $table.messageText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaUrlsJson => $composableBuilder(
    column: $table.mediaUrlsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaStoragePathsJson => $composableBuilder(
    column: $table.mediaStoragePathsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioUrl => $composableBuilder(
    column: $table.audioUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioStoragePath => $composableBuilder(
    column: $table.audioStoragePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get audioDurationMs => $composableBuilder(
    column: $table.audioDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioWaveformJson => $composableBuilder(
    column: $table.audioWaveformJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyMessageId => $composableBuilder(
    column: $table.replyMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replySenderId => $composableBuilder(
    column: $table.replySenderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyType => $composableBuilder(
    column: $table.replyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyText => $composableBuilder(
    column: $table.replyText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPending => $composableBuilder(
    column: $table.isPending,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageText => $composableBuilder(
    column: $table.messageText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaUrlsJson => $composableBuilder(
    column: $table.mediaUrlsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaStoragePathsJson => $composableBuilder(
    column: $table.mediaStoragePathsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioUrl => $composableBuilder(
    column: $table.audioUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioStoragePath => $composableBuilder(
    column: $table.audioStoragePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get audioDurationMs => $composableBuilder(
    column: $table.audioDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioWaveformJson => $composableBuilder(
    column: $table.audioWaveformJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyMessageId => $composableBuilder(
    column: $table.replyMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replySenderId => $composableBuilder(
    column: $table.replySenderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyType => $composableBuilder(
    column: $table.replyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyText => $composableBuilder(
    column: $table.replyText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPending => $composableBuilder(
    column: $table.isPending,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get messageText => $composableBuilder(
    column: $table.messageText,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get mediaUrlsJson => $composableBuilder(
    column: $table.mediaUrlsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaStoragePathsJson => $composableBuilder(
    column: $table.mediaStoragePathsJson,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get audioUrl =>
      $composableBuilder(column: $table.audioUrl, builder: (column) => column);

  GeneratedColumn<String> get audioStoragePath => $composableBuilder(
    column: $table.audioStoragePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get audioDurationMs => $composableBuilder(
    column: $table.audioDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioWaveformJson => $composableBuilder(
    column: $table.audioWaveformJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyMessageId => $composableBuilder(
    column: $table.replyMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replySenderId => $composableBuilder(
    column: $table.replySenderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyType =>
      $composableBuilder(column: $table.replyType, builder: (column) => column);

  GeneratedColumn<String> get replyText =>
      $composableBuilder(column: $table.replyText, builder: (column) => column);

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumn<bool> get isPending =>
      $composableBuilder(column: $table.isPending, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedMessagesTable,
          CachedMessage,
          $$CachedMessagesTableFilterComposer,
          $$CachedMessagesTableOrderingComposer,
          $$CachedMessagesTableAnnotationComposer,
          $$CachedMessagesTableCreateCompanionBuilder,
          $$CachedMessagesTableUpdateCompanionBuilder,
          (
            CachedMessage,
            BaseReferences<_$AppDatabase, $CachedMessagesTable, CachedMessage>,
          ),
          CachedMessage,
          PrefetchHooks Function()
        > {
  $$CachedMessagesTableTableManager(
    _$AppDatabase db,
    $CachedMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String> messageText = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> mediaUrlsJson = const Value.absent(),
                Value<String> mediaStoragePathsJson = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<String?> audioUrl = const Value.absent(),
                Value<String?> audioStoragePath = const Value.absent(),
                Value<int?> audioDurationMs = const Value.absent(),
                Value<String> audioWaveformJson = const Value.absent(),
                Value<String?> replyMessageId = const Value.absent(),
                Value<String?> replySenderId = const Value.absent(),
                Value<String?> replyType = const Value.absent(),
                Value<String?> replyText = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<bool> isPending = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion(
                ownerUserId: ownerUserId,
                id: id,
                chatId: chatId,
                senderId: senderId,
                messageText: messageText,
                timestamp: timestamp,
                status: status,
                type: type,
                mediaUrlsJson: mediaUrlsJson,
                mediaStoragePathsJson: mediaStoragePathsJson,
                latitude: latitude,
                longitude: longitude,
                audioUrl: audioUrl,
                audioStoragePath: audioStoragePath,
                audioDurationMs: audioDurationMs,
                audioWaveformJson: audioWaveformJson,
                replyMessageId: replyMessageId,
                replySenderId: replySenderId,
                replyType: replyType,
                replyText: replyText,
                readAt: readAt,
                isPending: isPending,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String id,
                required String chatId,
                required String senderId,
                required String messageText,
                required DateTime timestamp,
                required String status,
                required String type,
                required String mediaUrlsJson,
                required String mediaStoragePathsJson,
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<String?> audioUrl = const Value.absent(),
                Value<String?> audioStoragePath = const Value.absent(),
                Value<int?> audioDurationMs = const Value.absent(),
                required String audioWaveformJson,
                Value<String?> replyMessageId = const Value.absent(),
                Value<String?> replySenderId = const Value.absent(),
                Value<String?> replyType = const Value.absent(),
                Value<String?> replyText = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                required bool isPending,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion.insert(
                ownerUserId: ownerUserId,
                id: id,
                chatId: chatId,
                senderId: senderId,
                messageText: messageText,
                timestamp: timestamp,
                status: status,
                type: type,
                mediaUrlsJson: mediaUrlsJson,
                mediaStoragePathsJson: mediaStoragePathsJson,
                latitude: latitude,
                longitude: longitude,
                audioUrl: audioUrl,
                audioStoragePath: audioStoragePath,
                audioDurationMs: audioDurationMs,
                audioWaveformJson: audioWaveformJson,
                replyMessageId: replyMessageId,
                replySenderId: replySenderId,
                replyType: replyType,
                replyText: replyText,
                readAt: readAt,
                isPending: isPending,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedMessagesTable,
      CachedMessage,
      $$CachedMessagesTableFilterComposer,
      $$CachedMessagesTableOrderingComposer,
      $$CachedMessagesTableAnnotationComposer,
      $$CachedMessagesTableCreateCompanionBuilder,
      $$CachedMessagesTableUpdateCompanionBuilder,
      (
        CachedMessage,
        BaseReferences<_$AppDatabase, $CachedMessagesTable, CachedMessage>,
      ),
      CachedMessage,
      PrefetchHooks Function()
    >;
typedef $$PendingChatOperationsTableCreateCompanionBuilder =
    PendingChatOperationsCompanion Function({
      required String ownerUserId,
      required String id,
      required String chatId,
      required String type,
      required String payloadJson,
      Value<int> attempts,
      Value<String?> lastError,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$PendingChatOperationsTableUpdateCompanionBuilder =
    PendingChatOperationsCompanion Function({
      Value<String> ownerUserId,
      Value<String> id,
      Value<String> chatId,
      Value<String> type,
      Value<String> payloadJson,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$PendingChatOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingChatOperationsTable> {
  $$PendingChatOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingChatOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingChatOperationsTable> {
  $$PendingChatOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingChatOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingChatOperationsTable> {
  $$PendingChatOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PendingChatOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingChatOperationsTable,
          PendingChatOperation,
          $$PendingChatOperationsTableFilterComposer,
          $$PendingChatOperationsTableOrderingComposer,
          $$PendingChatOperationsTableAnnotationComposer,
          $$PendingChatOperationsTableCreateCompanionBuilder,
          $$PendingChatOperationsTableUpdateCompanionBuilder,
          (
            PendingChatOperation,
            BaseReferences<
              _$AppDatabase,
              $PendingChatOperationsTable,
              PendingChatOperation
            >,
          ),
          PendingChatOperation,
          PrefetchHooks Function()
        > {
  $$PendingChatOperationsTableTableManager(
    _$AppDatabase db,
    $PendingChatOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingChatOperationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PendingChatOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PendingChatOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingChatOperationsCompanion(
                ownerUserId: ownerUserId,
                id: id,
                chatId: chatId,
                type: type,
                payloadJson: payloadJson,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String id,
                required String chatId,
                required String type,
                required String payloadJson,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => PendingChatOperationsCompanion.insert(
                ownerUserId: ownerUserId,
                id: id,
                chatId: chatId,
                type: type,
                payloadJson: payloadJson,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingChatOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingChatOperationsTable,
      PendingChatOperation,
      $$PendingChatOperationsTableFilterComposer,
      $$PendingChatOperationsTableOrderingComposer,
      $$PendingChatOperationsTableAnnotationComposer,
      $$PendingChatOperationsTableCreateCompanionBuilder,
      $$PendingChatOperationsTableUpdateCompanionBuilder,
      (
        PendingChatOperation,
        BaseReferences<
          _$AppDatabase,
          $PendingChatOperationsTable,
          PendingChatOperation
        >,
      ),
      PendingChatOperation,
      PrefetchHooks Function()
    >;
typedef $$CachedFriendsTableCreateCompanionBuilder =
    CachedFriendsCompanion Function({
      required String ownerUserId,
      required String userId,
      required String username,
      required String displayName,
      Value<String?> avatarUrl,
      Value<String?> avatarStoragePath,
      required DateTime friendsSince,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedFriendsTableUpdateCompanionBuilder =
    CachedFriendsCompanion Function({
      Value<String> ownerUserId,
      Value<String> userId,
      Value<String> username,
      Value<String> displayName,
      Value<String?> avatarUrl,
      Value<String?> avatarStoragePath,
      Value<DateTime> friendsSince,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedFriendsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedFriendsTable> {
  $$CachedFriendsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get friendsSince => $composableBuilder(
    column: $table.friendsSince,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedFriendsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedFriendsTable> {
  $$CachedFriendsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get friendsSince => $composableBuilder(
    column: $table.friendsSince,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedFriendsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedFriendsTable> {
  $$CachedFriendsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get friendsSince => $composableBuilder(
    column: $table.friendsSince,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedFriendsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedFriendsTable,
          CachedFriend,
          $$CachedFriendsTableFilterComposer,
          $$CachedFriendsTableOrderingComposer,
          $$CachedFriendsTableAnnotationComposer,
          $$CachedFriendsTableCreateCompanionBuilder,
          $$CachedFriendsTableUpdateCompanionBuilder,
          (
            CachedFriend,
            BaseReferences<_$AppDatabase, $CachedFriendsTable, CachedFriend>,
          ),
          CachedFriend,
          PrefetchHooks Function()
        > {
  $$CachedFriendsTableTableManager(_$AppDatabase db, $CachedFriendsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedFriendsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedFriendsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedFriendsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> avatarStoragePath = const Value.absent(),
                Value<DateTime> friendsSince = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFriendsCompanion(
                ownerUserId: ownerUserId,
                userId: userId,
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl,
                avatarStoragePath: avatarStoragePath,
                friendsSince: friendsSince,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String userId,
                required String username,
                required String displayName,
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> avatarStoragePath = const Value.absent(),
                required DateTime friendsSince,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedFriendsCompanion.insert(
                ownerUserId: ownerUserId,
                userId: userId,
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl,
                avatarStoragePath: avatarStoragePath,
                friendsSince: friendsSince,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedFriendsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedFriendsTable,
      CachedFriend,
      $$CachedFriendsTableFilterComposer,
      $$CachedFriendsTableOrderingComposer,
      $$CachedFriendsTableAnnotationComposer,
      $$CachedFriendsTableCreateCompanionBuilder,
      $$CachedFriendsTableUpdateCompanionBuilder,
      (
        CachedFriend,
        BaseReferences<_$AppDatabase, $CachedFriendsTable, CachedFriend>,
      ),
      CachedFriend,
      PrefetchHooks Function()
    >;
typedef $$CachedFriendRequestsTableCreateCompanionBuilder =
    CachedFriendRequestsCompanion Function({
      required String ownerUserId,
      required String requestId,
      required String peerId,
      required String peerUsername,
      required String peerDisplayName,
      Value<String?> peerAvatarUrl,
      Value<String?> peerAvatarStoragePath,
      Value<int?> peerFriendCount,
      required String direction,
      required DateTime requestedAt,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedFriendRequestsTableUpdateCompanionBuilder =
    CachedFriendRequestsCompanion Function({
      Value<String> ownerUserId,
      Value<String> requestId,
      Value<String> peerId,
      Value<String> peerUsername,
      Value<String> peerDisplayName,
      Value<String?> peerAvatarUrl,
      Value<String?> peerAvatarStoragePath,
      Value<int?> peerFriendCount,
      Value<String> direction,
      Value<DateTime> requestedAt,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedFriendRequestsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedFriendRequestsTable> {
  $$CachedFriendRequestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerUsername => $composableBuilder(
    column: $table.peerUsername,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerAvatarUrl => $composableBuilder(
    column: $table.peerAvatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerAvatarStoragePath => $composableBuilder(
    column: $table.peerAvatarStoragePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get peerFriendCount => $composableBuilder(
    column: $table.peerFriendCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedFriendRequestsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedFriendRequestsTable> {
  $$CachedFriendRequestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerUsername => $composableBuilder(
    column: $table.peerUsername,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerAvatarUrl => $composableBuilder(
    column: $table.peerAvatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerAvatarStoragePath => $composableBuilder(
    column: $table.peerAvatarStoragePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get peerFriendCount => $composableBuilder(
    column: $table.peerFriendCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedFriendRequestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedFriendRequestsTable> {
  $$CachedFriendRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get peerUsername => $composableBuilder(
    column: $table.peerUsername,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerAvatarUrl => $composableBuilder(
    column: $table.peerAvatarUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerAvatarStoragePath => $composableBuilder(
    column: $table.peerAvatarStoragePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get peerFriendCount => $composableBuilder(
    column: $table.peerFriendCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedFriendRequestsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedFriendRequestsTable,
          CachedFriendRequest,
          $$CachedFriendRequestsTableFilterComposer,
          $$CachedFriendRequestsTableOrderingComposer,
          $$CachedFriendRequestsTableAnnotationComposer,
          $$CachedFriendRequestsTableCreateCompanionBuilder,
          $$CachedFriendRequestsTableUpdateCompanionBuilder,
          (
            CachedFriendRequest,
            BaseReferences<
              _$AppDatabase,
              $CachedFriendRequestsTable,
              CachedFriendRequest
            >,
          ),
          CachedFriendRequest,
          PrefetchHooks Function()
        > {
  $$CachedFriendRequestsTableTableManager(
    _$AppDatabase db,
    $CachedFriendRequestsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedFriendRequestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedFriendRequestsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedFriendRequestsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> requestId = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String> peerUsername = const Value.absent(),
                Value<String> peerDisplayName = const Value.absent(),
                Value<String?> peerAvatarUrl = const Value.absent(),
                Value<String?> peerAvatarStoragePath = const Value.absent(),
                Value<int?> peerFriendCount = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<DateTime> requestedAt = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFriendRequestsCompanion(
                ownerUserId: ownerUserId,
                requestId: requestId,
                peerId: peerId,
                peerUsername: peerUsername,
                peerDisplayName: peerDisplayName,
                peerAvatarUrl: peerAvatarUrl,
                peerAvatarStoragePath: peerAvatarStoragePath,
                peerFriendCount: peerFriendCount,
                direction: direction,
                requestedAt: requestedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String requestId,
                required String peerId,
                required String peerUsername,
                required String peerDisplayName,
                Value<String?> peerAvatarUrl = const Value.absent(),
                Value<String?> peerAvatarStoragePath = const Value.absent(),
                Value<int?> peerFriendCount = const Value.absent(),
                required String direction,
                required DateTime requestedAt,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedFriendRequestsCompanion.insert(
                ownerUserId: ownerUserId,
                requestId: requestId,
                peerId: peerId,
                peerUsername: peerUsername,
                peerDisplayName: peerDisplayName,
                peerAvatarUrl: peerAvatarUrl,
                peerAvatarStoragePath: peerAvatarStoragePath,
                peerFriendCount: peerFriendCount,
                direction: direction,
                requestedAt: requestedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedFriendRequestsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedFriendRequestsTable,
      CachedFriendRequest,
      $$CachedFriendRequestsTableFilterComposer,
      $$CachedFriendRequestsTableOrderingComposer,
      $$CachedFriendRequestsTableAnnotationComposer,
      $$CachedFriendRequestsTableCreateCompanionBuilder,
      $$CachedFriendRequestsTableUpdateCompanionBuilder,
      (
        CachedFriendRequest,
        BaseReferences<
          _$AppDatabase,
          $CachedFriendRequestsTable,
          CachedFriendRequest
        >,
      ),
      CachedFriendRequest,
      PrefetchHooks Function()
    >;
typedef $$CachedFriendLocationsTableCreateCompanionBuilder =
    CachedFriendLocationsCompanion Function({
      required String ownerUserId,
      required String friendUserId,
      required double latitude,
      required double longitude,
      required int locationUpdatedAtMs,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedFriendLocationsTableUpdateCompanionBuilder =
    CachedFriendLocationsCompanion Function({
      Value<String> ownerUserId,
      Value<String> friendUserId,
      Value<double> latitude,
      Value<double> longitude,
      Value<int> locationUpdatedAtMs,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedFriendLocationsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedFriendLocationsTable> {
  $$CachedFriendLocationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get friendUserId => $composableBuilder(
    column: $table.friendUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get locationUpdatedAtMs => $composableBuilder(
    column: $table.locationUpdatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedFriendLocationsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedFriendLocationsTable> {
  $$CachedFriendLocationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get friendUserId => $composableBuilder(
    column: $table.friendUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get locationUpdatedAtMs => $composableBuilder(
    column: $table.locationUpdatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedFriendLocationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedFriendLocationsTable> {
  $$CachedFriendLocationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get friendUserId => $composableBuilder(
    column: $table.friendUserId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<int> get locationUpdatedAtMs => $composableBuilder(
    column: $table.locationUpdatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedFriendLocationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedFriendLocationsTable,
          CachedFriendLocation,
          $$CachedFriendLocationsTableFilterComposer,
          $$CachedFriendLocationsTableOrderingComposer,
          $$CachedFriendLocationsTableAnnotationComposer,
          $$CachedFriendLocationsTableCreateCompanionBuilder,
          $$CachedFriendLocationsTableUpdateCompanionBuilder,
          (
            CachedFriendLocation,
            BaseReferences<
              _$AppDatabase,
              $CachedFriendLocationsTable,
              CachedFriendLocation
            >,
          ),
          CachedFriendLocation,
          PrefetchHooks Function()
        > {
  $$CachedFriendLocationsTableTableManager(
    _$AppDatabase db,
    $CachedFriendLocationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedFriendLocationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedFriendLocationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedFriendLocationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> friendUserId = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<int> locationUpdatedAtMs = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFriendLocationsCompanion(
                ownerUserId: ownerUserId,
                friendUserId: friendUserId,
                latitude: latitude,
                longitude: longitude,
                locationUpdatedAtMs: locationUpdatedAtMs,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String friendUserId,
                required double latitude,
                required double longitude,
                required int locationUpdatedAtMs,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedFriendLocationsCompanion.insert(
                ownerUserId: ownerUserId,
                friendUserId: friendUserId,
                latitude: latitude,
                longitude: longitude,
                locationUpdatedAtMs: locationUpdatedAtMs,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedFriendLocationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedFriendLocationsTable,
      CachedFriendLocation,
      $$CachedFriendLocationsTableFilterComposer,
      $$CachedFriendLocationsTableOrderingComposer,
      $$CachedFriendLocationsTableAnnotationComposer,
      $$CachedFriendLocationsTableCreateCompanionBuilder,
      $$CachedFriendLocationsTableUpdateCompanionBuilder,
      (
        CachedFriendLocation,
        BaseReferences<
          _$AppDatabase,
          $CachedFriendLocationsTable,
          CachedFriendLocation
        >,
      ),
      CachedFriendLocation,
      PrefetchHooks Function()
    >;
typedef $$CachedContactMatchesTableCreateCompanionBuilder =
    CachedContactMatchesCompanion Function({
      required String ownerUserId,
      required String phoneKey,
      required bool isRegistered,
      Value<String?> candidateId,
      Value<String?> username,
      Value<String?> displayName,
      Value<String?> avatarUrl,
      Value<String?> avatarStoragePath,
      Value<int?> friendCount,
      required DateTime checkedAt,
      Value<int> rowid,
    });
typedef $$CachedContactMatchesTableUpdateCompanionBuilder =
    CachedContactMatchesCompanion Function({
      Value<String> ownerUserId,
      Value<String> phoneKey,
      Value<bool> isRegistered,
      Value<String?> candidateId,
      Value<String?> username,
      Value<String?> displayName,
      Value<String?> avatarUrl,
      Value<String?> avatarStoragePath,
      Value<int?> friendCount,
      Value<DateTime> checkedAt,
      Value<int> rowid,
    });

class $$CachedContactMatchesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedContactMatchesTable> {
  $$CachedContactMatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneKey => $composableBuilder(
    column: $table.phoneKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRegistered => $composableBuilder(
    column: $table.isRegistered,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get candidateId => $composableBuilder(
    column: $table.candidateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get friendCount => $composableBuilder(
    column: $table.friendCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedContactMatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedContactMatchesTable> {
  $$CachedContactMatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneKey => $composableBuilder(
    column: $table.phoneKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRegistered => $composableBuilder(
    column: $table.isRegistered,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get candidateId => $composableBuilder(
    column: $table.candidateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get friendCount => $composableBuilder(
    column: $table.friendCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedContactMatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedContactMatchesTable> {
  $$CachedContactMatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get phoneKey =>
      $composableBuilder(column: $table.phoneKey, builder: (column) => column);

  GeneratedColumn<bool> get isRegistered => $composableBuilder(
    column: $table.isRegistered,
    builder: (column) => column,
  );

  GeneratedColumn<String> get candidateId => $composableBuilder(
    column: $table.candidateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get friendCount => $composableBuilder(
    column: $table.friendCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);
}

class $$CachedContactMatchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedContactMatchesTable,
          CachedContactMatch,
          $$CachedContactMatchesTableFilterComposer,
          $$CachedContactMatchesTableOrderingComposer,
          $$CachedContactMatchesTableAnnotationComposer,
          $$CachedContactMatchesTableCreateCompanionBuilder,
          $$CachedContactMatchesTableUpdateCompanionBuilder,
          (
            CachedContactMatch,
            BaseReferences<
              _$AppDatabase,
              $CachedContactMatchesTable,
              CachedContactMatch
            >,
          ),
          CachedContactMatch,
          PrefetchHooks Function()
        > {
  $$CachedContactMatchesTableTableManager(
    _$AppDatabase db,
    $CachedContactMatchesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedContactMatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedContactMatchesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedContactMatchesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> phoneKey = const Value.absent(),
                Value<bool> isRegistered = const Value.absent(),
                Value<String?> candidateId = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> avatarStoragePath = const Value.absent(),
                Value<int?> friendCount = const Value.absent(),
                Value<DateTime> checkedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedContactMatchesCompanion(
                ownerUserId: ownerUserId,
                phoneKey: phoneKey,
                isRegistered: isRegistered,
                candidateId: candidateId,
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl,
                avatarStoragePath: avatarStoragePath,
                friendCount: friendCount,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String phoneKey,
                required bool isRegistered,
                Value<String?> candidateId = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> avatarStoragePath = const Value.absent(),
                Value<int?> friendCount = const Value.absent(),
                required DateTime checkedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedContactMatchesCompanion.insert(
                ownerUserId: ownerUserId,
                phoneKey: phoneKey,
                isRegistered: isRegistered,
                candidateId: candidateId,
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl,
                avatarStoragePath: avatarStoragePath,
                friendCount: friendCount,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedContactMatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedContactMatchesTable,
      CachedContactMatch,
      $$CachedContactMatchesTableFilterComposer,
      $$CachedContactMatchesTableOrderingComposer,
      $$CachedContactMatchesTableAnnotationComposer,
      $$CachedContactMatchesTableCreateCompanionBuilder,
      $$CachedContactMatchesTableUpdateCompanionBuilder,
      (
        CachedContactMatch,
        BaseReferences<
          _$AppDatabase,
          $CachedContactMatchesTable,
          CachedContactMatch
        >,
      ),
      CachedContactMatch,
      PrefetchHooks Function()
    >;
typedef $$CachedSearchPrivacySettingsTableCreateCompanionBuilder =
    CachedSearchPrivacySettingsCompanion Function({
      required String ownerUserId,
      required bool searchByUsername,
      required bool searchByPhone,
      required bool searchByName,
      Value<String> lastSeenVisibility,
      Value<bool> sharePreciseLocation,
      Value<bool> shareDistance,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedSearchPrivacySettingsTableUpdateCompanionBuilder =
    CachedSearchPrivacySettingsCompanion Function({
      Value<String> ownerUserId,
      Value<bool> searchByUsername,
      Value<bool> searchByPhone,
      Value<bool> searchByName,
      Value<String> lastSeenVisibility,
      Value<bool> sharePreciseLocation,
      Value<bool> shareDistance,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedSearchPrivacySettingsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedSearchPrivacySettingsTable> {
  $$CachedSearchPrivacySettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get searchByUsername => $composableBuilder(
    column: $table.searchByUsername,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get searchByPhone => $composableBuilder(
    column: $table.searchByPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get searchByName => $composableBuilder(
    column: $table.searchByName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSeenVisibility => $composableBuilder(
    column: $table.lastSeenVisibility,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sharePreciseLocation => $composableBuilder(
    column: $table.sharePreciseLocation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get shareDistance => $composableBuilder(
    column: $table.shareDistance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedSearchPrivacySettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedSearchPrivacySettingsTable> {
  $$CachedSearchPrivacySettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get searchByUsername => $composableBuilder(
    column: $table.searchByUsername,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get searchByPhone => $composableBuilder(
    column: $table.searchByPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get searchByName => $composableBuilder(
    column: $table.searchByName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSeenVisibility => $composableBuilder(
    column: $table.lastSeenVisibility,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sharePreciseLocation => $composableBuilder(
    column: $table.sharePreciseLocation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get shareDistance => $composableBuilder(
    column: $table.shareDistance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedSearchPrivacySettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedSearchPrivacySettingsTable> {
  $$CachedSearchPrivacySettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get searchByUsername => $composableBuilder(
    column: $table.searchByUsername,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get searchByPhone => $composableBuilder(
    column: $table.searchByPhone,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get searchByName => $composableBuilder(
    column: $table.searchByName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSeenVisibility => $composableBuilder(
    column: $table.lastSeenVisibility,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get sharePreciseLocation => $composableBuilder(
    column: $table.sharePreciseLocation,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get shareDistance => $composableBuilder(
    column: $table.shareDistance,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedSearchPrivacySettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedSearchPrivacySettingsTable,
          CachedSearchPrivacySetting,
          $$CachedSearchPrivacySettingsTableFilterComposer,
          $$CachedSearchPrivacySettingsTableOrderingComposer,
          $$CachedSearchPrivacySettingsTableAnnotationComposer,
          $$CachedSearchPrivacySettingsTableCreateCompanionBuilder,
          $$CachedSearchPrivacySettingsTableUpdateCompanionBuilder,
          (
            CachedSearchPrivacySetting,
            BaseReferences<
              _$AppDatabase,
              $CachedSearchPrivacySettingsTable,
              CachedSearchPrivacySetting
            >,
          ),
          CachedSearchPrivacySetting,
          PrefetchHooks Function()
        > {
  $$CachedSearchPrivacySettingsTableTableManager(
    _$AppDatabase db,
    $CachedSearchPrivacySettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedSearchPrivacySettingsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedSearchPrivacySettingsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedSearchPrivacySettingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<bool> searchByUsername = const Value.absent(),
                Value<bool> searchByPhone = const Value.absent(),
                Value<bool> searchByName = const Value.absent(),
                Value<String> lastSeenVisibility = const Value.absent(),
                Value<bool> sharePreciseLocation = const Value.absent(),
                Value<bool> shareDistance = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedSearchPrivacySettingsCompanion(
                ownerUserId: ownerUserId,
                searchByUsername: searchByUsername,
                searchByPhone: searchByPhone,
                searchByName: searchByName,
                lastSeenVisibility: lastSeenVisibility,
                sharePreciseLocation: sharePreciseLocation,
                shareDistance: shareDistance,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required bool searchByUsername,
                required bool searchByPhone,
                required bool searchByName,
                Value<String> lastSeenVisibility = const Value.absent(),
                Value<bool> sharePreciseLocation = const Value.absent(),
                Value<bool> shareDistance = const Value.absent(),
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedSearchPrivacySettingsCompanion.insert(
                ownerUserId: ownerUserId,
                searchByUsername: searchByUsername,
                searchByPhone: searchByPhone,
                searchByName: searchByName,
                lastSeenVisibility: lastSeenVisibility,
                sharePreciseLocation: sharePreciseLocation,
                shareDistance: shareDistance,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedSearchPrivacySettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedSearchPrivacySettingsTable,
      CachedSearchPrivacySetting,
      $$CachedSearchPrivacySettingsTableFilterComposer,
      $$CachedSearchPrivacySettingsTableOrderingComposer,
      $$CachedSearchPrivacySettingsTableAnnotationComposer,
      $$CachedSearchPrivacySettingsTableCreateCompanionBuilder,
      $$CachedSearchPrivacySettingsTableUpdateCompanionBuilder,
      (
        CachedSearchPrivacySetting,
        BaseReferences<
          _$AppDatabase,
          $CachedSearchPrivacySettingsTable,
          CachedSearchPrivacySetting
        >,
      ),
      CachedSearchPrivacySetting,
      PrefetchHooks Function()
    >;
typedef $$CachedPreciseLocationExclusionsTableCreateCompanionBuilder =
    CachedPreciseLocationExclusionsCompanion Function({
      required String ownerUserId,
      required String viewerUserId,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedPreciseLocationExclusionsTableUpdateCompanionBuilder =
    CachedPreciseLocationExclusionsCompanion Function({
      Value<String> ownerUserId,
      Value<String> viewerUserId,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedPreciseLocationExclusionsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedPreciseLocationExclusionsTable> {
  $$CachedPreciseLocationExclusionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get viewerUserId => $composableBuilder(
    column: $table.viewerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPreciseLocationExclusionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedPreciseLocationExclusionsTable> {
  $$CachedPreciseLocationExclusionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get viewerUserId => $composableBuilder(
    column: $table.viewerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPreciseLocationExclusionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedPreciseLocationExclusionsTable> {
  $$CachedPreciseLocationExclusionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get viewerUserId => $composableBuilder(
    column: $table.viewerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedPreciseLocationExclusionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedPreciseLocationExclusionsTable,
          CachedPreciseLocationExclusion,
          $$CachedPreciseLocationExclusionsTableFilterComposer,
          $$CachedPreciseLocationExclusionsTableOrderingComposer,
          $$CachedPreciseLocationExclusionsTableAnnotationComposer,
          $$CachedPreciseLocationExclusionsTableCreateCompanionBuilder,
          $$CachedPreciseLocationExclusionsTableUpdateCompanionBuilder,
          (
            CachedPreciseLocationExclusion,
            BaseReferences<
              _$AppDatabase,
              $CachedPreciseLocationExclusionsTable,
              CachedPreciseLocationExclusion
            >,
          ),
          CachedPreciseLocationExclusion,
          PrefetchHooks Function()
        > {
  $$CachedPreciseLocationExclusionsTableTableManager(
    _$AppDatabase db,
    $CachedPreciseLocationExclusionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPreciseLocationExclusionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedPreciseLocationExclusionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedPreciseLocationExclusionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> viewerUserId = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPreciseLocationExclusionsCompanion(
                ownerUserId: ownerUserId,
                viewerUserId: viewerUserId,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String viewerUserId,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedPreciseLocationExclusionsCompanion.insert(
                ownerUserId: ownerUserId,
                viewerUserId: viewerUserId,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPreciseLocationExclusionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedPreciseLocationExclusionsTable,
      CachedPreciseLocationExclusion,
      $$CachedPreciseLocationExclusionsTableFilterComposer,
      $$CachedPreciseLocationExclusionsTableOrderingComposer,
      $$CachedPreciseLocationExclusionsTableAnnotationComposer,
      $$CachedPreciseLocationExclusionsTableCreateCompanionBuilder,
      $$CachedPreciseLocationExclusionsTableUpdateCompanionBuilder,
      (
        CachedPreciseLocationExclusion,
        BaseReferences<
          _$AppDatabase,
          $CachedPreciseLocationExclusionsTable,
          CachedPreciseLocationExclusion
        >,
      ),
      CachedPreciseLocationExclusion,
      PrefetchHooks Function()
    >;
typedef $$CachedViewedProfileMetadataTableCreateCompanionBuilder =
    CachedViewedProfileMetadataCompanion Function({
      required String ownerUserId,
      required String targetUserId,
      required String relationship,
      Value<String?> requestId,
      required int friendCount,
      required String friendsPreviewJson,
      required int viewCount,
      Value<DateTime?> lastSeenAt,
      required bool showsLastSeen,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedViewedProfileMetadataTableUpdateCompanionBuilder =
    CachedViewedProfileMetadataCompanion Function({
      Value<String> ownerUserId,
      Value<String> targetUserId,
      Value<String> relationship,
      Value<String?> requestId,
      Value<int> friendCount,
      Value<String> friendsPreviewJson,
      Value<int> viewCount,
      Value<DateTime?> lastSeenAt,
      Value<bool> showsLastSeen,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedViewedProfileMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileMetadataTable> {
  $$CachedViewedProfileMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get friendCount => $composableBuilder(
    column: $table.friendCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get friendsPreviewJson => $composableBuilder(
    column: $table.friendsPreviewJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get viewCount => $composableBuilder(
    column: $table.viewCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showsLastSeen => $composableBuilder(
    column: $table.showsLastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedViewedProfileMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileMetadataTable> {
  $$CachedViewedProfileMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get friendCount => $composableBuilder(
    column: $table.friendCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get friendsPreviewJson => $composableBuilder(
    column: $table.friendsPreviewJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get viewCount => $composableBuilder(
    column: $table.viewCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showsLastSeen => $composableBuilder(
    column: $table.showsLastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedViewedProfileMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileMetadataTable> {
  $$CachedViewedProfileMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<int> get friendCount => $composableBuilder(
    column: $table.friendCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get friendsPreviewJson => $composableBuilder(
    column: $table.friendsPreviewJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get viewCount =>
      $composableBuilder(column: $table.viewCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get showsLastSeen => $composableBuilder(
    column: $table.showsLastSeen,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedViewedProfileMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedViewedProfileMetadataTable,
          CachedViewedProfileMetadataData,
          $$CachedViewedProfileMetadataTableFilterComposer,
          $$CachedViewedProfileMetadataTableOrderingComposer,
          $$CachedViewedProfileMetadataTableAnnotationComposer,
          $$CachedViewedProfileMetadataTableCreateCompanionBuilder,
          $$CachedViewedProfileMetadataTableUpdateCompanionBuilder,
          (
            CachedViewedProfileMetadataData,
            BaseReferences<
              _$AppDatabase,
              $CachedViewedProfileMetadataTable,
              CachedViewedProfileMetadataData
            >,
          ),
          CachedViewedProfileMetadataData,
          PrefetchHooks Function()
        > {
  $$CachedViewedProfileMetadataTableTableManager(
    _$AppDatabase db,
    $CachedViewedProfileMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedViewedProfileMetadataTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedViewedProfileMetadataTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedViewedProfileMetadataTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> targetUserId = const Value.absent(),
                Value<String> relationship = const Value.absent(),
                Value<String?> requestId = const Value.absent(),
                Value<int> friendCount = const Value.absent(),
                Value<String> friendsPreviewJson = const Value.absent(),
                Value<int> viewCount = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<bool> showsLastSeen = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedViewedProfileMetadataCompanion(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                relationship: relationship,
                requestId: requestId,
                friendCount: friendCount,
                friendsPreviewJson: friendsPreviewJson,
                viewCount: viewCount,
                lastSeenAt: lastSeenAt,
                showsLastSeen: showsLastSeen,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String targetUserId,
                required String relationship,
                Value<String?> requestId = const Value.absent(),
                required int friendCount,
                required String friendsPreviewJson,
                required int viewCount,
                Value<DateTime?> lastSeenAt = const Value.absent(),
                required bool showsLastSeen,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedViewedProfileMetadataCompanion.insert(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                relationship: relationship,
                requestId: requestId,
                friendCount: friendCount,
                friendsPreviewJson: friendsPreviewJson,
                viewCount: viewCount,
                lastSeenAt: lastSeenAt,
                showsLastSeen: showsLastSeen,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedViewedProfileMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedViewedProfileMetadataTable,
      CachedViewedProfileMetadataData,
      $$CachedViewedProfileMetadataTableFilterComposer,
      $$CachedViewedProfileMetadataTableOrderingComposer,
      $$CachedViewedProfileMetadataTableAnnotationComposer,
      $$CachedViewedProfileMetadataTableCreateCompanionBuilder,
      $$CachedViewedProfileMetadataTableUpdateCompanionBuilder,
      (
        CachedViewedProfileMetadataData,
        BaseReferences<
          _$AppDatabase,
          $CachedViewedProfileMetadataTable,
          CachedViewedProfileMetadataData
        >,
      ),
      CachedViewedProfileMetadataData,
      PrefetchHooks Function()
    >;
typedef $$CachedViewedProfileFriendsTableCreateCompanionBuilder =
    CachedViewedProfileFriendsCompanion Function({
      required String ownerUserId,
      required String targetUserId,
      required String friendUserId,
      required String username,
      required String displayName,
      Value<String?> avatarUrl,
      Value<String?> avatarStoragePath,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedViewedProfileFriendsTableUpdateCompanionBuilder =
    CachedViewedProfileFriendsCompanion Function({
      Value<String> ownerUserId,
      Value<String> targetUserId,
      Value<String> friendUserId,
      Value<String> username,
      Value<String> displayName,
      Value<String?> avatarUrl,
      Value<String?> avatarStoragePath,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedViewedProfileFriendsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileFriendsTable> {
  $$CachedViewedProfileFriendsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get friendUserId => $composableBuilder(
    column: $table.friendUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedViewedProfileFriendsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileFriendsTable> {
  $$CachedViewedProfileFriendsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get friendUserId => $composableBuilder(
    column: $table.friendUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedViewedProfileFriendsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileFriendsTable> {
  $$CachedViewedProfileFriendsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get friendUserId => $composableBuilder(
    column: $table.friendUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get avatarStoragePath => $composableBuilder(
    column: $table.avatarStoragePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedViewedProfileFriendsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedViewedProfileFriendsTable,
          CachedViewedProfileFriend,
          $$CachedViewedProfileFriendsTableFilterComposer,
          $$CachedViewedProfileFriendsTableOrderingComposer,
          $$CachedViewedProfileFriendsTableAnnotationComposer,
          $$CachedViewedProfileFriendsTableCreateCompanionBuilder,
          $$CachedViewedProfileFriendsTableUpdateCompanionBuilder,
          (
            CachedViewedProfileFriend,
            BaseReferences<
              _$AppDatabase,
              $CachedViewedProfileFriendsTable,
              CachedViewedProfileFriend
            >,
          ),
          CachedViewedProfileFriend,
          PrefetchHooks Function()
        > {
  $$CachedViewedProfileFriendsTableTableManager(
    _$AppDatabase db,
    $CachedViewedProfileFriendsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedViewedProfileFriendsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedViewedProfileFriendsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedViewedProfileFriendsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> targetUserId = const Value.absent(),
                Value<String> friendUserId = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> avatarStoragePath = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedViewedProfileFriendsCompanion(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                friendUserId: friendUserId,
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl,
                avatarStoragePath: avatarStoragePath,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String targetUserId,
                required String friendUserId,
                required String username,
                required String displayName,
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> avatarStoragePath = const Value.absent(),
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedViewedProfileFriendsCompanion.insert(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                friendUserId: friendUserId,
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl,
                avatarStoragePath: avatarStoragePath,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedViewedProfileFriendsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedViewedProfileFriendsTable,
      CachedViewedProfileFriend,
      $$CachedViewedProfileFriendsTableFilterComposer,
      $$CachedViewedProfileFriendsTableOrderingComposer,
      $$CachedViewedProfileFriendsTableAnnotationComposer,
      $$CachedViewedProfileFriendsTableCreateCompanionBuilder,
      $$CachedViewedProfileFriendsTableUpdateCompanionBuilder,
      (
        CachedViewedProfileFriend,
        BaseReferences<
          _$AppDatabase,
          $CachedViewedProfileFriendsTable,
          CachedViewedProfileFriend
        >,
      ),
      CachedViewedProfileFriend,
      PrefetchHooks Function()
    >;
typedef $$CachedViewedProfileFriendListsTableCreateCompanionBuilder =
    CachedViewedProfileFriendListsCompanion Function({
      required String ownerUserId,
      required String targetUserId,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedViewedProfileFriendListsTableUpdateCompanionBuilder =
    CachedViewedProfileFriendListsCompanion Function({
      Value<String> ownerUserId,
      Value<String> targetUserId,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedViewedProfileFriendListsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileFriendListsTable> {
  $$CachedViewedProfileFriendListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedViewedProfileFriendListsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileFriendListsTable> {
  $$CachedViewedProfileFriendListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedViewedProfileFriendListsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedViewedProfileFriendListsTable> {
  $$CachedViewedProfileFriendListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedViewedProfileFriendListsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedViewedProfileFriendListsTable,
          CachedViewedProfileFriendList,
          $$CachedViewedProfileFriendListsTableFilterComposer,
          $$CachedViewedProfileFriendListsTableOrderingComposer,
          $$CachedViewedProfileFriendListsTableAnnotationComposer,
          $$CachedViewedProfileFriendListsTableCreateCompanionBuilder,
          $$CachedViewedProfileFriendListsTableUpdateCompanionBuilder,
          (
            CachedViewedProfileFriendList,
            BaseReferences<
              _$AppDatabase,
              $CachedViewedProfileFriendListsTable,
              CachedViewedProfileFriendList
            >,
          ),
          CachedViewedProfileFriendList,
          PrefetchHooks Function()
        > {
  $$CachedViewedProfileFriendListsTableTableManager(
    _$AppDatabase db,
    $CachedViewedProfileFriendListsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedViewedProfileFriendListsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedViewedProfileFriendListsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedViewedProfileFriendListsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> targetUserId = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedViewedProfileFriendListsCompanion(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String targetUserId,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedViewedProfileFriendListsCompanion.insert(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedViewedProfileFriendListsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedViewedProfileFriendListsTable,
      CachedViewedProfileFriendList,
      $$CachedViewedProfileFriendListsTableFilterComposer,
      $$CachedViewedProfileFriendListsTableOrderingComposer,
      $$CachedViewedProfileFriendListsTableAnnotationComposer,
      $$CachedViewedProfileFriendListsTableCreateCompanionBuilder,
      $$CachedViewedProfileFriendListsTableUpdateCompanionBuilder,
      (
        CachedViewedProfileFriendList,
        BaseReferences<
          _$AppDatabase,
          $CachedViewedProfileFriendListsTable,
          CachedViewedProfileFriendList
        >,
      ),
      CachedViewedProfileFriendList,
      PrefetchHooks Function()
    >;
typedef $$CachedUserDistancesTableCreateCompanionBuilder =
    CachedUserDistancesCompanion Function({
      required String ownerUserId,
      required String targetUserId,
      required int distanceValue,
      required String distanceUnit,
      required DateTime locationUpdatedAt,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedUserDistancesTableUpdateCompanionBuilder =
    CachedUserDistancesCompanion Function({
      Value<String> ownerUserId,
      Value<String> targetUserId,
      Value<int> distanceValue,
      Value<String> distanceUnit,
      Value<DateTime> locationUpdatedAt,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedUserDistancesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedUserDistancesTable> {
  $$CachedUserDistancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get distanceValue => $composableBuilder(
    column: $table.distanceValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get distanceUnit => $composableBuilder(
    column: $table.distanceUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get locationUpdatedAt => $composableBuilder(
    column: $table.locationUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedUserDistancesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedUserDistancesTable> {
  $$CachedUserDistancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get distanceValue => $composableBuilder(
    column: $table.distanceValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get distanceUnit => $composableBuilder(
    column: $table.distanceUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get locationUpdatedAt => $composableBuilder(
    column: $table.locationUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedUserDistancesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedUserDistancesTable> {
  $$CachedUserDistancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get distanceValue => $composableBuilder(
    column: $table.distanceValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get distanceUnit => $composableBuilder(
    column: $table.distanceUnit,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get locationUpdatedAt => $composableBuilder(
    column: $table.locationUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedUserDistancesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedUserDistancesTable,
          CachedUserDistance,
          $$CachedUserDistancesTableFilterComposer,
          $$CachedUserDistancesTableOrderingComposer,
          $$CachedUserDistancesTableAnnotationComposer,
          $$CachedUserDistancesTableCreateCompanionBuilder,
          $$CachedUserDistancesTableUpdateCompanionBuilder,
          (
            CachedUserDistance,
            BaseReferences<
              _$AppDatabase,
              $CachedUserDistancesTable,
              CachedUserDistance
            >,
          ),
          CachedUserDistance,
          PrefetchHooks Function()
        > {
  $$CachedUserDistancesTableTableManager(
    _$AppDatabase db,
    $CachedUserDistancesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedUserDistancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedUserDistancesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedUserDistancesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> targetUserId = const Value.absent(),
                Value<int> distanceValue = const Value.absent(),
                Value<String> distanceUnit = const Value.absent(),
                Value<DateTime> locationUpdatedAt = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedUserDistancesCompanion(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                distanceValue: distanceValue,
                distanceUnit: distanceUnit,
                locationUpdatedAt: locationUpdatedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String targetUserId,
                required int distanceValue,
                required String distanceUnit,
                required DateTime locationUpdatedAt,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedUserDistancesCompanion.insert(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                distanceValue: distanceValue,
                distanceUnit: distanceUnit,
                locationUpdatedAt: locationUpdatedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedUserDistancesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedUserDistancesTable,
      CachedUserDistance,
      $$CachedUserDistancesTableFilterComposer,
      $$CachedUserDistancesTableOrderingComposer,
      $$CachedUserDistancesTableAnnotationComposer,
      $$CachedUserDistancesTableCreateCompanionBuilder,
      $$CachedUserDistancesTableUpdateCompanionBuilder,
      (
        CachedUserDistance,
        BaseReferences<
          _$AppDatabase,
          $CachedUserDistancesTable,
          CachedUserDistance
        >,
      ),
      CachedUserDistance,
      PrefetchHooks Function()
    >;
typedef $$CachedProfileViewCountsTableCreateCompanionBuilder =
    CachedProfileViewCountsCompanion Function({
      required String ownerUserId,
      required String targetUserId,
      required int viewCount,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedProfileViewCountsTableUpdateCompanionBuilder =
    CachedProfileViewCountsCompanion Function({
      Value<String> ownerUserId,
      Value<String> targetUserId,
      Value<int> viewCount,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedProfileViewCountsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedProfileViewCountsTable> {
  $$CachedProfileViewCountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get viewCount => $composableBuilder(
    column: $table.viewCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProfileViewCountsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedProfileViewCountsTable> {
  $$CachedProfileViewCountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get viewCount => $composableBuilder(
    column: $table.viewCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProfileViewCountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedProfileViewCountsTable> {
  $$CachedProfileViewCountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get viewCount =>
      $composableBuilder(column: $table.viewCount, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedProfileViewCountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedProfileViewCountsTable,
          CachedProfileViewCount,
          $$CachedProfileViewCountsTableFilterComposer,
          $$CachedProfileViewCountsTableOrderingComposer,
          $$CachedProfileViewCountsTableAnnotationComposer,
          $$CachedProfileViewCountsTableCreateCompanionBuilder,
          $$CachedProfileViewCountsTableUpdateCompanionBuilder,
          (
            CachedProfileViewCount,
            BaseReferences<
              _$AppDatabase,
              $CachedProfileViewCountsTable,
              CachedProfileViewCount
            >,
          ),
          CachedProfileViewCount,
          PrefetchHooks Function()
        > {
  $$CachedProfileViewCountsTableTableManager(
    _$AppDatabase db,
    $CachedProfileViewCountsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProfileViewCountsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedProfileViewCountsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedProfileViewCountsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> targetUserId = const Value.absent(),
                Value<int> viewCount = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfileViewCountsCompanion(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                viewCount: viewCount,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String targetUserId,
                required int viewCount,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedProfileViewCountsCompanion.insert(
                ownerUserId: ownerUserId,
                targetUserId: targetUserId,
                viewCount: viewCount,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProfileViewCountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedProfileViewCountsTable,
      CachedProfileViewCount,
      $$CachedProfileViewCountsTableFilterComposer,
      $$CachedProfileViewCountsTableOrderingComposer,
      $$CachedProfileViewCountsTableAnnotationComposer,
      $$CachedProfileViewCountsTableCreateCompanionBuilder,
      $$CachedProfileViewCountsTableUpdateCompanionBuilder,
      (
        CachedProfileViewCount,
        BaseReferences<
          _$AppDatabase,
          $CachedProfileViewCountsTable,
          CachedProfileViewCount
        >,
      ),
      CachedProfileViewCount,
      PrefetchHooks Function()
    >;
typedef $$CachedAppLanguagesTableCreateCompanionBuilder =
    CachedAppLanguagesCompanion Function({
      required String ownerUserId,
      required String languageCode,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedAppLanguagesTableUpdateCompanionBuilder =
    CachedAppLanguagesCompanion Function({
      Value<String> ownerUserId,
      Value<String> languageCode,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedAppLanguagesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedAppLanguagesTable> {
  $$CachedAppLanguagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get languageCode => $composableBuilder(
    column: $table.languageCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedAppLanguagesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedAppLanguagesTable> {
  $$CachedAppLanguagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get languageCode => $composableBuilder(
    column: $table.languageCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedAppLanguagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedAppLanguagesTable> {
  $$CachedAppLanguagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get languageCode => $composableBuilder(
    column: $table.languageCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedAppLanguagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedAppLanguagesTable,
          CachedAppLanguage,
          $$CachedAppLanguagesTableFilterComposer,
          $$CachedAppLanguagesTableOrderingComposer,
          $$CachedAppLanguagesTableAnnotationComposer,
          $$CachedAppLanguagesTableCreateCompanionBuilder,
          $$CachedAppLanguagesTableUpdateCompanionBuilder,
          (
            CachedAppLanguage,
            BaseReferences<
              _$AppDatabase,
              $CachedAppLanguagesTable,
              CachedAppLanguage
            >,
          ),
          CachedAppLanguage,
          PrefetchHooks Function()
        > {
  $$CachedAppLanguagesTableTableManager(
    _$AppDatabase db,
    $CachedAppLanguagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedAppLanguagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedAppLanguagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedAppLanguagesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerUserId = const Value.absent(),
                Value<String> languageCode = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedAppLanguagesCompanion(
                ownerUserId: ownerUserId,
                languageCode: languageCode,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerUserId,
                required String languageCode,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedAppLanguagesCompanion.insert(
                ownerUserId: ownerUserId,
                languageCode: languageCode,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedAppLanguagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedAppLanguagesTable,
      CachedAppLanguage,
      $$CachedAppLanguagesTableFilterComposer,
      $$CachedAppLanguagesTableOrderingComposer,
      $$CachedAppLanguagesTableAnnotationComposer,
      $$CachedAppLanguagesTableCreateCompanionBuilder,
      $$CachedAppLanguagesTableUpdateCompanionBuilder,
      (
        CachedAppLanguage,
        BaseReferences<
          _$AppDatabase,
          $CachedAppLanguagesTable,
          CachedAppLanguage
        >,
      ),
      CachedAppLanguage,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedProfilesTableTableManager get cachedProfiles =>
      $$CachedProfilesTableTableManager(_db, _db.cachedProfiles);
  $$CachedProfilePhotosTableTableManager get cachedProfilePhotos =>
      $$CachedProfilePhotosTableTableManager(_db, _db.cachedProfilePhotos);
  $$CachedChatsTableTableManager get cachedChats =>
      $$CachedChatsTableTableManager(_db, _db.cachedChats);
  $$CachedMessagesTableTableManager get cachedMessages =>
      $$CachedMessagesTableTableManager(_db, _db.cachedMessages);
  $$PendingChatOperationsTableTableManager get pendingChatOperations =>
      $$PendingChatOperationsTableTableManager(_db, _db.pendingChatOperations);
  $$CachedFriendsTableTableManager get cachedFriends =>
      $$CachedFriendsTableTableManager(_db, _db.cachedFriends);
  $$CachedFriendRequestsTableTableManager get cachedFriendRequests =>
      $$CachedFriendRequestsTableTableManager(_db, _db.cachedFriendRequests);
  $$CachedFriendLocationsTableTableManager get cachedFriendLocations =>
      $$CachedFriendLocationsTableTableManager(_db, _db.cachedFriendLocations);
  $$CachedContactMatchesTableTableManager get cachedContactMatches =>
      $$CachedContactMatchesTableTableManager(_db, _db.cachedContactMatches);
  $$CachedSearchPrivacySettingsTableTableManager
  get cachedSearchPrivacySettings =>
      $$CachedSearchPrivacySettingsTableTableManager(
        _db,
        _db.cachedSearchPrivacySettings,
      );
  $$CachedPreciseLocationExclusionsTableTableManager
  get cachedPreciseLocationExclusions =>
      $$CachedPreciseLocationExclusionsTableTableManager(
        _db,
        _db.cachedPreciseLocationExclusions,
      );
  $$CachedViewedProfileMetadataTableTableManager
  get cachedViewedProfileMetadata =>
      $$CachedViewedProfileMetadataTableTableManager(
        _db,
        _db.cachedViewedProfileMetadata,
      );
  $$CachedViewedProfileFriendsTableTableManager
  get cachedViewedProfileFriends =>
      $$CachedViewedProfileFriendsTableTableManager(
        _db,
        _db.cachedViewedProfileFriends,
      );
  $$CachedViewedProfileFriendListsTableTableManager
  get cachedViewedProfileFriendLists =>
      $$CachedViewedProfileFriendListsTableTableManager(
        _db,
        _db.cachedViewedProfileFriendLists,
      );
  $$CachedUserDistancesTableTableManager get cachedUserDistances =>
      $$CachedUserDistancesTableTableManager(_db, _db.cachedUserDistances);
  $$CachedProfileViewCountsTableTableManager get cachedProfileViewCounts =>
      $$CachedProfileViewCountsTableTableManager(
        _db,
        _db.cachedProfileViewCounts,
      );
  $$CachedAppLanguagesTableTableManager get cachedAppLanguages =>
      $$CachedAppLanguagesTableTableManager(_db, _db.cachedAppLanguages);
}
