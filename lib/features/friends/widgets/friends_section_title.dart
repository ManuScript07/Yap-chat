import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class FriendsSectionTitle extends StatelessWidget {
  const FriendsSectionTitle({
    super.key,
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final systemPadding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16 + systemPadding.left,
        right: 16 + systemPadding.right,
        top: 18,
        bottom: 8,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: title),
            TextSpan(
              text: ' $count',
              style: TextStyle(color: context.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        style: context.textTheme.headlineSmall?.copyWith(
          color: context.colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
