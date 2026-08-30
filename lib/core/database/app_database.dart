import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class CachedProfiles extends Table {
  TextColumn get userId => text()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get avatarStoragePath => text().nullable()();
  BlobColumn get avatarBytes => blob().nullable()();
  DateTimeColumn get avatarUpdatedAt => dateTime().nullable()();
  TextColumn get gender => text()();
  TextColumn get bio => text()();
  BoolColumn get onboardingCompleted => boolean()();
  DateTimeColumn get termsAcceptedAt => dateTime().nullable()();
  DateTimeColumn get privacyAcceptedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId};
}

class CachedProfilePhotos extends Table {
  TextColumn get userId => text()();
  IntColumn get position => integer()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get storagePath => text().nullable()();
  BlobColumn get bytes => blob().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId, position};
}

class CachedChats extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get id => text()();
  TextColumn get peerId => text()();
  TextColumn get peerUsername => text()();
  TextColumn get peerDisplayName => text()();
  TextColumn get peerAvatarUrl => text().nullable()();
  TextColumn get peerAvatarStoragePath => text().nullable()();
  TextColumn get lastMessageId => text().nullable()();
  TextColumn get lastMessage => text()();
  TextColumn get lastMessageType => text()();
  DateTimeColumn get lastMessageTime => dateTime()();
  IntColumn get unreadCount => integer()();
  BoolColumn get isLastMessageFromMe => boolean()();
  BoolColumn get isMuted => boolean()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  BoolColumn get showsLastSeen => boolean().withDefault(const Constant(true))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, id};
}

class CachedMessages extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get id => text()();
  TextColumn get chatId => text()();
  TextColumn get senderId => text()();
  TextColumn get messageText => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get status => text()();
  TextColumn get type => text()();
  TextColumn get mediaUrlsJson => text()();
  TextColumn get mediaStoragePathsJson => text()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get audioUrl => text().nullable()();
  TextColumn get audioStoragePath => text().nullable()();
  IntColumn get audioDurationMs => integer().nullable()();
  TextColumn get audioWaveformJson => text()();
  TextColumn get replyMessageId => text().nullable()();
  TextColumn get replySenderId => text().nullable()();
  TextColumn get replyType => text().nullable()();
  TextColumn get replyText => text().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  BoolColumn get isPending => boolean()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, id};
}

class PendingChatOperations extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get id => text()();
  TextColumn get chatId => text()();
  TextColumn get type => text()();
  TextColumn get payloadJson => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, id};
}

class CachedFriends extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get userId => text()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get avatarStoragePath => text().nullable()();
  DateTimeColumn get friendsSince => dateTime()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, userId};
}

class CachedFriendRequests extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get requestId => text()();
  TextColumn get peerId => text()();
  TextColumn get peerUsername => text()();
  TextColumn get peerDisplayName => text()();
  TextColumn get peerAvatarUrl => text().nullable()();
  TextColumn get peerAvatarStoragePath => text().nullable()();
  IntColumn get peerFriendCount => integer().nullable()();
  TextColumn get direction => text()();
  DateTimeColumn get requestedAt => dateTime()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, requestId};
}

@DataClassName('CachedFriendLocation')
class CachedFriendLocations extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get friendUserId => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  IntColumn get locationUpdatedAtMs => integer()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, friendUserId};
}

@DataClassName('CachedContactMatch')
class CachedContactMatches extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get phoneKey => text()();
  BoolColumn get isRegistered => boolean()();
  TextColumn get candidateId => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get avatarStoragePath => text().nullable()();
  IntColumn get friendCount => integer().nullable()();
  DateTimeColumn get checkedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, phoneKey};
}

@DataClassName('CachedSearchPrivacySetting')
class CachedSearchPrivacySettings extends Table {
  TextColumn get ownerUserId => text()();
  BoolColumn get searchByUsername => boolean()();
  BoolColumn get searchByPhone => boolean()();
  BoolColumn get searchByName => boolean()();
  TextColumn get lastSeenVisibility =>
      text().withDefault(const Constant('all'))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId};
}

@DriftDatabase(
  tables: [
    CachedProfiles,
    CachedProfilePhotos,
    CachedChats,
    CachedMessages,
    PendingChatOperations,
    CachedFriends,
    CachedFriendRequests,
    CachedFriendLocations,
    CachedContactMatches,
    CachedSearchPrivacySettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({String name = 'yap_chat_cache'})
    : super(
        driftDatabase(
          name: name,
          native: const DriftNativeOptions(shareAcrossIsolates: true),
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(cachedChats);
        await migrator.createTable(cachedMessages);
        await migrator.createTable(pendingChatOperations);
      }
      if (from >= 2 && from < 3) {
        await migrator.addColumn(cachedChats, cachedChats.lastMessageId);
      }
      if (from < 4) {
        await migrator.addColumn(cachedChats, cachedChats.lastSeenAt);
      }
      if (from < 5) {
        await migrator.addColumn(cachedChats, cachedChats.showsLastSeen);
      }
      if (from < 6) {
        await migrator.createTable(cachedFriends);
        await migrator.createTable(cachedFriendRequests);
      }
      if (from < 7) {
        await migrator.createTable(cachedContactMatches);
      }
      if (from < 8) {
        await migrator.createTable(cachedFriendLocations);
      }
      if (from < 9) {
        await migrator.addColumn(cachedProfiles, cachedProfiles.createdAt);
        await migrator.createTable(cachedProfilePhotos);
      }
      if (from < 10) {
        await customStatement('UPDATE cached_profiles SET avatar_bytes = NULL');
      }
      if (from < 11) {
        await migrator.createTable(cachedSearchPrivacySettings);
      }
      if (from < 12) {
        await migrator.addColumn(
          cachedSearchPrivacySettings,
          cachedSearchPrivacySettings.lastSeenVisibility,
        );
      }
    },
    beforeOpen: (details) async {
      if (details.hadUpgrade && details.versionBefore! < 10) {
        // Reclaim pages that previously contained duplicated avatar BLOBs.
        await customStatement('VACUUM');
      }
    },
  );
}
