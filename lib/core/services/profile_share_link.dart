/// Canonical public link for a YapChat profile.
///
/// The username is intentionally the complete path.  The website serves the
/// landing page at `/`, while Android verifies and hands all one-segment paths
/// to the application.
final class ProfileShareLink {
  const ProfileShareLink._();

  static const host = 'links.yapchat.ru';
  static final _usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');

  static Uri? tryCreate(String username) {
    final normalized = username.trim().toLowerCase();
    if (!_usernamePattern.hasMatch(normalized)) return null;
    return Uri.https(host, '/$normalized');
  }

  static String? tryParse(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() != host ||
        uri.hasQuery ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.length != 1) {
      return null;
    }
    final username = uri.pathSegments.single.trim().toLowerCase();
    return _usernamePattern.hasMatch(username) ? username : null;
  }

  static String invitationText({
    required String invitation,
    required String username,
  }) {
    final link = tryCreate(username);
    return link == null ? invitation : '$invitation\n$link';
  }
}
