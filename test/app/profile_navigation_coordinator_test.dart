import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/app/profile_navigation_coordinator.dart';

void main() {
  test('opens a queued profile only once', () async {
    final openedUserIds = <String>[];
    final coordinator = ProfileNavigationCoordinator(
      navigateToProfile: (userId) async => openedUserIds.add(userId),
      isProfileVisible: (_) => false,
      isActive: () => true,
      onError: (_, _, _) {},
      waitForFrame: () async {},
    );

    await Future.wait([coordinator.open('user'), coordinator.open('user')]);

    expect(openedUserIds, ['user']);
  });

  test('does not navigate to an already visible profile', () async {
    var opened = false;
    final coordinator = ProfileNavigationCoordinator(
      navigateToProfile: (_) async => opened = true,
      isProfileVisible: (userId) => userId == 'user',
      isActive: () => true,
      onError: (_, _, _) {},
      waitForFrame: () async {},
    );

    await coordinator.open('user');

    expect(opened, isFalse);
  });

  test('serializes profile opens from different notification taps', () async {
    final openedUserIds = <String>[];
    final coordinator = ProfileNavigationCoordinator(
      navigateToProfile: (userId) async => openedUserIds.add(userId),
      isProfileVisible: (_) => false,
      isActive: () => true,
      onError: (_, _, _) {},
      waitForFrame: () async {},
    );

    await Future.wait([coordinator.open('first'), coordinator.open('second')]);

    expect(openedUserIds, ['first', 'second']);
  });
}
