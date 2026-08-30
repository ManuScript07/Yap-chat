import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/bloc/bloc.dart';
import 'package:yap_chat/features/friends/data/data.dart';
import 'package:yap_chat/features/friends/widgets/widgets.dart';
import 'package:yap_chat/features/profile/view/view.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class AddFriendByUsernamePage extends StatelessWidget {
  const AddFriendByUsernamePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          FriendSearchCubit(repository: context.read<IFriendsRepository>()),
      child: const _AddFriendByUsernameView(),
    );
  }
}

class _AddFriendByUsernameView extends StatefulWidget {
  const _AddFriendByUsernameView();

  @override
  State<_AddFriendByUsernameView> createState() =>
      _AddFriendByUsernameViewState();
}

class _AddFriendByUsernameViewState extends State<_AddFriendByUsernameView> {
  final _usernameController = TextEditingController();
  String? _submittedUsername;
  FriendCandidate? _localFriendCandidate;
  var _localSearchGeneration = 0;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FriendSearchCubit, FriendSearchState>(
      listenWhen: (previous, current) =>
          previous.actionError != current.actionError &&
          current.actionError != null,
      listener: (context, state) {
        showAppSnackBar(
          context,
          message: context.l10n.friendsActionFailed,
          type: SnackBarType.error,
        );
        context.read<FriendSearchCubit>().clearActionError();
      },
      child: KeyboardDismissPopScope(
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: context.scaffoldBackgroundColor,
          appBar: PrimaryAppBar(
            title: context.l10n.friendsAddByUsernameTitle,
            titleWidget: Text(
              context.l10n.friendsAddByUsernameTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLargeFlex.copyWith(fontSize: 32),
            ),
          ),
          body: _UsernameSearchBody(
            controller: _usernameController,
            submittedUsername: _submittedUsername,
            localFriendCandidate: _localFriendCandidate,
            onChanged: _onUsernameChanged,
            onSubmitted: _submitSearch,
          ),
        ),
      ),
    );
  }

  void _onUsernameChanged(String value) {
    final normalized = _normalizedUsername(value);
    setState(() {
      if (_submittedUsername != null && normalized != _submittedUsername) {
        _submittedUsername = null;
        _localFriendCandidate = null;
        _localSearchGeneration++;
      }
    });
  }

  void _submitSearch() {
    final value = _usernameController.text;
    final normalized = _normalizedUsername(value);
    if (!_isValidUsername(value)) return;

    FocusManager.instance.primaryFocus?.unfocus();
    final generation = ++_localSearchGeneration;
    setState(() {
      _submittedUsername = normalized;
      _localFriendCandidate = null;
    });
    context.read<FriendSearchCubit>().queryChanged('@$normalized');
    unawaited(_findLocalFriend(normalized, generation));
  }

  Future<void> _findLocalFriend(String username, int generation) async {
    try {
      final friends = await context
          .read<IFriendsRepository>()
          .watchFriends()
          .first;
      if (!mounted ||
          generation != _localSearchGeneration ||
          username != _submittedUsername) {
        return;
      }
      Friend? match;
      for (final friend in friends) {
        if (friend.username.toLowerCase() == username) {
          match = friend;
          break;
        }
      }
      final localFriend = match;
      if (localFriend == null) return;
      setState(() {
        _localFriendCandidate = FriendCandidate(
          id: localFriend.id,
          username: localFriend.username,
          displayName: localFriend.displayName,
          avatarUrl: localFriend.avatarUrl,
          avatarStoragePath: localFriend.avatarStoragePath,
          relationship: FriendRelationship.friend,
        );
      });
    } catch (_) {
      // Ошибка локального кэша не должна прерывать существующий поиск по сети.
    }
  }
}

class _UsernameSearchBody extends StatelessWidget {
  const _UsernameSearchBody({
    required this.controller,
    required this.submittedUsername,
    required this.localFriendCandidate,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String? submittedUsername;
  final FriendCandidate? localFriendCandidate;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = math.max(16.0, (constraints.maxWidth - 560) / 2);
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontal + systemPadding.left,
                  130,
                  horizontal + systemPadding.right,
                  systemPadding.bottom + 24,
                ),
                child: BlocBuilder<FriendSearchCubit, FriendSearchState>(
                  builder: (context, state) {
                    final viewState = _UsernameSearchViewState.from(
                      state: state,
                      submittedUsername: submittedUsername,
                      localFriendCandidate: localFriendCandidate,
                    );
                    final isValid = _isValidUsername(controller.text);
                    final isSearching =
                        state.status == FriendSearchStatus.loading;
                    final isLoading =
                        isSearching && viewState.candidate == null;
                    final searchError = switch (viewState.message) {
                      _UsernameSearchMessage.failure =>
                        context.l10n.friendsUserSearchFailed,
                      _UsernameSearchMessage.notFound =>
                        context.l10n.friendsUsernameNotFound,
                      null => null,
                    };
                    final errorText =
                        _hasInvalidUsernameCharacters(controller.text)
                        ? context.l10n.friendsUsernameCharactersOnly
                        : searchError;
                    return Column(
                      children: [
                        const Spacer(flex: 4),
                        OnboardingTextField(
                          controller: controller,
                          label: context.l10n.friendsUsernameLabel,
                          hint: context.l10n.friendsUsernameHint,
                          maxLength: _maximumUsernameLength,
                          maxLines: 1,
                          tooLongText: context.l10n.friendsUsernameTooLong,
                          errorText: errorText,
                          textInputAction: TextInputAction.search,
                          autocorrect: false,
                          lengthResolver: (value) =>
                              _normalizedUsername(value).length,
                          onChanged: onChanged,
                          onSubmitted: (_) => onSubmitted(),
                        ),
                        const SizedBox(height: 16),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: isLoading
                                ? const Padding(
                                    key: ValueKey('username-search-loading'),
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                  )
                                : switch (viewState) {
                                    _UsernameSearchViewState(
                                      candidate: final candidate?,
                                    ) =>
                                      FriendCandidateItem(
                                        key: ValueKey(
                                          'username:${candidate.id}',
                                        ),
                                        candidate: candidate,
                                        friendsLabel: context.l10n.friendsCount,
                                        relationshipLabel: (relationship) =>
                                            switch (relationship) {
                                              FriendRelationship.friend =>
                                                context
                                                    .l10n
                                                    .friendsAlreadyAdded,
                                              FriendRelationship.outgoing =>
                                                context.l10n.friendsRequestSent,
                                              FriendRelationship.incoming =>
                                                context
                                                    .l10n
                                                    .friendsRequestIncoming,
                                              FriendRelationship.none => '',
                                            },
                                        avatarLoader: () => context
                                            .read<IFriendsRepository>()
                                            .resolveCandidateAvatar(candidate),
                                        respectSystemPadding: false,
                                        onTap: () => openViewedProfile(
                                          context,
                                          userId: candidate.id,
                                        ),
                                        onAdd: () => context
                                            .read<FriendSearchCubit>()
                                            .sendRequest(candidate),
                                        onAccept: () => context
                                            .read<FriendSearchCubit>()
                                            .respondToIncoming(
                                              candidate,
                                              accept: true,
                                            ),
                                        onReject: () => context
                                            .read<FriendSearchCubit>()
                                            .respondToIncoming(
                                              candidate,
                                              accept: false,
                                            ),
                                      ),
                                    _ => const SizedBox(
                                      key: ValueKey('username-search-idle'),
                                    ),
                                  },
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: FilledButton(
                            onPressed: isValid && !isSearching
                                ? onSubmitted
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: context.colorScheme.primary,
                              foregroundColor: context.colorScheme.onPrimary,
                              disabledBackgroundColor: context
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.35),
                              disabledForegroundColor: context
                                  .colorScheme
                                  .onPrimary
                                  .withValues(alpha: 0.6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(21),
                              ),
                              textStyle: context.textTheme.labelLarge?.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            child: Text(context.l10n.friendsUsernameSearch),
                          ),
                        ),
                        const Spacer(flex: 5),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UsernameSearchViewState {
  const _UsernameSearchViewState({this.message, this.candidate});

  final _UsernameSearchMessage? message;
  final FriendCandidate? candidate;

  factory _UsernameSearchViewState.from({
    required FriendSearchState state,
    required String? submittedUsername,
    required FriendCandidate? localFriendCandidate,
  }) {
    final isCurrentSearch =
        submittedUsername != null &&
        _normalizedUsername(state.query) == submittedUsername;
    if (!isCurrentSearch) return const _UsernameSearchViewState();
    if (localFriendCandidate != null) {
      return _UsernameSearchViewState(candidate: localFriendCandidate);
    }
    if (state.status == FriendSearchStatus.failure) {
      return const _UsernameSearchViewState(
        message: _UsernameSearchMessage.failure,
      );
    }
    if (state.status != FriendSearchStatus.success) {
      return const _UsernameSearchViewState();
    }
    for (final candidate in state.results) {
      if (_normalizedUsername(candidate.username) == submittedUsername) {
        return _UsernameSearchViewState(candidate: candidate);
      }
    }
    return const _UsernameSearchViewState(
      message: _UsernameSearchMessage.notFound,
    );
  }
}

enum _UsernameSearchMessage { failure, notFound }

const _maximumUsernameLength = 24;

bool _isValidUsername(String username) =>
    RegExp(r'^@?[a-z0-9_]{3,24}$').hasMatch(username.toLowerCase());

bool _hasInvalidUsernameCharacters(String value) {
  return value.isNotEmpty &&
      !RegExp(r'^@?[a-z0-9_]*$').hasMatch(value.toLowerCase());
}

String _normalizedUsername(String value) {
  final normalized = value.toLowerCase();
  return normalized.startsWith('@') ? normalized.substring(1) : normalized;
}
