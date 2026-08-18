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
    gender,
    bio,
    onboardingCompleted,
    termsAcceptedAt,
    privacyAcceptedAt,
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
  final String gender;
  final String bio;
  final bool onboardingCompleted;
  final DateTime? termsAcceptedAt;
  final DateTime? privacyAcceptedAt;
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
    required this.gender,
    required this.bio,
    required this.onboardingCompleted,
    this.termsAcceptedAt,
    this.privacyAcceptedAt,
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
    map['gender'] = Variable<String>(gender);
    map['bio'] = Variable<String>(bio);
    map['onboarding_completed'] = Variable<bool>(onboardingCompleted);
    if (!nullToAbsent || termsAcceptedAt != null) {
      map['terms_accepted_at'] = Variable<DateTime>(termsAcceptedAt);
    }
    if (!nullToAbsent || privacyAcceptedAt != null) {
      map['privacy_accepted_at'] = Variable<DateTime>(privacyAcceptedAt);
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
      gender: Value(gender),
      bio: Value(bio),
      onboardingCompleted: Value(onboardingCompleted),
      termsAcceptedAt: termsAcceptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(termsAcceptedAt),
      privacyAcceptedAt: privacyAcceptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(privacyAcceptedAt),
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
      gender: serializer.fromJson<String>(json['gender']),
      bio: serializer.fromJson<String>(json['bio']),
      onboardingCompleted: serializer.fromJson<bool>(
        json['onboardingCompleted'],
      ),
      termsAcceptedAt: serializer.fromJson<DateTime?>(json['termsAcceptedAt']),
      privacyAcceptedAt: serializer.fromJson<DateTime?>(
        json['privacyAcceptedAt'],
      ),
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
      'gender': serializer.toJson<String>(gender),
      'bio': serializer.toJson<String>(bio),
      'onboardingCompleted': serializer.toJson<bool>(onboardingCompleted),
      'termsAcceptedAt': serializer.toJson<DateTime?>(termsAcceptedAt),
      'privacyAcceptedAt': serializer.toJson<DateTime?>(privacyAcceptedAt),
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
    String? gender,
    String? bio,
    bool? onboardingCompleted,
    Value<DateTime?> termsAcceptedAt = const Value.absent(),
    Value<DateTime?> privacyAcceptedAt = const Value.absent(),
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
    gender: gender ?? this.gender,
    bio: bio ?? this.bio,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    termsAcceptedAt: termsAcceptedAt.present
        ? termsAcceptedAt.value
        : this.termsAcceptedAt,
    privacyAcceptedAt: privacyAcceptedAt.present
        ? privacyAcceptedAt.value
        : this.privacyAcceptedAt,
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
          ..write('gender: $gender, ')
          ..write('bio: $bio, ')
          ..write('onboardingCompleted: $onboardingCompleted, ')
          ..write('termsAcceptedAt: $termsAcceptedAt, ')
          ..write('privacyAcceptedAt: $privacyAcceptedAt, ')
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
    gender,
    bio,
    onboardingCompleted,
    termsAcceptedAt,
    privacyAcceptedAt,
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
          other.gender == this.gender &&
          other.bio == this.bio &&
          other.onboardingCompleted == this.onboardingCompleted &&
          other.termsAcceptedAt == this.termsAcceptedAt &&
          other.privacyAcceptedAt == this.privacyAcceptedAt &&
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
  final Value<String> gender;
  final Value<String> bio;
  final Value<bool> onboardingCompleted;
  final Value<DateTime?> termsAcceptedAt;
  final Value<DateTime?> privacyAcceptedAt;
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
    this.gender = const Value.absent(),
    this.bio = const Value.absent(),
    this.onboardingCompleted = const Value.absent(),
    this.termsAcceptedAt = const Value.absent(),
    this.privacyAcceptedAt = const Value.absent(),
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
    required String gender,
    required String bio,
    required bool onboardingCompleted,
    this.termsAcceptedAt = const Value.absent(),
    this.privacyAcceptedAt = const Value.absent(),
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
    Expression<String>? gender,
    Expression<String>? bio,
    Expression<bool>? onboardingCompleted,
    Expression<DateTime>? termsAcceptedAt,
    Expression<DateTime>? privacyAcceptedAt,
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
      if (gender != null) 'gender': gender,
      if (bio != null) 'bio': bio,
      if (onboardingCompleted != null)
        'onboarding_completed': onboardingCompleted,
      if (termsAcceptedAt != null) 'terms_accepted_at': termsAcceptedAt,
      if (privacyAcceptedAt != null) 'privacy_accepted_at': privacyAcceptedAt,
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
    Value<String>? gender,
    Value<String>? bio,
    Value<bool>? onboardingCompleted,
    Value<DateTime?>? termsAcceptedAt,
    Value<DateTime?>? privacyAcceptedAt,
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
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      privacyAcceptedAt: privacyAcceptedAt ?? this.privacyAcceptedAt,
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
          ..write('gender: $gender, ')
          ..write('bio: $bio, ')
          ..write('onboardingCompleted: $onboardingCompleted, ')
          ..write('termsAcceptedAt: $termsAcceptedAt, ')
          ..write('privacyAcceptedAt: $privacyAcceptedAt, ')
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
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cachedProfiles];
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
      required String gender,
      required String bio,
      required bool onboardingCompleted,
      Value<DateTime?> termsAcceptedAt,
      Value<DateTime?> privacyAcceptedAt,
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
      Value<String> gender,
      Value<String> bio,
      Value<bool> onboardingCompleted,
      Value<DateTime?> termsAcceptedAt,
      Value<DateTime?> privacyAcceptedAt,
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
                Value<String> gender = const Value.absent(),
                Value<String> bio = const Value.absent(),
                Value<bool> onboardingCompleted = const Value.absent(),
                Value<DateTime?> termsAcceptedAt = const Value.absent(),
                Value<DateTime?> privacyAcceptedAt = const Value.absent(),
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
                gender: gender,
                bio: bio,
                onboardingCompleted: onboardingCompleted,
                termsAcceptedAt: termsAcceptedAt,
                privacyAcceptedAt: privacyAcceptedAt,
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
                required String gender,
                required String bio,
                required bool onboardingCompleted,
                Value<DateTime?> termsAcceptedAt = const Value.absent(),
                Value<DateTime?> privacyAcceptedAt = const Value.absent(),
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
                gender: gender,
                bio: bio,
                onboardingCompleted: onboardingCompleted,
                termsAcceptedAt: termsAcceptedAt,
                privacyAcceptedAt: privacyAcceptedAt,
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedProfilesTableTableManager get cachedProfiles =>
      $$CachedProfilesTableTableManager(_db, _db.cachedProfiles);
}
