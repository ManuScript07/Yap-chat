import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class ProfileDaysLabel extends StatelessWidget {
  const ProfileDaysLabel({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.favorite_border_rounded,
        color: context.colorScheme.outline,
        size: 42,
      ),
      const SizedBox(width: 12),
      Text(
        context.l10n.profileDaysWithUs(days),
        style: TextStyle(
          color: context.colorScheme.outline,
          fontSize: 20,
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w500,
          height: 1.20,
          letterSpacing: .50,
        ),
      ),
    ],
  );
}
