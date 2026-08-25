import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class FriendRequestRejectButton extends StatelessWidget {
  const FriendRequestRejectButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 42,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        iconSize: 26,
        color: context.colorScheme.onSurface,
        icon: const Icon(Icons.close_rounded),
      ),
    );
  }
}
