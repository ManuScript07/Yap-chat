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
  BoolColumn get yandexAvatarDisabled =>
      boolean().withDefault(const Constant(false))();
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
  TextColumn get peerDisplayNameSearch =>
      text().withDefault(const Constant(''))();
  TextColumn get peerAvatarUrl => text().nullable()();
  TextColumn get peerAvatarStoragePath => text().nullable()();
  TextColumn get lastMessageId => text().nullable()();
  TextColumn get lastMessage => text()();
  TextColumn get lastMessageType => text()();
  DateTimeColumn get lastMessageTime => dateTime()();
  IntColumn get listOrderMicros => integer().nullable()();
  IntColumn get unreadCount => integer()();
  BoolColumn get isLastMessageFromMe => boolean()();
  BoolColumn get isMuted => boolean()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  BoolColumn get showsLastSeen => boolean().withDefault(const Constant(true))();
  BoolColumn get blockedByMe => boolean().withDefault(const Constant(false))();
  BoolColumn get blockedByPeer =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get peerIsGloballyBanned =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, id};
}

/// Membership in a fetched list query is separate from retained chat metadata.
class CachedChatListEntries extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get query => text()();
  TextColumn get chatId => text()();
  IntColumn get activityMicros => integer()();

  @override
  Set<Column> get primaryKey => {ownerUserId, query, chatId};
}

class CachedChatListStates extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get query => text()();
  TextColumn get revision => text()();
  BoolColumn get hasRemotePage =>
      boolean().withDefault(const Constant(false))();
  IntColumn get nextActivityMicros => integer().nullable()();
  TextColumn get nextChatId => text().nullable()();
  DateTimeColumn get checkedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {ownerUserId, query};
}

class CachedChatUnreadTotals extends Table {
  TextColumn get ownerUserId => text()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  IntColumn get unreadTotal => integer().nullable()();
  DateTimeColumn get checkedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {ownerUserId};
}

class CachedMessages extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get id => text()();
  TextColumn get chatId => text()();
  TextColumn get senderId => text()();
  TextColumn get messageText => text()();
  DateTimeColumn get timestamp => dateTime()();
  // Drift's DateTime storage is second-resolution. Server pagination compares
  // (created_at, id), so preserve microseconds independently of display dates.
  IntColumn get timestampMicros => integer().withDefault(const Constant(0))();
  BoolColumn get hasExactTimestamp =>
      boolean().withDefault(const Constant(false))();
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

/// Proven contiguous intervals, not a claim that all cached rows are adjacent.
/// Distant reply windows deliberately never create these intervals.
class CachedChatHistoryRanges extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get chatId => text()();
  IntColumn get oldestMicros => integer()();
  TextColumn get oldestId => text()();
  IntColumn get newestMicros => integer()();
  TextColumn get newestId => text()();
  BoolColumn get reachesStart => boolean()();

  @override
  Set<Column> get primaryKey => {ownerUserId, chatId, newestMicros, newestId};
}

class PendingChatOperations extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get id => text()();
  TextColumn get chatId => text()();
  TextColumn get type => text()();
  TextColumn get payloadJson => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// The next time a message operation may be retried. A null value marks an
  /// operation that needs an explicit user retry after automatic attempts are
  /// exhausted. Chat-deletion operations do not use the message scheduler and
  /// deliberately keep this field null.
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, id};
}

/// Only reaction metadata; storing a distant message here never fills a gap in
/// the contiguous message history used by cursor pagination.
class CachedMessageReactionStates extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get messageId => text()();
  TextColumn get chatId => text()();
  IntColumn get version => integer()();
  TextColumn get stateJson => text()();
  @override
  Set<Column> get primaryKey => {ownerUserId, messageId};
}

class PendingMessageReactions extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get messageId => text()();
  TextColumn get chatId => text()();
  TextColumn get operationId => text()();
  TextColumn get code => text().nullable()();
  IntColumn get expectedRevision => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  @override
  Set<Column> get primaryKey => {ownerUserId, messageId};
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

/// Persists the deepest loaded cursor for the paged own-friends feed.
///
/// Cached friend rows themselves remain the page cache. Keeping the cursor in
/// a separate one-row table lets the app retain already downloaded pages
/// across a restart without refetching them.
class CachedFriendListStates extends Table {
  TextColumn get ownerUserId => text()();
  DateTimeColumn get nextFriendsSince => dateTime().nullable()();
  TextColumn get nextFriendId => text().nullable()();
  BoolColumn get hasMore => boolean().withDefault(const Constant(false))();
  IntColumn get totalCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId};
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
  BoolColumn get sharePreciseLocation =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get shareDistance => boolean().withDefault(const Constant(true))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId};
}

class CachedPreciseLocationExclusions extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get viewerUserId => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, viewerUserId};
}

class CachedViewedProfileMetadata extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get targetUserId => text()();
  TextColumn get relationship => text()();
  TextColumn get requestId => text().nullable()();
  IntColumn get friendCount => integer()();
  TextColumn get friendsPreviewJson => text()();
  IntColumn get viewCount => integer()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  BoolColumn get showsLastSeen => boolean()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, targetUserId};
}

class CachedViewedProfileFriends extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get targetUserId => text()();
  TextColumn get friendUserId => text()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get avatarStoragePath => text().nullable()();
  IntColumn get mutualFriendCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, targetUserId, friendUserId};
}

class CachedViewedProfileFriendLists extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get targetUserId => text()();
  BoolColumn get hasMore => boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, targetUserId};
}

class CachedUserDistances extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get targetUserId => text()();
  IntColumn get distanceValue => integer()();
  TextColumn get distanceUnit => text()();
  DateTimeColumn get locationUpdatedAt => dateTime()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, targetUserId};
}

class CachedProfileViewCounts extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get targetUserId => text()();
  IntColumn get viewCount => integer()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ownerUserId, targetUserId};
}

@DataClassName('CachedAppLanguage')
class CachedAppLanguages extends Table {
  TextColumn get ownerUserId => text()();
  TextColumn get languageCode => text()();
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
    CachedMessageReactionStates,
    PendingMessageReactions,
    CachedFriends,
    CachedFriendListStates,
    CachedFriendRequests,
    CachedFriendLocations,
    CachedContactMatches,
    CachedSearchPrivacySettings,
    CachedPreciseLocationExclusions,
    CachedViewedProfileMetadata,
    CachedViewedProfileFriends,
    CachedViewedProfileFriendLists,
    CachedUserDistances,
    CachedProfileViewCounts,
    CachedAppLanguages,
    CachedChatHistoryRanges,
    CachedChatListEntries,
    CachedChatListStates,
    CachedChatUnreadTotals,
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
  int get schemaVersion => 28;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createBlocklistCacheTables();
      await _createChatCacheIndexes();
    },
    onUpgrade: (migrator, from, to) async {
      if (from >= 2 && from < 28) {
        final columns = await customSelect(
          'PRAGMA table_info(cached_chats)',
        ).get();
        if (!columns.any(
          (c) => c.read<String>('name') == 'list_order_micros',
        )) {
          await migrator.addColumn(cachedChats, cachedChats.listOrderMicros);
        }
      }
      if (from < 25) {
        await migrator.createTable(cachedMessageReactionStates);
        await migrator.createTable(pendingMessageReactions);
      }
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
      } else {
        if (from < 12) {
          await migrator.addColumn(
            cachedSearchPrivacySettings,
            cachedSearchPrivacySettings.lastSeenVisibility,
          );
        }
        if (from < 13) {
          await migrator.addColumn(
            cachedSearchPrivacySettings,
            cachedSearchPrivacySettings.sharePreciseLocation,
          );
          await migrator.addColumn(
            cachedSearchPrivacySettings,
            cachedSearchPrivacySettings.shareDistance,
          );
        }
      }
      if (from < 13) {
        await migrator.createTable(cachedPreciseLocationExclusions);
      }
      if (from < 14) {
        await migrator.createTable(cachedAppLanguages);
      }
      if (from < 15) {
        await migrator.createTable(cachedViewedProfileMetadata);
        await migrator.createTable(cachedViewedProfileFriends);
        await migrator.createTable(cachedUserDistances);
        await migrator.createTable(cachedProfileViewCounts);
      }
      if (from < 16) {
        await migrator.createTable(cachedViewedProfileFriendLists);
      }
      if (from < 17) {
        await customStatement('DELETE FROM cached_profile_view_counts');
        await customStatement(
          'UPDATE cached_viewed_profile_metadata SET view_count = 0',
        );
      }
      if (from < 18) {
        final columns = await customSelect(
          'PRAGMA table_info(cached_profiles)',
        ).get();
        if (!columns.any(
          (column) => column.read<String>('name') == 'yandex_avatar_disabled',
        )) {
          await migrator.addColumn(
            cachedProfiles,
            cachedProfiles.yandexAvatarDisabled,
          );
        }
      }
      if (from < 19) {
        await _createBlocklistCacheTables();
      }
      if (from >= 15 && from < 20) {
        await migrator.addColumn(
          cachedViewedProfileFriends,
          cachedViewedProfileFriends.mutualFriendCount,
        );
      }
      if (from >= 16 && from < 20) {
        await migrator.addColumn(
          cachedViewedProfileFriendLists,
          cachedViewedProfileFriendLists.hasMore,
        );
      }
      if (from < 22) {
        final columns = await customSelect(
          'PRAGMA table_info(cached_chats)',
        ).get();
        final names = columns
            .map((column) => column.read<String>('name'))
            .toSet();
        if (!names.contains('blocked_by_me')) {
          await migrator.addColumn(cachedChats, cachedChats.blockedByMe);
        }
        if (!names.contains('blocked_by_peer')) {
          await migrator.addColumn(cachedChats, cachedChats.blockedByPeer);
        }
        if (!names.contains('peer_is_globally_banned')) {
          await migrator.addColumn(
            cachedChats,
            cachedChats.peerIsGloballyBanned,
          );
        }
      }
      if (from < 23) {
        await migrator.createTable(cachedFriendListStates);
      }
      if (from < 24) {
        // Some development builds already carried the outbox columns before
        // the schema version was advanced. Inspect the physical table so an
        // upgrade from one of those builds remains idempotent instead of
        // failing before the application can open its local cache.
        final columns = await customSelect(
          'PRAGMA table_info(pending_chat_operations)',
        ).get();
        final names = columns
            .map((column) => column.read<String>('name'))
            .toSet();
        if (!names.contains('next_attempt_at')) {
          await migrator.addColumn(
            pendingChatOperations,
            pendingChatOperations.nextAttemptAt,
          );
        }
        if (!names.contains('last_attempt_at')) {
          await migrator.addColumn(
            pendingChatOperations,
            pendingChatOperations.lastAttemptAt,
          );
        }
        // Existing message operations used to be retried only while their
        // conversation was open. Make them due once after the upgrade rather
        // than silently leaving them in the old queue forever.
        await customStatement('''
          UPDATE pending_chat_operations
          SET next_attempt_at = created_at
          WHERE type IN ('text', 'image', 'audio', 'location')
            AND next_attempt_at IS NULL
        ''');
      }
      if (from < 26) {
        final columns = await customSelect(
          'PRAGMA table_info(cached_messages)',
        ).get();
        final names = columns.map((c) => c.read<String>('name')).toSet();
        if (!names.contains('timestamp_micros')) {
          await migrator.addColumn(
            cachedMessages,
            cachedMessages.timestampMicros,
          );
          await customStatement(
            'UPDATE cached_messages SET timestamp_micros = timestamp * 1000000',
          );
        }
        if (!names.contains('has_exact_timestamp')) {
          await migrator.addColumn(
            cachedMessages,
            cachedMessages.hasExactTimestamp,
          );
        }
        await customStatement('''
          CREATE TABLE IF NOT EXISTS cached_chat_history_ranges (
            owner_user_id TEXT NOT NULL, chat_id TEXT NOT NULL,
            oldest_micros INTEGER NOT NULL, oldest_id TEXT NOT NULL,
            newest_micros INTEGER NOT NULL, newest_id TEXT NOT NULL,
            reaches_start INTEGER NOT NULL CHECK (reaches_start IN (0, 1)),
            PRIMARY KEY (owner_user_id, chat_id, newest_micros, newest_id)
          )
        ''');
        // Replace, rather than duplicate, the old second-resolution index.
        await customStatement(
          'DROP INDEX IF EXISTS cached_messages_owner_chat_time_idx',
        );
      }
      if (from < 27) {
        final columns = await customSelect(
          'PRAGMA table_info(cached_chats)',
        ).get();
        if (!columns.any(
          (c) => c.read<String>('name') == 'peer_display_name_search',
        )) {
          await migrator.addColumn(
            cachedChats,
            cachedChats.peerDisplayNameSearch,
          );
        }
        for (final table in <TableInfo<Table, dynamic>>[
          cachedChatListEntries,
          cachedChatListStates,
          cachedChatUnreadTotals,
        ]) {
          final exists = await customSelect(
            'SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?',
            variables: [
              Variable<String>('table'),
              Variable<String>(table.actualTableName),
            ],
          ).getSingleOrNull();
          if (exists == null) await migrator.createTable(table);
        }
        // SQLite lower() only folds ASCII. Normalize old names in Dart once,
        // in bounded batches, so Russian offline search matches the server.
        int? rowId;
        while (true) {
          final rows = await customSelect(
            'SELECT rowid AS migration_rowid, peer_display_name FROM cached_chats ${rowId == null ? '' : 'WHERE rowid > ?'} ORDER BY rowid LIMIT 400',
            variables: [if (rowId != null) Variable<int>(rowId)],
          ).get();
          if (rows.isEmpty) break;
          await batch((b) {
            for (final row in rows) {
              b.customStatement(
                'UPDATE cached_chats SET peer_display_name_search = ? WHERE rowid = ?',
                [
                  row.read<String>('peer_display_name').toLowerCase(),
                  row.read<int>('migration_rowid'),
                ],
              );
            }
          });
          rowId = rows.last.read<int>('migration_rowid');
        }
      }
      if (from < 28) {
        // Recover exact known order without inventing remote coverage. A newer
        // displayed pending preview retains its existing place at the top.
        await customStatement('''
          UPDATE cached_chats SET list_order_micros=MAX(cached_chats.last_message_time*1000000,e.activity_micros)
          FROM cached_chat_list_entries e
          WHERE e.owner_user_id=cached_chats.owner_user_id AND e.chat_id=cached_chats.id
            AND e.query='' AND cached_chats.list_order_micros IS NULL
        ''');
      }
    },
    beforeOpen: (details) async {
      // Version 19 was briefly shipped while the blacklist cache schema was
      // being introduced. Keep this idempotent repair here so an existing
      // database carrying that version cannot silently miss the raw tables.
      await _createBlocklistCacheTables();
      await _createChatCacheIndexes();
      if (details.hadUpgrade && details.versionBefore! < 10) {
        // Reclaim pages that previously contained duplicated avatar BLOBs.
        await customStatement('VACUUM');
      }
    },
  );

  Future<void> _createBlocklistCacheTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS cached_blocked_users (
        owner_user_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        username TEXT NOT NULL,
        display_name TEXT NOT NULL,
        avatar_url TEXT,
        avatar_storage_path TEXT,
        blocked_at_ms INTEGER NOT NULL,
        PRIMARY KEY (owner_user_id, user_id)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS cached_blocklist_snapshots (
        owner_user_id TEXT NOT NULL PRIMARY KEY,
        cached_at_ms INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createChatCacheIndexes() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS cached_chats_owner_available_order_idx
      ON cached_chats (owner_user_id, COALESCE(list_order_micros,last_message_time * 1000000) DESC, id DESC)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS cached_chats_owner_peer_idx
      ON cached_chats (owner_user_id, peer_id)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS cached_chats_owner_time_idx
      ON cached_chats (owner_user_id, last_message_time DESC, id DESC)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS cached_chats_owner_name_idx
      ON cached_chats (owner_user_id, peer_display_name_search)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS cached_chats_owner_list_fallback_idx
      ON cached_chats (owner_user_id, (last_message_time * 1000000) DESC, id DESC)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS cached_chat_list_entries_order_idx
      ON cached_chat_list_entries (owner_user_id, query, activity_micros DESC, chat_id DESC)
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS pending_reactions_owner_due_idx ON pending_message_reactions (owner_user_id, next_attempt_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS cached_reactions_owner_chat_idx ON cached_message_reaction_states (owner_user_id, chat_id)',
    );
    await customStatement('''
      CREATE INDEX IF NOT EXISTS cached_messages_owner_chat_cursor_idx
      ON cached_messages (owner_user_id, chat_id, timestamp_micros DESC, id DESC)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS pending_chat_operations_owner_type_chat_idx
      ON pending_chat_operations (owner_user_id, type, chat_id, created_at ASC)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS pending_chat_operations_owner_due_idx
      ON pending_chat_operations (
        owner_user_id, type, next_attempt_at ASC, created_at ASC, id ASC
      )
      WHERE next_attempt_at IS NOT NULL
    ''');
  }

  /// Repairs the raw blacklist cache tables for databases created by an
  /// intermediate version of the application schema.
  Future<void> ensureBlocklistCacheTables() => _createBlocklistCacheTables();
}
