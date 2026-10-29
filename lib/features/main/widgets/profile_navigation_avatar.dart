import 'package:flutter/material.dart';
import 'package:yap_chat/features/profile/data/data.dart';

/// Uses the owner's already hydrated profile; no resolver or subscriptions.
class ProfileNavigationAvatar extends StatefulWidget {
  const ProfileNavigationAvatar({
    super.key,
    required this.photo,
    required this.selected,
    required this.iconColor,
  });

  final ProfilePhoto? photo;
  final bool selected;
  final Color iconColor;

  @override
  State<ProfileNavigationAvatar> createState() =>
      _ProfileNavigationAvatarState();
}

class _ProfileNavigationAvatarState extends State<ProfileNavigationAvatar> {
  late ProfilePhoto? _displayedPhoto = widget.photo;
  bool _hasImageFrame = false;

  @override
  void didUpdateWidget(covariant ProfileNavigationAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final photo = widget.photo;
    if (photo == null) _hasImageFrame = false;
    // An authoritative deletion always wins. Metadata alone must not discard
    // the previous cached photo while the existing profile loader hydrates the
    // replacement. The parent keys this widget by owner to isolate accounts.
    if (photo == null ||
        photo.bytes != null ||
        _displayedPhoto?.bytes == null) {
      _displayedPhoto = photo;
    }
  }

  Widget _fallback() => Icon(
    widget.selected ? Icons.person_rounded : Icons.person_outline_rounded,
    color: widget.iconColor,
    size: 26,
  );

  @override
  Widget build(BuildContext context) {
    final photo = _displayedPhoto;
    // Share the existing own-profile decode/cache key rather than creating a
    // separate full-resolution decode each time the active tab changes.
    final bytes = photo?.bytes;
    final provider = bytes == null
        ? null
        : ResizeImage.resizeIfNeeded(352, null, MemoryImage(bytes));
    if (provider == null) return _fallback();
    return AnimatedContainer(
      key: const ValueKey('profile_navigation_avatar_ring'),
      width: 30,
      height: 30,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.selected ? Colors.white : Colors.transparent,
          width: 1.75,
        ),
      ),
      child: ClipOval(
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (_, child, frame, synchronous) {
            if (synchronous || frame != null) _hasImageFrame = true;
            return _hasImageFrame ? child : _fallback();
          },
          errorBuilder: (_, _, _) {
            _hasImageFrame = false;
            return _fallback();
          },
        ),
      ),
    );
  }
}
