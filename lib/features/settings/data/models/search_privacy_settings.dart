import 'package:equatable/equatable.dart';

/// A single discovery setting. This is shared by the UI and repository so a
/// write never needs to send a stale snapshot of the other settings.
enum SearchPrivacySettingKey { username, phone, name }

/// Controls who may receive the precise last-seen timestamp.
enum LastSeenVisibility { all, friends, nobody }

/// Account privacy settings shared by search and chat surfaces.
///
/// A missing row on the server means the default value (`true`) for every
/// switch. Keeping this model independent from the page makes it possible to
/// add other account settings without coupling them to the UI.
class SearchPrivacySettings extends Equatable {
  const SearchPrivacySettings({
    this.searchByUsername = true,
    this.searchByPhone = true,
    this.searchByName = true,
    this.lastSeenVisibility = LastSeenVisibility.all,
  });

  final bool searchByUsername;
  final bool searchByPhone;
  final bool searchByName;
  final LastSeenVisibility lastSeenVisibility;

  SearchPrivacySettings copyWith({
    bool? searchByUsername,
    bool? searchByPhone,
    bool? searchByName,
    LastSeenVisibility? lastSeenVisibility,
  }) => SearchPrivacySettings(
    searchByUsername: searchByUsername ?? this.searchByUsername,
    searchByPhone: searchByPhone ?? this.searchByPhone,
    searchByName: searchByName ?? this.searchByName,
    lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
  );

  bool valueFor(SearchPrivacySettingKey key) => switch (key) {
    SearchPrivacySettingKey.username => searchByUsername,
    SearchPrivacySettingKey.phone => searchByPhone,
    SearchPrivacySettingKey.name => searchByName,
  };

  SearchPrivacySettings withValue(SearchPrivacySettingKey key, bool value) =>
      switch (key) {
        SearchPrivacySettingKey.username => copyWith(searchByUsername: value),
        SearchPrivacySettingKey.phone => copyWith(searchByPhone: value),
        SearchPrivacySettingKey.name => copyWith(searchByName: value),
      };

  @override
  List<Object> get props => [
    searchByUsername,
    searchByPhone,
    searchByName,
    lastSeenVisibility,
  ];
}
