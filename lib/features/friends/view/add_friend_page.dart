import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class AddFriendPage extends StatelessWidget {
  const AddFriendPage({super.key});

  @override
  Widget build(BuildContext context) => const _AddFriendView();
}

class _AddFriendView extends StatelessWidget {
  const _AddFriendView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      backgroundColor: context.scaffoldBackgroundColor,
      appBar: PrimaryAppBar(title: context.l10n.friendsAddTitle),
      body: const _AddFriendBody(),
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
            enabled: false,
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
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: EmptyChatState(
        showImage: false,
        message: context.l10n.friendsAddTemporarilyUnavailable,
      ),
    );
  }
}
