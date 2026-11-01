import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';

/// Keeps the primary title's geometry while showing a smaller recovery label.
class ConnectionStatusTitle extends StatelessWidget {
  const ConnectionStatusTitle({
    super.key,
    required this.title,
    this.compact = false,
  });

  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.textScalerOf(
      context,
    ).scale(compact ? PrimaryHeaderGeometry.compactTitleSize : 52),
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
                  style: AppTextStyles.titleLargeFlex.copyWith(
                    fontSize: compact ? 30 : 36,
                  ),
                ),
              )
            : SizedBox(
                key: ValueKey(title),
                width: double.infinity,
                child: _normalTitle(),
              ),
      ),
    ),
  );

  Widget _normalTitle() {
    final text = Text(
      title,
      style: compact
          ? AppTextStyles.titleLargeFlex.copyWith(
              fontSize: PrimaryHeaderGeometry.compactTitleSize,
            )
          : AppTextStyles.titleLargeFlex,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return compact
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: text,
          )
        : text;
  }
}
