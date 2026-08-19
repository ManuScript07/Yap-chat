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
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId};
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

@DriftDatabase(
  tables: [CachedProfiles, CachedChats, CachedMessages, PendingChatOperations],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'yap_chat_cache',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 3;

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
    },
  );
}
