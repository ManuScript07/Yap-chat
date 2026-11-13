import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/settings/bloc/bloc.dart';
import 'package:yap_chat/features/settings/data/data.dart';
import 'package:yap_chat/repositories/app_content/abstract_app_public_content_repository.dart';

void main() {
  test(
    'exposes cached links while refreshing the stale Storage manifest',
    () async {
      const cached = AppPublicContent(termsUrlRu: 'https://old.example/terms');
      const refreshed = AppPublicContent(
        termsUrlRu: 'https://new.example/terms',
      );
      final cubit = AppPublicContentCubit(
        repository: _PublicContentRepository(
          cached: CachedAppPublicContent(
            content: cached,
            fetchedAt: DateTime.now().toUtc().subtract(
              const Duration(hours: 7),
            ),
          ),
          refreshed: refreshed,
        ),
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.content, refreshed);
      expect(cubit.state.isLoading, isFalse);
    },
  );

  test('coalesces concurrent loads into one remote request', () async {
    final refresh = Completer<AppPublicContent?>();
    final repository = _PublicContentRepository(refreshFuture: refresh.future);
    final cubit = AppPublicContentCubit(repository: repository);
    addTearDown(cubit.close);

    final first = cubit.load();
    final second = cubit.ensureContent();
    await Future<void>.delayed(Duration.zero);
    expect(repository.refreshCalls, 1);

    refresh.complete(const AppPublicContent(telegramUrl: 'https://t.me/yap'));
    await first;
    await second;
    expect(cubit.state.content?.telegramUrl, 'https://t.me/yap');
  });

  test('does not contact Storage while the six-hour cache is fresh', () async {
    final repository = _PublicContentRepository(
      cached: CachedAppPublicContent(
        content: const AppPublicContent(telegramUrl: 'https://t.me/yap'),
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
    final cubit = AppPublicContentCubit(repository: repository);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.content?.telegramUrl, 'https://t.me/yap');
    expect(repository.refreshCalls, 0);
    expect(cubit.state.isLoading, isFalse);
  });

  test('keeps an optional GitHub link from the public manifest', () {
    const url = 'https://github.com/yap-chat/yap-chat';

    final content = AppPublicContent.fromJson({'githubUrl': url});

    expect(content.githubUrl, url);
  });
}

class _PublicContentRepository implements IAppPublicContentRepository {
  _PublicContentRepository({this.cached, this.refreshed, this.refreshFuture});

  final CachedAppPublicContent? cached;
  final AppPublicContent? refreshed;
  final Future<AppPublicContent?>? refreshFuture;
  int refreshCalls = 0;

  @override
  Future<CachedAppPublicContent?> readCached() async => cached;

  @override
  Future<AppPublicContent?> refresh() {
    refreshCalls++;
    return refreshFuture ?? Future.value(refreshed);
  }
}
