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

@DriftDatabase(tables: [CachedProfiles])
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
  int get schemaVersion => 1;
}
