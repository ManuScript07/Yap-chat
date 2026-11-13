import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yap_chat/app/profile_share_link_coordinator.dart';

void main() {
  test('waits for authentication before resolving a shared username', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final links = StreamController<Uri>();
    var authenticated = false;
    final resolved = <String>[];
    final opened = <String>[];
    final coordinator = ProfileShareLinkCoordinator(
      preferences: preferences,
      initialUri: () async => null,
      uriStream: links.stream,
      isAuthenticated: () => authenticated,
      resolveUserId: (username) async {
        resolved.add(username);
        return 'profile-id';
      },
      openProfile: (userId) async {
        opened.add(userId);
        return true;
      },
      onError: (_, _, _) {},
    );

    await coordinator.start();
    links.add(Uri.parse('https://links.yapchat.ru/manuscript07'));
    await Future<void>.delayed(Duration.zero);
    expect(resolved, isEmpty);

    authenticated = true;
    coordinator.onAuthenticationOrForegroundChanged();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(resolved, ['manuscript07']);
    expect(opened, ['profile-id']);
    expect(
      preferences.getString('pending_profile_share_link_username'),
      isNull,
    );
    await coordinator.dispose();
    await links.close();
  });
}
