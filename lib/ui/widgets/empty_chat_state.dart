import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class EmptyChatState extends StatelessWidget {
  const EmptyChatState({
    super.key,
    required this.message,
    this.showImage = true,
  });

  final String message;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final messageStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: Theme.of(context).colorScheme.onSurface,
    );

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showImage) ...[
                SvgPicture.asset(
                  'assets/images/empty_chat.svg',
                  width: 214,
                  height: 186,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 20),
              ],
              Text(message, textAlign: TextAlign.center, style: messageStyle),
            ],
          ),
        ),
      ),
    );
  }
}
