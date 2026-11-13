import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/features/profile/data/data.dart';
import 'package:yap_chat/l10n/app_localizations.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/widgets/onboarding_text_field.dart';

const _userId = 'fixture-user';
UserProfile _profile(DateTime? birthDate) => UserProfile(
  id: _userId,
  username: 'fixture_user',
  displayName: 'Fixture',
  birthDate: birthDate,
  onboardingCompleted: false,
);

class _Auth implements IAuthRepository {
  @override
  Future<AuthAccountAccess?> getCachedAccountAccess(String userId) async =>
      null;
  @override
  Future<AuthAccountAccess> getAccountAccess() async =>
      const AuthAccountAccess(isBanned: false);
  @override
  Future<void> cacheAccountAccess(
    String userId,
    AuthAccountAccess access,
  ) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements IProfileRepository {
  _Profiles(this.cached);
  final UserProfile cached;
  final response = Completer<UserProfile>();
  int fetches = 0;
  @override
  Future<UserProfile?> getCachedProfile(String userId) async => cached;
  @override
  Future<UserProfile> getOrCreateProfile(AuthSession session) {
    fetches++;
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<({AuthBloc bloc, _Profiles profiles})> open(
    WidgetTester tester, {
    DateTime? cachedDate,
    DateTime? sessionDate,
  }) async {
    final host = (await tester.runAsync(() async {
      final profiles = _Profiles(_profile(cachedDate));
      final bloc = AuthBloc(
        authRepository: _Auth(),
        profileRepository: profiles,
      );
      final cached = bloc.stream.firstWhere(
        (state) => state.status == AuthStatus.profileIncomplete,
      );
      bloc.add(
        AuthSessionChanged(
          AuthSession(userId: _userId, birthDate: sessionDate),
        ),
      );
      await cached;
      return (bloc: bloc, profiles: profiles);
    }))!;
    final profiles = host.profiles;
    final bloc = host.bloc;
    addTearDown(() async {
      if (!profiles.response.isCompleted) {
        profiles.response.complete(profiles.cached);
      }
      await tester.runAsync(bloc.close);
    });
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          theme: ThemeData.dark(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileSetupPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    return (bloc: bloc, profiles: profiles);
  }

  void expectDate(WidgetTester tester, DateTime? date) {
    final fields = tester.widget<OnboardingBirthDateFields>(
      find.byType(OnboardingBirthDateFields, skipOffstage: false),
    );
    expect(
      fields.dayController.text,
      date?.day.toString().padLeft(2, '0') ?? '',
    );
    expect(
      fields.monthController.text,
      date?.month.toString().padLeft(2, '0') ?? '',
    );
    expect(fields.yearController.text, date?.year.toString() ?? '');
    expect(tester.takeException(), isNull);
  }

  Future<void> completeProfile(
    WidgetTester tester,
    ({AuthBloc bloc, _Profiles profiles}) host,
    DateTime? date,
  ) async {
    await tester.runAsync(() async {
      host.profiles.response.complete(_profile(date));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(host.bloc.state.profile?.birthDate, date);
  }

  testWidgets('initial profile date takes priority over Yandex date', (
    tester,
  ) async {
    await open(
      tester,
      cachedDate: DateTime(2000, 2, 29),
      sessionDate: DateTime(2007, 2, 28),
    );
    expectDate(tester, DateTime(2000, 2, 29));
  });

  testWidgets('uses session date while the profile is incomplete', (
    tester,
  ) async {
    await open(tester, sessionDate: DateTime(2007, 2, 28));
    expectDate(tester, DateTime(2007, 2, 28));
  });

  testWidgets(
    'late server profile fills empty date fields without refetching',
    (tester) async {
      final host = await open(tester);
      expectDate(tester, null);
      await completeProfile(tester, host, DateTime(2007, 2, 28));
      expectDate(tester, DateTime(2007, 2, 28));
      expect(host.profiles.fetches, 1);
      expect(host.bloc.state.status, AuthStatus.profileIncomplete);
    },
  );

  testWidgets('late profile supersedes untouched session prefill', (
    tester,
  ) async {
    final host = await open(tester, sessionDate: DateTime(2007, 2, 28));
    await completeProfile(tester, host, DateTime(2000, 2, 29));
    expectDate(tester, DateTime(2000, 2, 29));
  });

  testWidgets('late session metadata fills an untouched empty date', (
    tester,
  ) async {
    final host = await open(tester);
    await completeProfile(tester, host, null);
    await tester.runAsync(() async {
      host.bloc.add(
        AuthSessionChanged(
          AuthSession(userId: _userId, birthDate: DateTime(2007, 2, 28)),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expectDate(tester, DateTime(2007, 2, 28));
  });

  for (final editedDay in ['15', '']) {
    testWidgets(
      'late profile preserves user edit "$editedDay", including clearing a field',
      (tester) async {
        final host = await open(tester, sessionDate: DateTime(2007, 2, 28));
        final fields = tester.widget<OnboardingBirthDateFields>(
          find.byType(OnboardingBirthDateFields),
        );
        final dayField = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.controller == fields.dayController,
        );
        await tester.enterText(dayField, editedDay);
        await completeProfile(tester, host, DateTime(2000, 2, 29));
        expect(fields.dayController.text, editedDay);
        expect(fields.monthController.text, '02');
        expect(fields.yearController.text, '2007');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
