import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/ui/ui.dart';

/// The future feed has its own route; opening it performs no background work.
@RoutePage()
class RecommendationsPage extends StatelessWidget {
  const RecommendationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: context.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: PrimaryAppBar(
        compact: true,
        title: context.l10n.recommendationsTitle,
        titleWidget: ConnectionStatusTitle(
          compact: true,
          title: context.l10n.recommendationsTitle,
        ),
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          24 + media.padding.left,
          PrimaryHeaderGeometry.compactHeight,
          24 + media.padding.right,
          FloatingNavigationGeometry.occupiedHeight(media) + 24,
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 48,
                  color: context.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  context.l10n.recommendationsEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
