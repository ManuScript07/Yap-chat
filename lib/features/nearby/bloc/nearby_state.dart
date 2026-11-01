import 'package:equatable/equatable.dart';
import 'package:yap_chat/features/nearby/data/data.dart';

enum NearbyStatus {
  initial,
  loading,
  ready,
  failure,
  locationRequired,
  visibilityDisabled,
}

enum NearbyLocationIssue {
  denied,
  permanentlyDenied,
  serviceDisabled,
  unavailable,
}

class NearbyState extends Equatable {
  const NearbyState({
    this.status = NearbyStatus.initial,
    this.filters = const NearbyFilters(),
    this.people = const [],
    this.hasMore = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.isVisibilitySaving = false,
    this.visibilityFeedbackId = 0,
    this.locationIssue,
    this.locationFeedbackId = 0,
    this.rateLimitFeedbackId = 0,
    this.feedRevision = 0,
  });

  final NearbyStatus status;
  final NearbyFilters filters;
  final List<NearbyPerson> people;
  final bool hasMore;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool isVisibilitySaving;
  final int visibilityFeedbackId;
  final NearbyLocationIssue? locationIssue;
  final int locationFeedbackId;
  final int rateLimitFeedbackId;

  /// Changes only when a first-page snapshot replaces the current feed.
  final int feedRevision;

  bool get shouldObscureContent =>
      status == NearbyStatus.visibilityDisabled ||
      status == NearbyStatus.locationRequired ||
      isRefreshing && locationIssue != null;

  NearbyState copyWith({
    NearbyStatus? status,
    NearbyFilters? filters,
    List<NearbyPerson>? people,
    bool? hasMore,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? isVisibilitySaving,
    int? visibilityFeedbackId,
    NearbyLocationIssue? locationIssue,
    bool clearLocationIssue = false,
    int? locationFeedbackId,
    int? rateLimitFeedbackId,
    int? feedRevision,
  }) => NearbyState(
    status: status ?? this.status,
    filters: filters ?? this.filters,
    people: people ?? this.people,
    hasMore: hasMore ?? this.hasMore,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    isVisibilitySaving: isVisibilitySaving ?? this.isVisibilitySaving,
    visibilityFeedbackId: visibilityFeedbackId ?? this.visibilityFeedbackId,
    locationIssue: clearLocationIssue
        ? null
        : locationIssue ?? this.locationIssue,
    locationFeedbackId: locationFeedbackId ?? this.locationFeedbackId,
    rateLimitFeedbackId: rateLimitFeedbackId ?? this.rateLimitFeedbackId,
    feedRevision: feedRevision ?? this.feedRevision,
  );

  @override
  List<Object?> get props => [
    status,
    filters,
    people,
    hasMore,
    isRefreshing,
    isLoadingMore,
    isVisibilitySaving,
    visibilityFeedbackId,
    locationIssue,
    locationFeedbackId,
    rateLimitFeedbackId,
    feedRevision,
  ];
}
