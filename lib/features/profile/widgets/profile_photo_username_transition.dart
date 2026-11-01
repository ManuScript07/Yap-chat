import 'package:flutter/material.dart';

/// Tracks this profile's gallery independently of route transition compatibility.
/// A Material route does not forward its secondary animation to every custom
/// gallery route, so that animation alone cannot guard the username plaque.
class ProfilePhotoTransitionScope extends StatefulWidget {
  const ProfilePhotoTransitionScope({super.key, required this.builder});
  final WidgetBuilder builder;

  static Future<void> openGallery(
    BuildContext context,
    PageRoute<void> route,
  ) async {
    final owner = context
        .getInheritedWidgetOfExactType<_ProfilePhotoTransitionVisibility>()
        ?.owner;
    if (owner?._galleryOpen.value == true) return;
    owner?._setGalleryOpen(true);
    try {
      Navigator.of(context).push(route);
      // push completes when pop begins; completed waits for the Hero to land.
      await route.completed;
    } finally {
      owner?._setGalleryOpen(false);
    }
  }

  @override
  State<ProfilePhotoTransitionScope> createState() =>
      _ProfilePhotoTransitionScopeState();
}

class _ProfilePhotoTransitionScopeState
    extends State<ProfilePhotoTransitionScope> {
  final _galleryOpen = ValueNotifier(false);

  void _setGalleryOpen(bool value) {
    if (mounted) _galleryOpen.value = value;
  }

  @override
  void dispose() {
    _galleryOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ProfilePhotoTransitionVisibility(
    owner: this,
    child: Builder(builder: widget.builder),
  );
}

class _ProfilePhotoTransitionVisibility
    extends InheritedNotifier<ValueNotifier<bool>> {
  _ProfilePhotoTransitionVisibility({required this.owner, required super.child})
    : super(notifier: owner._galleryOpen);
  final _ProfilePhotoTransitionScopeState owner;
}

/// Only the gallery fades this plaque. Profile route transitions retain their
/// original layering, with the avatar moving beneath the username.
class ProfilePhotoUsernameTransition extends StatelessWidget {
  const ProfilePhotoUsernameTransition({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final galleryOpen =
        context
            .dependOnInheritedWidgetOfExactType<
              _ProfilePhotoTransitionVisibility
            >()
            ?.notifier
            ?.value ??
        false;
    return IgnorePointer(
      ignoring: galleryOpen,
      child: AnimatedOpacity(
        opacity: galleryOpen ? 0 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : galleryOpen
            ? const Duration(milliseconds: 120)
            : const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
        child: child,
      ),
    );
  }
}
