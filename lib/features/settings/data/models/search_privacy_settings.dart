import 'package:equatable/equatable.dart';

/// Privacy switches that control how the current user can be discovered.
///
/// A missing row on the server means the default value (`true`) for every
/// switch. Keeping this model independent from the page makes it possible to
/// add other account settings without coupling them to the UI.
class SearchPrivacySettings extends Equatable {
  const SearchPrivacySettings({
    this.searchByUsername = true,
    this.searchByPhone = true,
    this.searchByName = true,
  });

  final bool searchByUsername;
  final bool searchByPhone;
  final bool searchByName;

  SearchPrivacySettings copyWith({
    bool? searchByUsername,
    bool? searchByPhone,
    bool? searchByName,
  }) => SearchPrivacySettings(
    searchByUsername: searchByUsername ?? this.searchByUsername,
    searchByPhone: searchByPhone ?? this.searchByPhone,
    searchByName: searchByName ?? this.searchByName,
  );

  @override
  List<Object> get props => [searchByUsername, searchByPhone, searchByName];
}
