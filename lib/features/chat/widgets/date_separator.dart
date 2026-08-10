import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/utils/utils.dart';

class DateSeparator extends StatelessWidget {
  const DateSeparator({
    super.key,
    required this.date,
  });

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final textColor = context.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Center(
        child: Text(
          TimeFormatter.formatDateSeparator(context, date),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            height: 1.25,
            letterSpacing: 0.25,
          ),
        ),
      ),
    );
  }
}