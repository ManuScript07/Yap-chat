import 'package:yap_chat/features/nearby/data/data.dart';
import 'package:yap_chat/repositories/nearby/nearby_cache_data_source.dart';

abstract interface class INearbyRepository {
  Future<NearbyFilters> getFilters();
  Future<void> saveFilters(NearbyFilters filters);
  Future<NearbyCacheSnapshot?> getCachedFeed(NearbyFilters filters);
  Future<NearbyCacheSnapshot> refreshFeed(NearbyFilters filters);
  Future<NearbyCacheSnapshot?> loadMore(NearbyFilters filters);
  Future<void> removeCachedPeople(Set<String> userIds);
  Future<String?> resolveAvatar(NearbyPerson person);
  Future<void> clearUserCache(String userId);
}
