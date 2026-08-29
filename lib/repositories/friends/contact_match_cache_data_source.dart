import 'package:drift/drift.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/data/data.dart';

class ContactMatchCacheRecord {
  const ContactMatchCacheRecord({
    required this.isRegistered,
    required this.checkedAt,
    this.candidate,
  });

  final bool isRegistered;
  final DateTime checkedAt;
  final FriendCandidate? candidate;
}

/// Keeps manual number lookup entries physically separate from address-book
/// matching, while retaining the same opaque HMAC storage format.
enum PhoneMatchCacheScope { contacts, manualSearch }

class ContactMatchCachePolicy {
  const ContactMatchCachePolicy({
    this.positiveTtl = const Duration(hours: 24),
    this.negativeTtl = const Duration(hours: 2),
  });

  final Duration positiveTtl;
  final Duration negativeTtl;

  bool shouldRefresh(ContactMatchCacheRecord? record, DateTime now) {
    if (record == null || (record.isRegistered && record.candidate == null)) {
      return true;
    }
    final ttl = record.isRegistered ? positiveTtl : negativeTtl;
    return now.toUtc().difference(record.checkedAt.toUtc()) >= ttl;
  }
}

class ContactMatchCacheDataSource {
  const ContactMatchCacheDataSource({
    required AppDatabase database,
    required String Function() userIdProvider,
    required IContactCacheKeyService keyService,
  }) : _database = database,
       _userIdProvider = userIdProvider,
       _keyService = keyService;

  final AppDatabase _database;
  final String Function() _userIdProvider;
  final IContactCacheKeyService _keyService;
  static const _manualKeyPrefix = 'manual-search:';

  Future<Map<String, ContactMatchCacheRecord>> read(
    Iterable<String> phoneNumbers, {
    String? ownerUserId,
    PhoneMatchCacheScope scope = PhoneMatchCacheScope.contacts,
  }) async {
    final keysByPhone = await _keysByPhone(phoneNumbers, scope: scope);
    if (keysByPhone.isEmpty) return const {};
    final phonesByKey = {
      for (final entry in keysByPhone.entries) entry.value: entry.key,
    };
    final owner = ownerUserId ?? _userIdProvider();
    final rows = <CachedContactMatch>[];
    final keys = phonesByKey.keys.toList(growable: false);
    const batchSize = 500;
    for (var offset = 0; offset < keys.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, keys.length);
      final query = _database.select(_database.cachedContactMatches)
        ..where(
          (table) =>
              table.ownerUserId.equals(owner) &
              table.phoneKey.isIn(keys.sublist(offset, end)),
        );
      rows.addAll(await query.get());
    }
    return {
      for (final row in rows)
        if (phonesByKey[row.phoneKey] case final phone?)
          phone: ContactMatchCacheRecord(
            isRegistered: row.isRegistered,
            checkedAt: row.checkedAt,
            candidate: _mapCandidate(row),
          ),
    };
  }

  Future<void> writeResults({
    required Iterable<String> checkedPhoneNumbers,
    required Map<String, FriendCandidate> matches,
    required DateTime checkedAt,
    String? ownerUserId,
    PhoneMatchCacheScope scope = PhoneMatchCacheScope.contacts,
  }) async {
    final keysByPhone = await _keysByPhone(
      checkedPhoneNumbers,
      scope: scope,
    );
    final owner = ownerUserId ?? _userIdProvider();
    final rows = keysByPhone.entries.map((entry) {
      final candidate = matches[entry.key];
      return CachedContactMatchesCompanion.insert(
        ownerUserId: owner,
        phoneKey: entry.value,
        isRegistered: candidate != null,
        candidateId: Value(candidate?.id),
        username: Value(candidate?.username),
        displayName: Value(candidate?.displayName),
        avatarUrl: Value(candidate?.avatarUrl),
        avatarStoragePath: Value(candidate?.avatarStoragePath),
        friendCount: Value(candidate?.friendCount),
        checkedAt: checkedAt.toUtc(),
      );
    });
    await _database.batch(
      (batch) => batch.insertAll(
        _database.cachedContactMatches,
        rows,
        mode: InsertMode.insertOrReplace,
      ),
    );
  }

  Future<void> retainOnly(
    Iterable<String> phoneNumbers, {
    String? ownerUserId,
    PhoneMatchCacheScope scope = PhoneMatchCacheScope.contacts,
  }) async {
    final keys = (await _keysByPhone(phoneNumbers, scope: scope)).values
        .toSet();
    final owner = ownerUserId ?? _userIdProvider();
    final existing = await (_database.select(
      _database.cachedContactMatches,
    )..where((table) => table.ownerUserId.equals(owner))).get();
    final obsoleteKeys = existing
        .map((row) => row.phoneKey)
        .where(
          (key) =>
              _belongsToScope(key, scope) && !keys.contains(key),
        )
        .toList(growable: false);
    const batchSize = 500;
    await _database.transaction(() async {
      for (var offset = 0; offset < obsoleteKeys.length; offset += batchSize) {
        final end = (offset + batchSize).clamp(0, obsoleteKeys.length);
        await (_database.delete(_database.cachedContactMatches)..where(
              (table) =>
                  table.ownerUserId.equals(owner) &
                  table.phoneKey.isIn(obsoleteKeys.sublist(offset, end)),
            ))
            .go();
      }
    });
  }

  /// Adds known positive matches without changing other contact results.
  Future<void> writeMatches({
    required Map<String, FriendCandidate> matches,
    required DateTime checkedAt,
    String? ownerUserId,
    PhoneMatchCacheScope scope = PhoneMatchCacheScope.contacts,
  }) async {
    if (matches.isEmpty) return;
    final keysByPhone = await _keysByPhone(matches.keys, scope: scope);
    final owner = ownerUserId ?? _userIdProvider();
    final rows = keysByPhone.entries.map((entry) {
      final candidate = matches[entry.key]!;
      return CachedContactMatchesCompanion.insert(
        ownerUserId: owner,
        phoneKey: entry.value,
        isRegistered: true,
        candidateId: Value(candidate.id),
        username: Value(candidate.username),
        displayName: Value(candidate.displayName),
        avatarUrl: Value(candidate.avatarUrl),
        avatarStoragePath: Value(candidate.avatarStoragePath),
        friendCount: Value(candidate.friendCount),
        checkedAt: checkedAt.toUtc(),
      );
    });
    await _database.batch(
      (batch) => batch.insertAll(
        _database.cachedContactMatches,
        rows,
        mode: InsertMode.insertOrReplace,
      ),
    );
  }

  /// Manual number lookups expire quickly and are not part of address-book
  /// retention. Pruning them keeps both disk usage and point reads bounded.
  Future<void> pruneExpiredManualSearchMatches({
    required DateTime expiredBefore,
    String? ownerUserId,
  }) async {
    final owner = ownerUserId ?? _userIdProvider();
    final manualRows = await (_database.select(_database.cachedContactMatches)
          ..where((table) => table.ownerUserId.equals(owner)))
        .get();
    final expiredKeys = manualRows
        .where(
          (row) =>
              _belongsToScope(row.phoneKey, PhoneMatchCacheScope.manualSearch) &&
              !row.checkedAt.isAfter(expiredBefore.toUtc()),
        )
        .map((row) => row.phoneKey)
        .toList(growable: false);
    const batchSize = 500;
    for (var offset = 0; offset < expiredKeys.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, expiredKeys.length);
      await (_database.delete(_database.cachedContactMatches)..where(
            (table) =>
                table.ownerUserId.equals(owner) &
                table.phoneKey.isIn(expiredKeys.sublist(offset, end)),
          ))
          .go();
    }
  }

  Future<Map<String, String>> _keysByPhone(
    Iterable<String> phoneNumbers, {
    required PhoneMatchCacheScope scope,
  }) async {
    final unique = phoneNumbers.toSet();
    final entries = await Future.wait(
      unique.map(
        (phone) async => MapEntry(
          phone,
          _keyForScope(
            await _keyService.createKey(phone),
            scope,
          ),
        ),
      ),
    );
    return Map.fromEntries(entries);
  }

  String _keyForScope(String phoneKey, PhoneMatchCacheScope scope) =>
      scope == PhoneMatchCacheScope.contacts
      ? phoneKey
      : '$_manualKeyPrefix$phoneKey';

  bool _belongsToScope(String phoneKey, PhoneMatchCacheScope scope) =>
      scope == PhoneMatchCacheScope.manualSearch
      ? phoneKey.startsWith(_manualKeyPrefix)
      : !phoneKey.startsWith(_manualKeyPrefix);

  FriendCandidate? _mapCandidate(CachedContactMatch row) {
    if (!row.isRegistered ||
        row.candidateId == null ||
        row.username == null ||
        row.displayName == null) {
      return null;
    }
    return FriendCandidate(
      id: row.candidateId!,
      username: row.username!,
      displayName: row.displayName!,
      avatarUrl: row.avatarUrl,
      avatarStoragePath: row.avatarStoragePath,
      friendCount: row.friendCount,
      relationship: FriendRelationship.none,
    );
  }
}
