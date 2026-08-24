import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/friends/friends.dart';
import 'package:yap_chat/repositories/repositories.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class AddFriendPage extends StatelessWidget {
  const AddFriendPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          FriendSearchCubit(repository: context.read<IFriendsRepository>()),
      child: const _AddFriendView(),
    );
  }
}

class _AddFriendView extends StatelessWidget {
  const _AddFriendView();

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Builder(
        builder: (scaffoldContext) =>
            BlocListener<FriendSearchCubit, FriendSearchState>(
              listenWhen: (previous, current) =>
                  previous.actionError != current.actionError &&
                  current.actionError != null,
              listener: (context, state) {
                showAppSnackBar(
                  scaffoldContext,
                  message: context.l10n.friendsActionFailed,
                  type: SnackBarType.error,
                  bottomMargin: 82,
                );
                context.read<FriendSearchCubit>().clearActionError();
              },
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                extendBodyBehindAppBar: true,
                backgroundColor: context.scaffoldBackgroundColor,
                appBar: PrimaryAppBar(title: context.l10n.friendsAddTitle),
                body: const _AddFriendBody(),
              ),
            ),
      ),
    );
  }
}

class _AddFriendBody extends StatelessWidget {
  const _AddFriendBody();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboard = mediaQuery.viewInsets.bottom;
    const searchSpacing = 16.0;
    const searchHeight = 50.0;
    final searchBottom = keyboard > 0
        ? keyboard + searchSpacing
        : mediaQuery.viewPadding.bottom + searchSpacing;
    final contentBottom = searchBottom + searchHeight + 16;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          top: 130,
          child: _SearchResults(bottomPadding: contentBottom),
        ),
        AnimatedPositioned(
          duration: Duration.zero,
          left: 0,
          right: 0,
          bottom: keyboard > 0 ? keyboard : 0,
          child: const BottomAmbientGlow(),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
          left: 0,
          right: 0,
          bottom: searchBottom,
          child: GlassSearchBar(
            hintText: context.l10n.friendsUserSearchHint,
            onChanged: context.read<FriendSearchCubit>().queryChanged,
          ),
        ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FriendSearchCubit, FriendSearchState>(
      builder: (context, state) {
        switch (state.status) {
          case FriendSearchStatus.initial:
            return Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: EmptyChatState(
                showImage: false,
                message: context.l10n.friendsSearchPrompt,
              ),
            );
          case FriendSearchStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case FriendSearchStatus.failure:
            return Center(child: Text(context.l10n.friendsUserSearchFailed));
          case FriendSearchStatus.success:
            if (state.results.isEmpty) {
              return Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: EmptyChatState(
                  showImage: false,
                  message: context.l10n.friendsNoSearchResults,
                ),
              );
            }
            return ListView.builder(
              padding: EdgeInsets.only(top: 16, bottom: bottomPadding),
              itemCount: state.results.length,
              itemBuilder: (context, index) {
                final candidate = state.results[index];
                return FriendCandidateItem(
                  key: ValueKey(candidate.id),
                  candidate: candidate,
                  friendsLabel: context.l10n.friendsCount,
                  relationshipLabel: (relationship) => switch (relationship) {
                    FriendRelationship.friend =>
                      context.l10n.friendsAlreadyAdded,
                    FriendRelationship.outgoing =>
                      context.l10n.friendsRequestSent,
                    FriendRelationship.incoming =>
                      context.l10n.friendsRequestIncoming,
                    FriendRelationship.none => '',
                  },
                  onAdd: () =>
                      context.read<FriendSearchCubit>().sendRequest(candidate),
                );
              },
            );
        }
      },
    );
  }
}
