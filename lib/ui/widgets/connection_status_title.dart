import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';

/// Keeps the primary title's geometry while showing a smaller recovery label.
class ConnectionStatusTitle extends StatelessWidget {
  const ConnectionStatusTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.textScalerOf(context).scale(52),
    child: ConnectionStatusBuilder(
      builder: (context, connecting) => AnimatedStatusSwitcher(
        alignment: AlignmentDirectional.centerStart,
        scaleAlignment: AlignmentDirectional.centerStart,
        scaleBegin: .94,
        child: connecting
            ? FittedBox(
                key: const ValueKey('connecting-title'),
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: AnimatedConnectingText(
                  label: context.l10n.connectionConnecting,
                  style: AppTextStyles.titleLargeFlex.copyWith(fontSize: 36),
                ),
              )
            : SizedBox(
                key: ValueKey(title),
                width: double.infinity,
                child: Text(
                  title,
                  style: AppTextStyles.titleLargeFlex,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
      ),
    ),
  );
}
