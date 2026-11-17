import 'profile_share_link.dart';

final class FeedPostLink {
  const FeedPostLink._();

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static bool isValidId(String id) => _uuid.hasMatch(id);

  static Uri create(String id) => Uri.https(ProfileShareLink.host, '/post/$id');

  static bool matchesPath(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == ProfileShareLink.host &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      uri.pathSegments.firstOrNull == 'post' &&
      uri.pathSegments.length >= 2;

  static String? tryParse(Uri uri) {
    if (!matchesPath(uri) ||
        uri.pathSegments.length != 2 ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final id = uri.pathSegments.last.toLowerCase();
    return isValidId(id) ? id : null;
  }
}
