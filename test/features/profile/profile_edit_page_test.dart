import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/data/data.dart';
import 'package:yap_chat/features/profile/profile.dart';
import 'package:yap_chat/features/profile/widgets/widgets.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/profile/profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/RobotoFlex-VF.ttf'))).load();
  });

  for (final size in [const Size(320, 720), const Size(780, 390)]) {
    testWidgets(
      'editor photo and add tile keep the gentler profile radius $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = _PendingProfileRepository();
        final cubit = ProfileMutationCubit(repository: repository);
        addTearDown(cubit.close);
        await _pumpEditorHost(
          tester,
          mutationCubit: cubit,
          profile: _profile(username: 'owner').copyWith(
            photos: [
              ProfilePhoto(
                position: 0,
                storagePath: 'owner/avatar.png',
                bytes: File('assets/logo/logo_yap_chat.png').readAsBytesSync(),
              ),
            ],
          ),
        );
        await tester.tap(find.text('open editor'));
        await tester.pumpAndSettle();
        final clip = tester.widget<ClipRRect>(
          find
              .ancestor(
                of: find.byType(ProfilePhotoImage),
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        expect(
          clip.borderRadius.resolve(TextDirection.ltr).topLeft.x,
          closeTo(22.4, 1e-9),
        );
        final addTile = find.byWidgetPredicate(
          (w) =>
              w is Material &&
              w.borderRadius == BorderRadius.circular(112 * .2),
        );
        expect(addTile, findsOneWidget);
        expect(tester.getSize(addTile), const Size(112, 112));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'does not pop the profile route twice when a background save finishes',
    (tester) async {
      final repository = _PendingProfileRepository();
      addTearDown(() {
        if (!repository.isCompleted) {
          repository.complete(_profile(username: 'before', bio: 'Saved bio'));
        }
      });
      final mutationCubit = ProfileMutationCubit(repository: repository);
      final profile = _profile(username: 'before');
      mutationCubit.setAuthenticatedUser(profile.id);

      await _pumpEditorHost(
        tester,
        mutationCubit: mutationCubit,
        profile: profile,
      );
      await tester.tap(find.text('open editor'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'Saved bio');
      await tester.tap(find.text('save'));
      await tester.pump();

      Navigator.of(tester.element(find.text('edit profile'))).pop();
      repository.complete(_profile(username: 'before', bio: 'Saved bio'));
      await tester.pumpAndSettle();

      expect(find.text('edit profile'), findsNothing);
      expect(find.text('open editor'), findsOneWidget);
    },
  );

  testWidgets('a successful save never navigates without a user action', (
    tester,
  ) async {
    final repository = _PendingProfileRepository();
    final mutationCubit = ProfileMutationCubit(repository: repository);
    final profile = _profile(username: 'before');
    mutationCubit.setAuthenticatedUser(profile.id);

    await _pumpEditorHost(
      tester,
      mutationCubit: mutationCubit,
      profile: profile,
    );
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Saved bio');
    await tester.tap(find.text('save'));
    await tester.pump();

    repository.complete(_profile(username: 'before', bio: 'Saved bio'));
    await tester.pumpAndSettle();

    expect(find.text('edit profile'), findsOneWidget);
    Navigator.of(tester.element(find.text('edit profile'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('edit profile'), findsNothing);
    expect(find.text('open editor'), findsOneWidget);
  });

  testWidgets('treats an already saved mutation as the editor baseline', (
    tester,
  ) async {
    final repository = _PendingProfileRepository();
    final mutationCubit = ProfileMutationCubit(repository: repository);
    final staleProfile = _profile(username: 'before');
    final savedProfile = _profile(username: 'before', bio: 'Saved bio');
    mutationCubit.setAuthenticatedUser(staleProfile.id);
    mutationCubit.submit(
      currentProfile: staleProfile,
      draft: ProfileDraft(
        userId: staleProfile.id,
        displayName: staleProfile.displayName,
        birthDate: staleProfile.birthDate!,
        gender: staleProfile.gender,
        username: staleProfile.username,
        bio: 'Saved bio',
        photos: staleProfile.effectivePhotos,
      ),
    );
    repository.complete(savedProfile);
    await tester.pump();

    await _pumpEditorHost(
      tester,
      mutationCubit: mutationCubit,
      profile: staleProfile,
    );
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'save'),
    );
    expect(saveButton.onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('open editor'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('restores a background save and keeps later edits interactive', (
    tester,
  ) async {
    final repository = _PendingProfileRepository();
    addTearDown(() {
      if (!repository.isCompleted) {
        repository.complete(_profile(username: 'after'));
      }
    });
    final mutationCubit = ProfileMutationCubit(repository: repository);
    final profile = _profile(username: 'before');
    mutationCubit.setAuthenticatedUser(profile.id);

    await _pumpEditorHost(
      tester,
      mutationCubit: mutationCubit,
      profile: profile,
    );

    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    expect(find.text('edit profile'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'save'));
    expect(saveButton().onPressed, isNull);

    await tester.enterText(find.byType(EditableText).last, 'Submitted bio');
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);
    await tester.tap(find.text('save'));
    await tester.pump();

    expect(repository.saveCallCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('open editor'), findsOneWidget);

    await tester.tap(find.text('open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('edit profile'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .controller
          .text,
      'Submitted bio',
    );

    await tester.enterText(find.byType(EditableText).last, 'Later bio');
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .controller
          .text,
      'Later bio',
    );

    repository.complete(_profile(username: 'before', bio: 'Submitted bio'));
    await tester.pumpAndSettle();

    expect(find.text('edit profile'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(saveButton().onPressed, isNotNull);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .controller
          .text,
      'Later bio',
    );
  });
}

Future<void> _pumpEditorHost(
  WidgetTester tester, {
  required ProfileMutationCubit mutationCubit,
  required UserProfile profile,
}) {
  return tester.pumpWidget(
    BlocProvider<ProfileMutationCubit>.value(
      value: mutationCubit,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showProfileEditPage(context, profile: profile),
                child: const Text('open editor'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

UserProfile _profile({required String username, String bio = ''}) {
  final acceptedAt = DateTime.utc(2026);
  return UserProfile(
    id: 'user',
    username: username,
    displayName: 'User',
    birthDate: DateTime(2000),
    bio: bio,
    onboardingCompleted: true,
    termsAcceptedAt: acceptedAt,
    privacyAcceptedAt: acceptedAt,
  );
}

class _PendingProfileRepository implements IProfileRepository {
  final _completer = Completer<UserProfile>();
  int saveCallCount = 0;

  bool get isCompleted => _completer.isCompleted;

  void complete(UserProfile profile) => _completer.complete(profile);

  @override
  Future<UserProfile?> getCachedProfile(String userId) async => null;

  @override
  Future<String?> resolveSharedProfileUsername(String username) async => null;

  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) async =>
      _profile(username: 'before');

  @override
  Future<UserProfile> saveOwnProfile({
    required UserProfile currentProfile,
    required String displayName,
    required DateTime birthDate,
    required ProfileGender gender,
    required String username,
    required String bio,
    required List<ProfilePhoto> photos,
  }) {
    saveCallCount++;
    return _completer.future;
  }
}
