# Implementation Plan - Bottom Navigation with Auto Route

Implement a professional Bottom Navigation Bar using `auto_route` with three sections: Chats, Friends, and Profile.

## User Review Required

> [!IMPORTANT]
> This change introduces `auto_route` and `build_runner`. After the files are created, you will need to run the code generator:
> `flutter pub run build_runner build --delete-conflicting-outputs`

## Proposed Changes

### Dependencies
#### [MODIFY] [pubspec.yaml](file:///D:/StudioProjects/Yap_chat/pubspec.yaml)
- Add `auto_route` to dependencies.
- Add `auto_route_generator` and `build_runner` to dev_dependencies.

### Friends Feature
#### [NEW] [friends_page.dart](file:///D:/StudioProjects/Yap_chat/lib/features/friends/view/friends_page.dart)
- Create a placeholder `FriendsPage` widget.
#### [NEW] [view.dart](file:///D:/StudioProjects/Yap_chat/lib/features/friends/view/view.dart)
- Export `friends_page.dart`.
#### [NEW] [friends.dart](file:///D:/StudioProjects/Yap_chat/lib/features/friends/friends.dart)
- Export `view/view.dart`.

### Profile Feature
#### [NEW] [profile_page.dart](file:///D:/StudioProjects/Yap_chat/lib/features/profile/view/profile_page.dart)
- Create a placeholder `ProfilePage` widget.
#### [NEW] [view.dart](file:///D:/StudioProjects/Yap_chat/lib/features/profile/view/view.dart)
- Export `profile_page.dart`.
#### [NEW] [profile.dart](file:///D:/StudioProjects/Yap_chat/lib/features/profile/profile.dart)
- Export `view/view.dart`.

### Main (Shell) Feature
#### [NEW] [main_page.dart](file:///D:/StudioProjects/Yap_chat/lib/features/main/view/main_page.dart)
- Implement `MainPage` using `AutoTabsScaffold` to manage bottom navigation.
#### [NEW] [view.dart](file:///D:/StudioProjects/Yap_chat/lib/features/main/view/view.dart)
- Export `main_page.dart`.
#### [NEW] [main.dart](file:///D:/StudioProjects/Yap_chat/lib/features/main/main.dart)
- Export `view/view.dart`.

### Routing
#### [MODIFY] [router.dart](file:///D:/StudioProjects/Yap_chat/lib/router/router.dart)
- Replace standard routes with `AppRouter` class using `@AutoRouterConfig`.
- Define nested routes for `MainPage`.

### Application Entry
#### [MODIFY] [yap_chat_app.dart](file:///D:/StudioProjects/Yap_chat/lib/yap_chat_app.dart)
- Update `MaterialApp.router` to use `AppRouter`.

## Verification Plan

### Automated Tests
- N/A (UI placeholders)

### Manual Verification
- Run `build_runner` and ensure `router.gr.dart` is generated.
- Launch the app and verify the Bottom Navigation Bar allows switching between Chats, Friends, and Profile.
- Verify that each page displays its corresponding placeholder content.
