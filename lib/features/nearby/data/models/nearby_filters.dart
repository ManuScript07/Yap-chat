import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/profile/data/data.dart';

class NearbyFilters extends Equatable {
  const NearbyFilters({
    this.gender,
    this.minimumAge = 18,
    this.maximumAge = 99,
  });

  final ProfileGender? gender;
  final int minimumAge;
  final int maximumAge;

  String get cacheKey =>
      '${gender?.databaseValue ?? 'all'}:$minimumAge:$maximumAge';

  NearbyFilters copyWith({
    ProfileGender? gender,
    int? minimumAge,
    int? maximumAge,
    bool clearGender = false,
  }) => NearbyFilters(
    gender: clearGender ? null : gender ?? this.gender,
    minimumAge: minimumAge ?? this.minimumAge,
    maximumAge: maximumAge ?? this.maximumAge,
  );

  Map<String, Object?> toJson() => {
    'gender': gender?.databaseValue,
    'minimum_age': minimumAge,
    'maximum_age': maximumAge,
  };

  factory NearbyFilters.fromJson(Map<String, dynamic> value) => NearbyFilters(
    gender: switch (value['gender'] as String?) {
      'male' => ProfileGender.male,
      'female' => ProfileGender.female,
      _ => null,
    },
    minimumAge: (value['minimum_age'] as num?)?.toInt() ?? 18,
    maximumAge: (value['maximum_age'] as num?)?.toInt() ?? 99,
  ).normalized();

  NearbyFilters normalized() {
    final minimum = minimumAge.clamp(18, 99).toInt();
    final maximum = maximumAge.clamp(minimum, 99).toInt();
    return NearbyFilters(
      gender: gender,
      minimumAge: minimum,
      maximumAge: maximum,
    );
  }

  @override
  List<Object?> get props => [gender, minimumAge, maximumAge];
}
